#requires -Version 7
<#
.SYNOPSIS
    Prépare une instance de développement ServiceNow pour le lab « Construisons un agent ensemble » :
    les données fictives de Contoso (Lyon), en français.

.DESCRIPTION
    Crée ou met à jour, sans doublon (le script peut être relancé autant de fois que nécessaire) :
      - 8 collaborateurs fictifs (adresses @contoso.example) ;
      - 15 incidents, marqués correlation_id = contoso-seed ;
      - la base de connaissances « Contoso - Support informatique » et ses 9 articles publiés ;
      - la catégorie « Arrivées et matériel » du catalogue de services et ses 4 articles ;
      - l'utilisateur d'intégration copilot.studio (réservé aux appels d'API, sans mot de passe), que la
        connexion Power Platform utilisera. Définissez son mot de passe dans ServiceNow ensuite.

    Il passe par l'API Table de ServiceNow avec une authentification de base (nom d'utilisateur et mot de
    passe d'un administrateur de l'instance). Les instances de développement renvoient parfois des
    erreurs 500 passagères : le script réessaie tout seul.

.PARAMETER Instance
    Le nom de votre instance, par exemple dev12345 (sans .service-now.com). L'adresse complète marche aussi.

.PARAMETER Utilisateur
    Un administrateur de l'instance. Par défaut : admin.

.PARAMETER MotDePasse
    Son mot de passe. S'il est omis, le script le demande sans l'afficher.

.PARAMETER MonEmail
    Facultatif : votre adresse e-mail Microsoft 365 de test. Elle est donnée à Camille Martin, pour que
    l'agent retrouve « vos » incidents quand vous lui demandez où en sont vos demandes.

.EXAMPLE
    pwsh -File .\servicenow-seed.ps1 -Instance dev12345 -MonEmail vous@votre-tenant.onmicrosoft.com
#>
param(
    [Parameter(Mandatory)] [string] $Instance,
    [string] $Utilisateur = 'admin',
    [securestring] $MotDePasse,
    [string] $MonEmail
)

$ErrorActionPreference = 'Stop'
$Instance = $Instance -replace '^https?://', '' -replace '\.service-now\.com.*$', '' -replace '/.*$', ''
$Base = "https://$Instance.service-now.com/api/now/table"
if (-not $MotDePasse) { $MotDePasse = Read-Host "Mot de passe de $Utilisateur sur $Instance" -AsSecureString }
$Cred = [pscredential]::new($Utilisateur, $MotDePasse)

function Invoke-Sn {
    param([string] $Method, [string] $Table, [string] $Id, [hashtable] $Query, $Body)
    $uri = "$Base/$Table" + ($(if ($Id) { "/$Id" } else { '' }))
    if ($Query) {
        $uri += '?' + (($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }) -join '&')
    }
    $params = @{ Method = $Method; Uri = $uri; Authentication = 'Basic'; Credential = $Cred; Headers = @{ Accept = 'application/json' } }
    if ($null -ne $Body) {
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10 -Compress))
        $params.ContentType = 'application/json; charset=utf-8'
    }
    for ($essai = 1; ; $essai++) {
        try { return (Invoke-RestMethod @params).result }
        catch {
            $code = [int]($_.Exception.Response.StatusCode)
            if ($code -in 500, 502, 503, 504 -and $essai -lt 10) { Start-Sleep -Seconds ([math]::Min(3 * $essai, 20)); continue }
            if ($code -eq 401) { throw "ServiceNow refuse la connexion (401) : vérifiez le nom de l'instance, l'utilisateur et le mot de passe. Si une politique d'accès protège l'API Table, elle doit accepter l'authentification de base." }
            throw
        }
    }
}

function Get-Sn([string] $Table, [string] $Filtre, [string] $Champs = 'sys_id', [int] $Max = 100) {
    @(Invoke-Sn GET $Table -Query @{ sysparm_query = $Filtre; sysparm_fields = $Champs; sysparm_limit = $Max })
}

# Crée l'enregistrement, ou le met à jour s'il existe déjà (repéré par $Filtre). Renvoie son sys_id.
function Sync-Sn([string] $Table, [string] $Filtre, [hashtable] $Valeurs) {
    $existant = Get-Sn $Table $Filtre 'sys_id' 1
    if ($existant.Count) { return (Invoke-Sn PATCH $Table -Id $existant[0].sys_id -Body $Valeurs).sys_id }
    return (Invoke-Sn POST $Table -Body $Valeurs).sys_id
}

Write-Host "Instance : https://$Instance.service-now.com" -ForegroundColor Cyan

