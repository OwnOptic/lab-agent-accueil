#requires -Version 7
<#
.SYNOPSIS
    Prépare le terrain SharePoint de l'agent d'accueil du lab « Construisons un agent ensemble » :
    le site, la liste « Arrivées » et les documents des ressources humaines de Contoso (entreprise fictive).

.DESCRIPTION
    Crée ou réutilise, sans doublon (le script peut être relancé autant de fois que nécessaire) :
      - le site « Contoso - Ressources humaines » (adresse /sites/contoso-rh), ou le site que vous indiquez ;
      - la liste « Arrivées » avec les colonnes et les noms internes qu'utilisent le lab et le fichier de contexte :
        Title (affiché « Nom complet »), Email, Poste, DateArrivee (date sans heure), Manager et Parrain (personnes),
        MaterielRemis (choix Non ou Oui) ;
      - deux arrivées passées, pour que la liste ne soit pas vide ;
      - les 5 documents du zip dans la bibliothèque Documents, et la politique de 2021 dans un dossier « Archives »
        (c'est le piège de l'étape 4 : gardez-la).

    Il passe par Microsoft Graph, avec le module Microsoft Graph PowerShell et une connexion interactive.
    Quand Microsoft limite le débit des appels, le script attend et réessaie tout seul.

.PARAMETER HoteSharePoint
    L'hôte SharePoint de votre tenant de test, par exemple contoso.sharepoint.com.

.PARAMETER SiteUrl
    Facultatif : l'adresse d'un site existant à utiliser, par exemple https://contoso.sharepoint.com/sites/contoso-rh.
    Sans ce paramètre, le script crée (ou retrouve) le site /sites/contoso-rh.

.PARAMETER Zip
    Le zip des documents. Par défaut : documents-contoso.zip, à côté du script.

.PARAMETER TenantId
    Facultatif : l'identifiant ou le domaine de votre tenant de test, pour ne pas vous connecter ailleurs par erreur.

.EXAMPLE
    pwsh -File .\sharepoint-setup.ps1 -HoteSharePoint contoso.sharepoint.com
#>
param(
    [Parameter(Mandatory)] [string] $HoteSharePoint,
    [string] $SiteUrl,
    [string] $Zip = (Join-Path $PSScriptRoot 'documents-contoso.zip'),
    [string] $TenantId
)

$ErrorActionPreference = 'Stop'
$HoteSharePoint = $HoteSharePoint -replace '^https?://', '' -replace '/.*$', ''
$Alias = 'contoso-rh'
$NomSite = 'Contoso - Ressources humaines'

if (-not (Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
    Write-Host "Le module Microsoft Graph PowerShell manque. Installez-le une fois avec :" -ForegroundColor Yellow
    Write-Host "  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    exit 1
}
if (-not (Test-Path $Zip)) { throw "Zip introuvable : $Zip. Téléchargez documents-contoso.zip depuis le lab, à côté de ce script." }
Import-Module Microsoft.Graph.Authentication

# ---------- Connexion ----------
$Scopes = @('Sites.FullControl.All', 'Sites.ReadWrite.All')
if (-not $SiteUrl) { $Scopes += 'Group.ReadWrite.All' }
try { Set-MgGraphOption -DisableLoginByWAM $true } catch { }
$connexion = @{ Scopes = $Scopes; NoWelcome = $true }
if ($TenantId) { $connexion.TenantId = $TenantId }
Connect-MgGraph @connexion
$Moi = (Get-MgContext).Account
Write-Host "Connecté : $Moi" -ForegroundColor Cyan

# Appel Graph avec nouvelle tentative quand Microsoft limite le débit (429) ou qu'un service est indisponible.
function Invoke-Graph {
    param([string] $Method, [string] $Uri, $Body, [string] $InputFilePath, [string] $ContentType = 'application/json')
    for ($essai = 1; ; $essai++) {
        try {
            $p = @{ Method = $Method; Uri = $Uri }
            if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10); $p.ContentType = $ContentType }
            if ($InputFilePath) { $p.InputFilePath = $InputFilePath; $p.ContentType = $ContentType }
            return Invoke-MgGraphRequest @p
        } catch {
            $code = 0
            try { $code = [int]$_.Exception.Response.StatusCode } catch { }
            if ($code -in 429, 502, 503, 504 -and $essai -lt 8) {
                $attente = [math]::Min(5 * $essai, 30)
                Write-Host "  Microsoft demande de ralentir ($code), nouvel essai dans $attente secondes..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds $attente; continue
            }
            throw
        }
    }
}
$G = 'https://graph.microsoft.com/v1.0'

