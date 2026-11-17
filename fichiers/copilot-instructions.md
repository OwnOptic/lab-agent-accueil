# Lab : un workflow Copilot Studio construit depuis le terminal

Tu aides à construire un **workflow Copilot Studio** (nouvelle expérience) avec le seul az CLI. Un workflow Copilot Studio est un enregistrement Dataverse : une ligne de la table `workflows`, de type « Copilot Studio flow » (`modernflowtype = 1`). Il apparaît ensuite dans Copilot Studio, page **Workflows**, et s'ouvre dans le nouvel éditeur.
Le déroulé doit être **fluide** : tout ce qu'il te faut est dans ce fichier.

- **Ne cherche rien sur le web ni sur Microsoft Learn** : chaque forme ci-dessous a été vérifiée par une exécution réelle, et elle s'ouvre dans le nouvel éditeur. Utilise-la telle quelle.
- **Ne pose aucune question** dont la réponse est dans ce fichier (voir « Décisions déjà prises »).
- **N'utilise jamais l'API de Power Automate pour créer le workflow** : on crée l'enregistrement Dataverse (sinon il n'apparaît pas dans Copilot Studio).
- Explique en une phrase courte ce que tu fais à chaque étape, en français.
- Montre d'abord la liste des étapes (une ligne par étape). Puis écris un script `./flux/creer-workflow.ps1` qui construit le workflow, garde le JSON produit dans `./flux/accueil-nouveaux-collaborateurs.json`, et l'envoie.

## Le contexte (tenant de test, entreprise fictive Contoso)

| Quoi | Valeur |
|---|---|
| Tenant | ID `TENANT_ID` |
| Environnement Power Platform | ID `ENVIRONNEMENT_ID` |
| Dataverse de l'environnement | `URL_DATAVERSE` (API : `/api/data/v9.2`) |
| Site SharePoint | `URL_DU_SITE` |
| Liste « Arrivées » | ID `LISTE_ID` |

Colonnes de la liste, et comment les lire :

| Colonne affichée | Dans le déclencheur | Après la relecture `Relire_l_element` |
|---|---|---|
| Nom complet | `triggerBody()?['Title']` | `body('Relire_l_element')?['Title']` |
| E-mail | `triggerBody()?['Email']` | `...?['Email']` |
| Poste | `triggerBody()?['Poste']` | `...?['Poste']` |
| Date d'arrivée | `triggerBody()?['DateArrivee']` (date `yyyy-MM-dd`) | `...?['DateArrivee']` |
| Manager | `triggerBody()?['Manager']?['Email']` | `...?['Manager']?['Email']` |
| Parrain ou marraine | `triggerBody()?['Parrain']?['Email']` | `...?['Parrain']?['Email']` |
| Matériel remis | `triggerBody()?['MaterielRemis']?['Value']` (« Oui » ou « Non ») | `body('Relire_l_element')?['MaterielRemis']?['Value']` |

## Décisions déjà prises

1. **Un seul workflow**, nommé « Accueil des nouveaux collaborateurs ». Une exécution dure au plus 30 jours : c'est accepté pour la démo (le dire en une phrase ; en production, on séparerait l'accueil et une relance quotidienne).
2. **Programme de la première semaine** pour l'e-mail de bienvenue (repris du livret d'accueil) : lundi 9 h accueil et badge au rez-de-chaussée, 9 h 30 remise du matériel salle Fourvière (3e étage), 11 h café avec le parrain ou la marraine, 14 h point avec le manager ; mardi formation « Sécurité de l'information » ; mercredi déjeuner d'équipe ; jeudi formation protection des données ; vendredi point de fin de semaine avec le manager. Adresse : 40 rue de la Démo, 69002 Lyon.
3. **Café de bienvenue** : le jour de l'arrivée, de 11 h à 11 h 30, heure de Paris, avec le nouveau collaborateur et le parrain ou la marraine.
4. **Relance** : 3 jours après la date d'arrivée, à 9 h heure de Paris, on relit l'élément ; si « Matériel remis » vaut encore Non, e-mail au manager.
5. Tous les e-mails et messages sont en français, chaleureux et courts.

## Les outils

- **Uniquement az CLI**, déjà connecté (`az login --tenant TENANT_ID`). Passe toujours `--tenant TENANT_ID`, au cas où le tenant par défaut d'az serait un autre. N'utilise pas `az rest` (mauvais tenant) : prends un jeton puis appelle l'API avec `Invoke-RestMethod`.
- Jeton Dataverse : `az account get-access-token --tenant TENANT_ID --resource URL_DATAVERSE --query accessToken -o tsv`
- Jeton pour suivre les exécutions : même commande avec `--resource https://service.flow.microsoft.com/`
- Jeton pour lire les connexions : même commande avec `--resource https://service.powerapps.com/`
- Envoie les corps en UTF-8 (`-Body ([System.Text.Encoding]::UTF8.GetBytes($json))` et `-ContentType 'application/json; charset=utf-8'`), pour garder les accents. Pour sérialiser : `ConvertTo-Json -Depth 50 -Compress`.