# ---------- Collaborateurs ----------
$Dom = 'contoso.example'
$Collaborateurs = @(
    @('camille.martin', 'Camille', 'Martin', 'Chargée de projets marketing'),
    @('thomas.leroy', 'Thomas', 'Leroy', 'Responsable marketing'),
    @('sophie.durand', 'Sophie', 'Durand', 'Responsable des ressources humaines'),
    @('karim.benali', 'Karim', 'Benali', 'Technicien support informatique'),
    @('julie.moreau', 'Julie', 'Moreau', 'Comptable'),
    @('lucas.bernard', 'Lucas', 'Bernard', 'Commercial grands comptes'),
    @('ines.garcia', 'Inès', 'Garcia', 'Assistante de direction'),
    @('antoine.petit', 'Antoine', 'Petit', 'Développeur')
)
$U = @{}
foreach ($c in $Collaborateurs) {
    $U[$c[0]] = Sync-Sn 'sys_user' "user_name=$($c[0])" @{
        user_name = $c[0]; first_name = $c[1]; last_name = $c[2]; title = $c[3]; email = "$($c[0])@$Dom"
        city = 'Lyon'; active = 'true'; preferred_language = 'fr'
    }
}
Invoke-Sn PATCH 'sys_user' -Id $U['camille.martin'] -Body @{ manager = $U['thomas.leroy'] } | Out-Null
if ($MonEmail) {
    Invoke-Sn PATCH 'sys_user' -Id $U['camille.martin'] -Body @{ email = $MonEmail } | Out-Null
    Write-Host "Camille Martin porte maintenant votre adresse : $MonEmail"
}

$Groupes = @{}
foreach ($g in Get-Sn 'sys_user_group' 'nameINService Desk,Hardware,Software,Network,Database,IT Securities' 'name,sys_id') { $Groupes[$g.name] = $g.sys_id }
$Roles = @{}
foreach ($r in Get-Sn 'sys_user_role' 'nameINitil,knowledge,catalog' 'name,sys_id') { $Roles[$r.name] = $r.sys_id }

function Add-Role([string] $UserId, [string] $Role) {
    if ($Roles[$Role] -and -not (Get-Sn 'sys_user_has_role' "user=$UserId^role=$($Roles[$Role])").Count) {
        Invoke-Sn POST 'sys_user_has_role' -Body @{ user = $UserId; role = $Roles[$Role] } | Out-Null
    }
}
Add-Role $U['karim.benali'] 'itil'
if ($Groupes['Service Desk'] -and -not (Get-Sn 'sys_user_grmember' "user=$($U['karim.benali'])^group=$($Groupes['Service Desk'])").Count) {
    Invoke-Sn POST 'sys_user_grmember' -Body @{ user = $U['karim.benali']; group = $Groupes['Service Desk'] } | Out-Null
}
Write-Host "Collaborateurs : $($U.Count)"

# ---------- Utilisateur d'intégration pour Power Platform ----------
# Un compte réservé aux appels d'API : ServiceNow refuse désormais l'authentification de base pour un
# utilisateur qui peut aussi se connecter au site (« denied basic-auth API call for interactive-login user »).
$Integ = Sync-Sn 'sys_user' 'user_name=copilot.studio' @{
    user_name = 'copilot.studio'; first_name = 'Copilot'; last_name = 'Studio'; title = "Compte d'intégration Power Platform"
    email = "copilot.studio@$Dom"; active = 'true'; preferred_language = 'fr'; web_service_access_only = 'true'
}
foreach ($r in 'itil', 'knowledge', 'catalog') { Add-Role $Integ $r }
Write-Host "Utilisateur d'intégration : copilot.studio (Web service access only), sans mot de passe." -ForegroundColor Yellow
Write-Host "  Dans ServiceNow : fiche copilot.studio, Set Password, Generate, Save Password, puis décochez « Password needs reset » et Update."