# ---------- Le site ----------
if ($SiteUrl) {
    $u = [uri]$SiteUrl
    $site = Invoke-Graph GET "$G/sites/$($u.Host):$($u.AbsolutePath.TrimEnd('/'))"
    Write-Host "Site utilisé : $($site.webUrl)"
} else {
    $site = $null
    try { $site = Invoke-Graph GET "$G/sites/${HoteSharePoint}:/sites/$Alias" } catch { }
    if ($site) {
        Write-Host "Site déjà présent : $($site.webUrl)"
    } else {
        $groupe = @((Invoke-Graph GET "$G/groups?`$filter=mailNickname eq '$Alias'&`$select=id").value) | Select-Object -First 1
        if (-not $groupe) {
            Write-Host "Création du site « $NomSite » (un groupe Microsoft 365 et son site d'équipe)..."
            $moiId = (Invoke-Graph GET "$G/me?`$select=id").id
            $groupe = Invoke-Graph POST "$G/groups" @{
                displayName = $NomSite; mailNickname = $Alias; mailEnabled = $true; securityEnabled = $false
                groupTypes = @('Unified'); visibility = 'Private'
                description = "Site des ressources humaines de Contoso Lyon (données fictives du lab)"
                'owners@odata.bind' = @("$G/users/$moiId"); 'members@odata.bind' = @("$G/users/$moiId")
            }
        }
        Write-Host "Attente du site SharePoint (une à trois minutes la première fois)..."
        for ($i = 1; $i -le 30 -and -not $site; $i++) {
            try { $site = Invoke-Graph GET "$G/groups/$($groupe.id)/sites/root" } catch { Start-Sleep -Seconds 10 }
        }
        if (-not $site) { throw "Le site n'est pas encore prêt. Relancez le script dans quelques minutes : il reprendra où il s'est arrêté." }
        Write-Host "Site prêt : $($site.webUrl)"
    }
}
$S = "$G/sites/$($site.id)"

# ---------- La liste « Arrivées » ----------
$liste = @((Invoke-Graph GET "$S/lists?`$select=id,displayName,webUrl").value) | Where-Object { $_.displayName -eq 'Arrivées' } | Select-Object -First 1
if (-not $liste) {
    $liste = Invoke-Graph POST "$S/lists" @{
        displayName = 'Arrivées'
        description = "Nouveaux collaborateurs de l'agence de Lyon"
        list        = @{ template = 'genericList' }
        columns     = @(
            @{ name = 'Email'; displayName = 'E-mail'; text = @{} }
            @{ name = 'Poste'; displayName = 'Poste'; text = @{} }
            @{ name = 'DateArrivee'; displayName = "Date d'arrivée"; dateTime = @{ format = 'dateOnly' } }
            @{ name = 'Manager'; displayName = 'Manager'; personOrGroup = @{ allowMultipleSelection = $false; chooseFromType = 'peopleOnly' } }
            @{ name = 'Parrain'; displayName = 'Parrain ou marraine'; personOrGroup = @{ allowMultipleSelection = $false; chooseFromType = 'peopleOnly' } }
            @{ name = 'MaterielRemis'; displayName = 'Matériel remis'; choice = @{ allowTextEntry = $false; choices = @('Non', 'Oui'); displayAs = 'dropDownMenu' }; defaultValue = @{ value = 'Non' } }
        )
    }
    Write-Host "Liste « Arrivées » créée"
} else {
    Write-Host "Liste « Arrivées » déjà présente"
}
$colTitre = @((Invoke-Graph GET "$S/lists/$($liste.id)/columns?`$select=id,name,displayName").value) | Where-Object { $_.name -eq 'Title' }
if ($colTitre -and $colTitre.displayName -ne 'Nom complet') {
    Invoke-Graph PATCH "$S/lists/$($liste.id)/columns/$($colTitre.id)" @{ displayName = 'Nom complet' } | Out-Null
}