## Les références de connexion (à créer d'abord, une seule fois)

Un workflow Copilot Studio ne pointe pas directement vers une connexion : il passe par une **référence de connexion** Dataverse. Les trois connexions existent déjà (SharePoint, Office 365 Outlook, Microsoft Teams, créées par l'utilisateur) ; crée les trois références qui pointent vers elles, sauf si elles existent déjà :

1. Vérifie : `GET URL_DATAVERSE/api/data/v9.2/connectionreferences?$select=connectionreferencelogicalname,connectionid&$filter=startswith(connectionreferencelogicalname,'new_accueil')`.
2. Pour chaque connecteur manquant, lis l'identifiant de sa connexion : `GET https://api.powerapps.com/providers/Microsoft.PowerApps/apis/<connecteur>/connections?api-version=2016-11-01&$filter=environment eq 'ENVIRONNEMENT_ID'` (jeton `service.powerapps.com`), et garde le `name` d'une connexion dont `properties.statuses` contient `Connected`.
3. Crée la référence : `POST URL_DATAVERSE/api/data/v9.2/connectionreferences` avec `{"connectionreferencelogicalname": "<référence>", "connectionreferencedisplayname": "Accueil <connecteur>", "connectorid": "/providers/Microsoft.PowerApps/apis/<connecteur>", "connectionid": "<name lu à l'étape 2>"}`.

| Connecteur | Référence de connexion |
|---|---|
| `shared_sharepointonline` | `new_accueil_sharepoint` |
| `shared_office365` | `new_accueil_outlook` |
| `shared_teams` | `new_accueil_teams` |

Ensuite, relis leur `connectionid` (requête de l'étape 1) : il sert dans le graphe.

## Ce qu'est un workflow Copilot Studio (format vérifié le 12 novembre 2026)

Le champ `clientdata` de l'enregistrement contient **deux vues du même workflow**, qui doivent rester cohérentes :
1. **la définition exécutable** (`properties.definition`), au format Logic Apps : déclencheur, actions, `runAfter` ;
2. **le graphe de l'éditeur**, dans `properties.definition.triggers.Nouvelle_arrivee.metadata.associatedData` : les nœuds et les liens que dessine le nouvel éditeur.

**Sans le graphe complet, le workflow tourne, mais l'éditeur affiche « Looks like that link is broken », ou le range parmi les workflows classiques.** Les trois clés de `associatedData` sont obligatoires : `graph`, `nodeActionMapping`, `canvasOrientation`.

### Le graphe

```json
"associatedData": {
  "graph": {
    "name": "Accueil des nouveaux collaborateurs",
    "nodes": [ "...un nœud par étape, le déclencheur en premier..." ],
    "edges": [ "...un lien par flèche..." ],
    "connectionReferences": {
      "shared_office365": { "api": { "name": "shared_office365" }, "connection": { "connectionReferenceLogicalName": "new_accueil_outlook" }, "runtimeSource": "embedded", "connectionName": "<connectionid de la référence>" }
    },
    "parameters": { "$authentication": { "type": "SecureObject", "defaultValue": {} }, "$connections": { "type": "Object", "defaultValue": {} } }
  },
  "nodeActionMapping": { "<id du nœud>": ["<nom de l'action>"] },
  "canvasOrientation": "horizontal"
}
```

Règles (chacune a cassé l'éditeur pendant la mise au point) :
- **Identifiant de nœud = `<type>-<GUID>`**, avec un vrai GUID (`[guid]::NewGuid()`) : `start-…`, `connector-…`, `builtinFunction-…`, `ifElse-…`. Un identifiant inventé (`start-1`) casse l'éditeur.
- Chaque nœud : `{"id", "name", "type", "version": 1, "position": {"x", "y"}, "data": {"config": {...}, "outcomes": [{"id": "default", "label": "Default"}]}, "measured": {"width": 240, "height": 66}}`. Positions : x = 250, puis +316 par colonne ; y = 180, et deux étapes en parallèle à y = 70 et y = 290. Le nœud If/Else a `"height": 169`.
- Chaque action de la définition porte `"metadata": {"description": "<nom du nœud>", "nodeId": "<id du nœud>"}`. `nodeActionMapping` relie chaque nœud, sauf le déclencheur, au nom de son action.
- Lien : `{"id": "edge-<source>-<cible>", "source": "<id>", "target": "<id>"}`. Depuis la branche If d'une condition : ajoute `"sourceHandle": "condition:<id de la condition>"`, et l'id devient `edge-<source>-condition:<id de la condition>-<cible>`.
- Le graphe n'a pas besoin du schéma des colonnes ni des icônes : l'éditeur les recharge.

### Les nœuds et leur action

**Déclencheur « élément créé »** (nœud `start`) :
```json
{ "triggerType": "connector", "connector": { "apiName": "shared_sharepointonline", "operationName": "GetOnNewItems", "connectionName": "shared_sharepointonline",
  "inputs": { "dataset": "URL_DU_SITE", "table": "LISTE_ID" },
  "displayName": "Nouvelle arrivee", "operationType": "OpenApiConnection", "triggerBatchMode": "Batch" } }
```
Déclencheur de la définition, nommé `Nouvelle_arrivee` :
```json
{ "type": "OpenApiConnection", "recurrence": { "frequency": "Minute", "interval": 1 }, "splitOn": "@triggerOutputs()?['body/value']",
  "metadata": { "associatedData": { "...le graphe..." } },
  "inputs": { "host": { "apiId": "/providers/Microsoft.PowerApps/apis/shared_sharepointonline", "connectionName": "shared_sharepointonline", "operationId": "GetOnNewItems" },
              "parameters": { "dataset": "...", "table": "..." }, "authentication": "@parameters('$authentication')" } }
```

**Action de connecteur** (nœud `connector`) : `{"apiName": "<connecteur>", "displayName": "<nom>", "operationName": "<opération>", "parameters": {...}, "operationType": "OpenApiConnection", "connectionName": "<connecteur>"}`.
Action : `{"type": "OpenApiConnection", "runAfter": {"<action précédente>": ["Succeeded"]}, "inputs": {"host": {"apiId": "/providers/Microsoft.PowerApps/apis/<connecteur>", "connectionName": "<connecteur>", "operationId": "<opération>"}, "parameters": {...les mêmes...}}, "metadata": {...}}`. La première action après le déclencheur n'a pas de `runAfter`.

| Étape | Connecteur | Opération | `parameters` |
|---|---|---|---|
| E-mail | `shared_office365` | `SendEmailV2` | `{"emailMessage/To": "...", "emailMessage/Subject": "...", "emailMessage/Body": "<p>HTML</p>"}` |
| Message Teams au manager | `shared_teams` | `PostMessageToConversation` | `{"poster": "Flow bot", "location": "Chat with Flow bot", "body/recipient": "<e-mail du manager>", "body/messageBody": "<p>HTML</p>"}` |
| Invitation au café | `shared_office365` | `V4CalendarPostItem` | `{"table": "Calendar", "item/subject": "...", "item/start": "<yyyy-MM-ddT11:00:00>", "item/end": "<yyyy-MM-ddT11:30:00>", "item/timeZone": "(UTC+01:00) Brussels, Copenhagen, Madrid, Paris", "item/requiredAttendees": "<e-mail1>;<e-mail2>", "item/body": "<p>HTML</p>"}` (pas de `item/isHtml` : refusé) |
| Relire l'élément | `shared_sharepointonline` | `GetItem` | `{"dataset": "<site>", "table": "<liste>", "id": "@triggerBody()?['ID']"}` |

**Attendre jusqu'à une date** (nœud `builtinFunction`) :
```json
{ "operationId": "delayuntil", "operationName": "delayuntil", "displayName": "Delay until",
  "category": "providers/Microsoft.ProcessSimple/operationGroups/Schedule", "categoryDisplayName": "Schedule",
  "parameters": { "until": "<date UTC>" } }
```
Action : `{"type": "Wait", "inputs": {"until": {"timestamp": "<date UTC>"}}, "runAfter": {...}, "metadata": {...}}`. Attention, les deux formes diffèrent : dans le **nœud**, `until` est une simple chaîne (sinon le champ s'affiche vide) ; dans l'**action**, `until` contient `timestamp` (la forme chaîne que l'éditeur écrit échoue à l'exécution : « Error converting value … WaitUntil »). `delayuntil` s'écrit en minuscules.

**Condition** (nœud `ifElse`, `"height": 169`) : `{"conditions": [{"id": "<GUID>", "name": "If", "expression": "<l'expression, sérialisée en texte JSON>"}]}`, avec `"outcomes": [{"id": "condition:<GUID>", "label": "If"}, {"id": "else", "label": "Else"}]`.
Action : `{"type": "If", "expression": {"and": [{"equals": ["@body('Relire_l_element')?['MaterielRemis']?['Value']", "Non"]}]}, "actions": {...la branche If ; sa première action sans runAfter...}, "else": {"actions": {}}, "runAfter": {...}, "metadata": {...}}`.

### Valeurs dynamiques

Une expression `@{...}` dans le texte : `"Bienvenue chez Contoso, @{triggerBody()?['Title']} !"`. L'éditeur les affiche comme des jetons.
- Dates du café : `@{formatDateTime(triggerBody()?['DateArrivee'], 'yyyy-MM-dd')}T11:00:00` et `...T11:30:00`.
- Attente jusqu'à 9 h, heure de Paris, 3 jours après l'arrivée (le format UTC est obligatoire) : `@{convertToUtc(concat(formatDateTime(addDays(triggerBody()?['DateArrivee'], 3), 'yyyy-MM-dd'), 'T09:00:00'), 'Romance Standard Time')}`.

### Le workflow attendu

`Nouvelle_arrivee` → `E_mail_de_bienvenue` → en parallèle `Message_au_manager` et `Cafe_de_bienvenue` (tous deux après l'e-mail) → `Attendre_3_jours` (après les deux) → `Relire_l_element` → `Materiel_manquant` (condition) → dans sa branche If, `Relancer_le_manager`. Noms des nœuds : les mêmes, avec des espaces (« E-mail de bienvenue », « Materiel manquant ? »…).

## La séquence de déploiement

1. **POST** `URL_DATAVERSE/api/data/v9.2/workflows`, en-tête `Prefer: return=representation`, corps :
   ```json
   { "category": 5, "type": 1, "modernflowtype": 1, "primaryentity": "none",
     "name": "Accueil des nouveaux collaborateurs",
     "description": "Accueil automatique des nouveaux collaborateurs de Contoso",
     "clientdata": "<le JSON ci-dessous, sérialisé en chaîne>" }
   ```
   ```json
   { "properties": {
       "connectionReferences": {
         "shared_sharepointonline": { "runtimeSource": "embedded", "connection": { "connectionReferenceLogicalName": "new_accueil_sharepoint" }, "api": { "name": "shared_sharepointonline" } },
         "shared_office365": { "runtimeSource": "embedded", "connection": { "connectionReferenceLogicalName": "new_accueil_outlook" }, "api": { "name": "shared_office365" } },
         "shared_teams": { "runtimeSource": "embedded", "connection": { "connectionReferenceLogicalName": "new_accueil_teams" }, "api": { "name": "shared_teams" } } },
       "definition": {
         "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
         "contentVersion": "1.0.0.0",
         "parameters": { "$authentication": { "defaultValue": {}, "type": "SecureObject" }, "$connections": { "defaultValue": {}, "type": "Object" } },
         "triggers": { "Nouvelle_arrivee": { "...avec metadata.associatedData..." } },
         "actions": { "..." },
         "outputs": {} } },
     "schemaVersion": "1.0.0.0" }
   ```
   Dans la définition comme dans le graphe, `connectionName` vaut le nom du connecteur (`shared_office365`…), qui est la clé de `connectionReferences`. La réponse donne `workflowid`.
2. **Activer** : `PATCH .../workflows(<workflowid>)` avec `{"statecode": 1, "statuscode": 2}`.
3. Donne les liens : l'éditeur `https://copilotstudio.microsoft.com/environments/ENVIRONNEMENT_ID/flows/<workflowid>` et la liste `https://copilotstudio.microsoft.com/environments/ENVIRONNEMENT_ID/workflows`.

**Modifier le workflow ensuite** (par exemple pour ajouter une étape) : relis `clientdata` (`GET .../workflows(<id>)?$select=clientdata`), garde une copie dans `./sauvegardes/`, désactive (`PATCH {"statecode": 0, "statuscode": 1}`), modifie **la définition et le graphe ensemble**, envoie (`PATCH {"clientdata": "..."}`), puis réactive.

## Après l'activation

Dis à l'utilisateur d'ajouter une ligne dans la liste (le déclencheur passe toutes les minutes), puis suis les exécutions avec l'API des flux :
1. retrouve le workflow : `GET https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/ENVIRONNEMENT_ID/flows?api-version=2016-11-01`, garde celui dont `properties.workflowEntityId` vaut ton `workflowid` (son `name` sert dans les appels suivants) ;
2. `GET .../flows/<name>/runs?api-version=2016-11-01`, puis `.../runs/<runId>/actions?api-version=2016-11-01`.
Résume le statut de chaque action. Si une action échoue, l'erreur réelle est souvent dans le lien signé `outputsLink.uri` de l'action : ouvre-le. L'onglet **Activity** de l'éditeur montre la même chose.

## Variante ServiceNow (si l'utilisateur a choisi l'agent de support)

L'utilisateur a une instance de développement ServiceNow préparée par `servicenow-seed.ps1`, et une connexion **ServiceNow** (authentification de base, utilisateur `copilot.studio`) dans son environnement. Crée sa référence de connexion comme les autres (même méthode que plus haut) : connecteur `shared_service-now`, référence `new_support_servicenow`, nom affiché « Support ServiceNow ». Pour un workflow qui n'utilise que ServiceNow et Teams, ne crée que les références dont il a besoin.

Les données : table `incident` (champs utiles : `number`, `short_description`, `description`, `caller_id`, `priority`, `state`, `assigned_to`, `assignment_group`, `category`), incidents de démonstration marqués `correlation_id = contoso-seed` ; base de connaissances « Contoso - Support informatique » ; catégorie de catalogue « Arrivées et matériel ». États d'un incident : 1 nouveau, 2 en cours, 3 en attente, 6 résolu, 7 clos. Priorité : 1 critique à 5 planification.

Les actions (nœud `connector`, `apiName` et `connectionName` = `shared_service-now`, même forme que les autres connecteurs) :

| Étape | Opération | `parameters` |
|---|---|---|
| Lister des incidents | `GetRecords` | `{"tableType": "incident", "sysparm_query": "active=true^priority<=2^assigned_toISEMPTY", "sysparm_limit": 10, "sysparm_display_value": true, "sysparm_fields": "number,short_description,priority,state,caller_id"}` |
| Créer un incident | `CreateRecord` | `{"tableType": "incident", "body/short_description": "...", "body/description": "...", "body/caller_id": "<sys_id du demandeur>", "body/urgency": "2", "sysparm_display_value": true, "sysparm_exclude_reference_link": true}` (le corps est dynamique : un champ ServiceNow = une clé `body/<nom du champ>`. **Garde `sysparm_exclude_reference_link: true`** : sans lui, la réponse renvoie `caller_id` sous forme d'objet et l'action échoue alors que l'incident est créé.) |
| Lire un incident | `GetRecord` | `{"tableType": "incident", "sysid": "<sys_id>", "sysparm_display_value": true}` |
| Mettre à jour un incident | `UpdateRecord` | `{"tableType": "incident", "sysid": "<sys_id>", "body/state": "2", "body/work_notes": "..."}` |
| Retrouver un collaborateur | `GetRecords` | `{"tableType": "sys_user", "sysparm_query": "email=<adresse>", "sysparm_fields": "sys_id,name", "sysparm_limit": 1}` |
| Chercher dans la base de connaissances | `GetRecords` | `{"tableType": "kb_knowledge", "sysparm_query": "kb_knowledge_base.title=Contoso - Support informatique^active=true^short_descriptionLIKE<mot>^ORtextLIKE<mot>", "sysparm_fields": "number,short_description", "sysparm_limit": 3}` (n'utilise pas `GetKnowledgeArticles` : le module Knowledge API manque sur les instances de développement) |
| Chercher dans le catalogue | `GetCatalogItems` | `{"sysparm_text": "<texte>", "sysparm_limit": 5}` |

La liste renvoyée par `GetRecords` est dans `body('<action>')?['result']` : parcours-la avec une boucle « Apply to each », ou mets-la en forme avec `join` et `select`. Avec `sysparm_display_value: true`, les champs référence (`caller_id`, `assigned_to`) sont lisibles directement.

Pour un workflow qui part d'une nouvelle arrivée, garde le déclencheur SharePoint « élément créé » décrit plus haut : il est vérifié dans le nouvel éditeur. Un workflow planifié commence par un déclencheur `Recurrence` dans la définition (`{"type": "Recurrence", "recurrence": {"frequency": "Day", "interval": 1, "schedule": {"hours": ["8"]}, "timeZone": "Romance Standard Time"}}`). Le dessin de ce déclencheur dans l'éditeur n'a pas été vérifié ici : si l'éditeur l'affiche mal, le workflow tourne quand même ; dis-le à l'utilisateur plutôt que d'improviser.

## Garde-fous

N'affiche jamais un jeton. Ne touche à aucun autre environnement ni à aucun autre workflow. Ne supprime rien, ne recrée pas des références de connexion qui existent déjà. Avant de modifier un workflow existant, relis son `clientdata` et garde-le dans `./sauvegardes/`.