# ---------- Incidents ----------
$Nouveau = '1'; $EnCours = '2'; $EnAttente = '3'; $Resolu = '6'
$Incidents = @(
    @{ c = 'camille.martin'; t = "Impossible de me connecter à Teams depuis mon nouveau poste"; d = "Arrivée lundi. Teams affiche « Nous n'avons pas pu vous connecter » après la saisie du mot de passe."; cat = 'access'; i = 2; u = 2; s = $EnCours; g = 'Service Desk'; k = $true },
    @{ c = 'camille.martin'; t = "Pas encore d'accès au dossier partagé Marketing"; d = "Mon responsable m'a demandé de reprendre les fichiers de la campagne de printemps, mais le dossier Marketing m'est refusé."; cat = 'access'; i = 3; u = 2; s = $Nouveau; g = 'Service Desk' },
    @{ c = 'thomas.leroy'; t = "Le PC portable de Camille Martin n'est pas encore livré"; d = "Camille Martin est arrivée le 9 novembre et travaille sur un poste de prêt. Le PC commandé n'est pas arrivé."; cat = 'hardware'; i = 2; u = 1; s = $EnAttente; g = 'Hardware'; x = @{ hold_reason = '4' } },
    @{ c = 'sophie.durand'; t = "Demande d'accès au site SharePoint des ressources humaines pour Camille Martin"; d = "Camille Martin doit consulter les procédures d'accueil publiées sur le site des ressources humaines."; cat = 'access'; i = 3; u = 3; s = $Nouveau; g = 'Service Desk' },
    @{ c = 'julie.moreau'; t = "Excel se ferme à l'ouverture du classeur de clôture mensuelle"; d = "Le fichier fait 80 Mo. Excel se ferme sans message. Les autres classeurs s'ouvrent normalement."; cat = 'software'; i = 2; u = 2; s = $EnCours; g = 'Software' },
    @{ c = 'lucas.bernard'; t = "VPN coupé toutes les dix minutes en déplacement"; d = "Depuis la mise à jour de la semaine dernière, la connexion VPN tombe régulièrement depuis les hôtels."; cat = 'network'; i = 2; u = 2; s = $EnCours; g = 'Network' },
    @{ c = 'julie.moreau'; t = "E-mail suspect : demande de virement urgent au nom du directeur"; d = "Reçu ce matin, expéditeur externe qui imite l'adresse du directeur financier. Je n'ai pas cliqué sur le lien."; cat = 'security'; i = 1; u = 1; s = $EnCours; g = 'IT Securities' },
    @{ c = 'antoine.petit'; t = "Accès refusé à la base de données de recette"; d = "Mon compte de service ne peut plus se connecter à la base de recette depuis le renouvellement des certificats."; cat = 'database'; i = 3; u = 2; s = $Nouveau; g = 'Database' },
    @{ c = 'sophie.durand'; t = "Le formulaire d'arrivée des nouveaux collaborateurs ne s'envoie plus"; d = "Le bouton Envoyer reste grisé depuis ce matin, même avec tous les champs remplis."; cat = 'internal_applications'; i = 2; u = 2; s = $Nouveau; g = 'Software' },
    @{ c = 'ines.garcia'; t = "Salle Fourvière : l'écran ne détecte pas l'ordinateur"; d = "Le câble HDMI et la station de partage sans fil ne fonctionnent ni l'un ni l'autre. Réunion du comité de direction jeudi."; cat = 'hardware'; i = 3; u = 2; s = $Nouveau; g = 'Hardware' },
    @{ c = 'antoine.petit'; t = "Lenteurs importantes sur l'application de notes de frais"; d = "Chaque page met plus de 20 secondes à s'afficher, surtout en fin de mois."; cat = 'performance'; i = 2; u = 3; s = $EnAttente; g = 'Software'; x = @{ hold_reason = '1' } },
    @{ c = 'julie.moreau'; t = "OneDrive ne synchronise plus mes documents"; d = "L'icône OneDrive affiche une croix rouge et indique « Synchronisation en pause »."; cat = 'cloud_services'; i = 3; u = 2; s = $EnCours; g = 'Service Desk'; k = $true },
    @{ c = 'ines.garcia'; t = "Imprimante du 2e étage bloquée"; d = "Bourrage papier dans le bac 2, l'imprimante affiche une erreur."; cat = 'hardware'; i = 3; u = 3; s = $Resolu; g = 'Hardware'; x = @{ close_code = 'Resolved – Permanent Fix Applied'; close_notes = "Bourrage retiré, rouleau d'entraînement du bac 2 remplacé." } },
    @{ c = 'lucas.bernard'; t = "Mot de passe expiré, compte verrouillé"; d = "Trois tentatives avec l'ancien mot de passe, compte verrouillé."; cat = 'access'; i = 2; u = 1; s = $Resolu; g = 'Service Desk'; k = $true; x = @{ close_code = 'Resolved by caller'; close_notes = "Compte déverrouillé, l'utilisateur a réinitialisé son mot de passe en libre-service." } },
    @{ c = 'thomas.leroy'; t = "Teams : impossible de partager l'écran en réunion"; d = "Le bouton Partager est grisé dans les réunions externes."; cat = 'collaboration_tools'; i = 3; u = 2; s = $Resolu; g = 'Service Desk'; k = $true; x = @{ close_code = 'Workaround provided'; close_notes = "Autorisation de partage d'écran de Teams accordée par le système d'exploitation. Redémarrage de Teams." } }
)
$crees = 0
foreach ($n in $Incidents) {
    $v = @{
        caller_id = $U[$n.c]; short_description = $n.t; description = $n.d; category = $n.cat
        impact = [string]$n.i; urgency = [string]$n.u; correlation_id = 'contoso-seed'; contact_type = 'self-service'
    }
    if ($Groupes[$n.g]) { $v.assignment_group = $Groupes[$n.g] }
    if ($n.k -or ($n.s -ne $Nouveau -and $n.g -eq 'Service Desk')) { $v.assigned_to = $U['karim.benali'] }
    if ($n.x) { $n.x.GetEnumerator() | ForEach-Object { $v[$_.Key] = $_.Value } }
    $existant = Get-Sn 'incident' "correlation_id=contoso-seed^short_description=$($n.t)" 'sys_id' 1
    if ($existant.Count) { $id = $existant[0].sys_id; Invoke-Sn PATCH 'incident' -Id $id -Body $v | Out-Null }
    else { $id = (Invoke-Sn POST 'incident' -Body $v).sys_id; $crees++ }
    if ($n.s -ne $Nouveau) {
        $etat = @{ state = $n.s }
        if ($n.x) { $n.x.GetEnumerator() | ForEach-Object { $etat[$_.Key] = $_.Value } }
        Invoke-Sn PATCH 'incident' -Id $id -Body $etat | Out-Null
    }
}
Write-Host "Incidents : $($Incidents.Count) ($crees nouveaux)"

