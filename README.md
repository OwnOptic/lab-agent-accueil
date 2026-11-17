# Lab : construisons un agent ensemble

Lab pas à pas de la session « Construisons un agent ensemble : Copilot Studio en direct, de zéro à un agent qui fonctionne » (aMP Day Lyon 2026).

**Ouvrir le lab : https://ownoptic.github.io/lab-agent-accueil/**

Au début du lab, vous choisissez l'agent à construire, dans un tenant de test :

- **l'agent d'accueil des ressources humaines** : un workflow Copilot Studio d'accueil des nouveaux collaborateurs, écrit par GitHub Copilot ou Claude Code et créé dans Dataverse avec Azure CLI, puis un agent qui répond à partir des documents des ressources humaines, testé, évalué et publié dans Teams ;
- **l'agent de support informatique ServiceNow** : une instance de développement ServiceNow remplie par `fichiers/servicenow-seed.ps1`, une connexion ServiceNow dans Power Platform, puis un agent Copilot Studio qui cherche dans la base de connaissances, suit et crée des incidents, évalué avec `fichiers/test-set-servicenow.csv` et publié dans Teams ;
- **l'agent de résolution des tickets** : sur la même instance ServiceNow, un agent qui travaille pour le support : il propose la solution dans les tickets simples à partir de la base de connaissances, rédige en brouillon l'article qui manque, ne clôture ni ne publie rien, évalué avec `fichiers/test-set-resolution.csv`.

Contoso est une entreprise fictive. Les documents du dossier `fichiers/` sont des exemples.

Par Elliot Margot, Microsoft MVP (Most Valuable Professional) Microsoft 365 Copilot et Copilot Studio.