# Les colonnes « personne » prennent l'identifiant de l'utilisateur dans le site.
$infos = @((Invoke-Graph GET "$S/lists('User Information List')/items?`$expand=fields(`$select=EMail)&`$top=500").value)
$moiLookup = ($infos | Where-Object { $_.fields.EMail -eq $Moi } | Select-Object -First 1).id

$exemples = @(
    @{ Title = 'Hugo Bernard'; Poste = 'Développeur Power Platform'; DateArrivee = (Get-Date).AddDays(-14).ToString('yyyy-MM-dd'); MaterielRemis = 'Oui' },
    @{ Title = 'Inès Moreau'; Poste = 'Chargée de recrutement'; DateArrivee = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd'); MaterielRemis = 'Oui' }
)
$lignes = @((Invoke-Graph GET "$S/lists/$($liste.id)/items?`$expand=fields(`$select=Title,ManagerLookupId)&`$top=200").value)
foreach ($e in $exemples) {
    $champs = @{ Title = $e.Title; Email = $Moi; Poste = $e.Poste; DateArrivee = $e.DateArrivee; MaterielRemis = $e.MaterielRemis }
    if ($moiLookup) { $champs.ManagerLookupId = [int]$moiLookup; $champs.ParrainLookupId = [int]$moiLookup }
    $ligne = $lignes | Where-Object { $_.fields.Title -eq $e.Title } | Select-Object -First 1
    if (-not $ligne) {
        Invoke-Graph POST "$S/lists/$($liste.id)/items" @{ fields = $champs } | Out-Null
        Write-Host "Arrivée ajoutée : $($e.Title)"
    } elseif ($moiLookup -and -not $ligne.fields.ManagerLookupId) {
        Invoke-Graph PATCH "$S/lists/$($liste.id)/items/$($ligne.id)/fields" @{ ManagerLookupId = [int]$moiLookup; ParrainLookupId = [int]$moiLookup } | Out-Null
        Write-Host "Manager et parrain complétés : $($e.Title)"
    } else {
        Write-Host "Arrivée déjà présente : $($e.Title)"
    }
}
if (-not $moiLookup) {
    Write-Host "Votre compte n'est pas encore connu du site : les deux arrivées n'ont pas de manager." -ForegroundColor Yellow
    Write-Host "  Ouvrez une fois le site dans le navigateur, puis relancez le script : il complétera le manager et le parrain."
}

# ---------- Les documents ----------
$dossier = Join-Path ([System.IO.Path]::GetTempPath()) ("contoso-docs-" + [guid]::NewGuid().ToString('N'))
Expand-Archive -Path $Zip -DestinationPath $dossier
$fichiers = Get-ChildItem $dossier -Recurse -File -Filter *.pdf
foreach ($f in $fichiers) {
    $relatif = $f.FullName.Substring($dossier.Length).TrimStart('\', '/') -replace '\\', '/'
    $chemin = ($relatif -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    Invoke-Graph PUT "$S/drive/root:/${chemin}:/content" -InputFilePath $f.FullName -ContentType 'application/pdf' | Out-Null
    Write-Host "Document déposé : $relatif"
}

Write-Host ""
Write-Host "Terrain prêt." -ForegroundColor Green
Write-Host "  Site      : $($site.webUrl)"
Write-Host "  Liste     : $($site.webUrl)/Lists/Arrivees (ou « Arrivées » dans le contenu du site)"
Write-Host "  Documents : $($fichiers.Count) fichiers, dont Archives/politique-teletravail-2021.pdf"