# ---------- Base de connaissances ----------
$Kb = Sync-Sn 'kb_knowledge_base' 'title=Contoso - Support informatique' @{
    title = 'Contoso - Support informatique'; description = 'Procédures du support informatique de Contoso Lyon.'
    active = 'true'; owner = $U['karim.benali']
}
$Articles = [ordered]@{
    'Réinitialiser son mot de passe Contoso' = "<p>Votre mot de passe expire tous les 90 jours. Vous recevez un rappel 10 jours avant.</p><ol><li>Ouvrez <b>https://aka.ms/sspr</b> depuis n'importe quel navigateur.</li><li>Saisissez votre adresse Contoso, puis validez avec Microsoft Authenticator.</li><li>Choisissez un mot de passe d'au moins 14 caractères, différent des 5 précédents.</li></ol><p>Compte verrouillé après 3 essais : il se déverrouille seul après 15 minutes, ou appelez le support au poste 2200.</p>"
    'Premier jour : configurer son poste et Microsoft Teams' = "<p>Votre PC portable vous est remis le jour de votre arrivée, au 1er étage, par le support informatique.</p><ol><li>Connectez-vous avec l'identifiant et le mot de passe provisoire remis par le support.</li><li>Changez le mot de passe à la première connexion.</li><li>Configurez Microsoft Authenticator sur votre téléphone.</li><li>Ouvrez Teams : vous êtes déjà membre de l'équipe de votre service.</li></ol><p>Si Teams refuse la connexion, redémarrez le PC une fois : la licence peut mettre jusqu'à 2 heures à s'activer.</p>"
    "Demander l'accès à un dossier partagé ou un site SharePoint" = "<p>Les accès sont accordés par le propriétaire du site, pas par le support.</p><ol><li>Ouvrez le lien du site ou du dossier.</li><li>Cliquez sur <b>Demander l'accès</b> et précisez la raison.</li><li>Le propriétaire reçoit la demande par e-mail.</li></ol><p>Sans réponse sous 2 jours ouvrés, ouvrez une demande « Accès à un site SharePoint » dans le catalogue de services.</p>"
    'Se connecter au VPN Contoso en déplacement' = "<p>Le VPN est nécessaire uniquement pour les applications internes (notes de frais, base de recette). Microsoft 365 fonctionne sans VPN.</p><ol><li>Lancez <b>Contoso Connect</b> depuis la barre des tâches.</li><li>Choisissez la passerelle <b>Lyon</b>, ou <b>Paris</b> si vous êtes dans le nord de la France.</li><li>Validez la notification Microsoft Authenticator.</li></ol><p>Coupures répétées depuis un hôtel : désactivez le Wi-Fi « invité » et utilisez le partage de connexion de votre téléphone.</p>"
    "Configurer l'authentification multifacteur avec Microsoft Authenticator" = "<p>L'authentification multifacteur est obligatoire pour tous les comptes Contoso.</p><ol><li>Installez Microsoft Authenticator sur votre téléphone.</li><li>Ouvrez <b>https://aka.ms/mysecurityinfo</b> et choisissez <b>Ajouter une méthode</b>.</li><li>Scannez le code affiché avec l'application.</li></ol><p>Nouveau téléphone : ajoutez-le avant de rendre l'ancien. Téléphone perdu : appelez le support au poste 2200.</p>"
    'Signaler un e-mail suspect' = "<p>Une demande de virement urgente, un lien vers une page de connexion ou une pièce jointe inattendue doivent vous alerter.</p><ol><li>Ne cliquez sur aucun lien et n'ouvrez pas les pièces jointes.</li><li>Dans Outlook, cliquez sur <b>Signaler</b> puis <b>Hameçonnage</b>.</li><li>Si vous avez cliqué ou saisi votre mot de passe, appelez immédiatement le support au poste 2200.</li></ol><p>Aucune demande de virement n'est jamais validée par e-mail seul chez Contoso.</p>"
    'Imprimer sur les imprimantes Contoso' = "<p>Toutes les impressions passent par la file <b>Contoso-Impression</b> et sortent sur l'imprimante de votre choix.</p><ol><li>Imprimez vers Contoso-Impression.</li><li>Passez votre badge sur le lecteur de n'importe quelle imprimante.</li><li>Choisissez vos documents à l'écran.</li></ol><p>Les documents non imprimés sont supprimés après 24 heures.</p>"
    'Commander du matériel informatique' = "<p>PC, écran, casque, station d'accueil : tout se commande dans le catalogue de services, catégorie <b>Arrivées et matériel</b>.</p><ul><li>Le manager valide la demande.</li><li>Délai habituel : 5 jours ouvrés pour un PC, 2 jours pour les accessoires.</li><li>Pour un nouvel arrivant, commandez au moins 10 jours ouvrés avant son arrivée.</li></ul>"
    'Contacter le support informatique' = "<p>Le support informatique de Contoso Lyon est joignable du lundi au vendredi, de 8 h à 18 h.</p><ul><li>Téléphone : poste 2200.</li><li>Portail : ouvrez un incident ou une demande dans ServiceNow.</li><li>Sur place : 1er étage, bureau 112.</li></ul><p>Urgence de sécurité en dehors des horaires : appelez le numéro d'astreinte affiché à l'accueil.</p>"
}
foreach ($titre in $Articles.Keys) {
    Sync-Sn 'kb_knowledge' "kb_knowledge_base=$Kb^short_description=$titre" @{
        kb_knowledge_base = $Kb; short_description = $titre; text = $Articles[$titre]
        workflow_state = 'published'; author = $U['karim.benali']; valid_to = '2100-01-01'
    } | Out-Null
}
Write-Host "Base de connaissances : $($Articles.Count) articles"

# ---------- Catalogue de services ----------
$Catalogue = (Get-Sn 'sc_catalog' 'title=Service Catalog' 'sys_id' 1)[0].sys_id
$Categorie = Sync-Sn 'sc_category' "title=Arrivées et matériel^sc_catalog=$Catalogue" @{
    title = 'Arrivées et matériel'; sc_catalog = $Catalogue; active = 'true'
    description = 'Matériel et accès pour les nouveaux collaborateurs de Contoso.'
}
$Items = @(
    @('PC portable Contoso standard', 'PC portable 14 pouces, 32 Go de mémoire, livré configuré avec Microsoft 365.', '1450'),
    @('Accès à un site SharePoint', "Demande d'accès à un site SharePoint quand le propriétaire n'a pas répondu sous 2 jours ouvrés.", '0'),
    @("Badge d'accès aux locaux de Lyon", "Badge pour les portes et les imprimantes. Remis à l'accueil le jour de l'arrivée.", '0'),
    @('Casque certifié pour Microsoft Teams', 'Casque sans fil avec réduction de bruit, certifié pour Teams.', '180')
)
foreach ($it in $Items) {
    Sync-Sn 'sc_cat_item' "name=$($it[0])" @{
        name = $it[0]; short_description = $it[1]; description = "<p>$($it[1])</p>"; category = $Categorie
        sc_catalogs = $Catalogue; price = $it[2]; active = 'true'
    } | Out-Null
}
Write-Host "Catalogue : $($Items.Count) articles dans « Arrivées et matériel »"
Write-Host "Terminé. Relancez le script sans risque : il met à jour au lieu de dupliquer." -ForegroundColor Green
