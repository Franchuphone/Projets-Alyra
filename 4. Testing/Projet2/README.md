# L'idée de démarrage

J'ai essayé de me projeter dans un smart contract vide et son processus de création pour implémenter le TDD.  
J'ai vidé le contract originel et j'ai commencé à écrire les tests (ok c'est plus facile quand on sait le contenu du code à l'avance).

# Le process

## 1. Le déploiement

Tester les bases du smart contract avant l'utilisation de ses fonctions

- vérification de la bonne implémentation des héritages
- vérification des variables d'état

## 2. Les getters

Initialisation de getVoter et getOneProposal.  
Une liste de voters étant nécessaire pour accéder aux getters (onlyVoter), le test de addVoter est prioritaire.  
Leur utilisation et bon fonctionnement va faciliter le reste des tests.

- vérification des informations retournées
- restriction de la fonction aux votants
- contrôle de certains edge case

## 3. Le Workflow

Certains changements de workflow doivent être implémentés en parallèle du processus de vote

- vérification du changement correct de status du workflow
- vérification de l'émission de l'event
- restriction d'utilisation à owner
- restriction d'exécution durant le correct status de workflow
- contrôle des edge case

## 4. Enregistrement des voters

Première fonction à coder dû aux restrictions onlyVoter

- vérification de l'ajout d´un voter avec les bons arguments : codage et test couplé de getVoter
- vérification de l'émission de l'event
- restriction de la fonction à owner
- restriction au workflow : codage et test couplé de startProposalsRegistering
- controle des doublons
- tests étendus

## 5. Enregistrement des proposals

- vérification de l'ajout correct d'une proposal
- vérification de l'émission de l'event
- restriction de la fonction aux voters
- restriction au workflow
- contrôle de la validité de la proposition
- test étendu des fonctionnalités

## 6. Enregistrement des votes

- vérification de l'ajout correct d'un vote à une proposition
- vérification de la modification correcte du statut du voter
- vérification de l'émission de l'event
- restriction de la fonction aux voters
- restriction au workflow
- contrôle des doubles votes
- contrôle de la validité du vote

## 7. Comptage des votes

- vérification du gagnant retourné
- vérification de la modification finale du workflow
- vérification de l'émission de l'event
- restriction d'utilisation à owner
- restriction du workflow
- test étendu des fonctionnalités
- test de résistance

# Conclusion

J'ai trouvé ma solution très répétitive pour le contrôle des fonctions gérant le workflow.  
J'avoue ne pas avoir entrevu une autre facon de faire pour que cela reste cohérent et lisible.

Je reconnais également l'utilisation de l'IA pour compenser dans les tâches répétitives d'écriture des tests, mais aucune utilisation de cet outil dans la logique sous-jacente.  
La structure de ce md reprend la structure des tests dans le fichier typescript, mais ne représente par leur chronologie d'écriture : l'agencement a été revu pour une meilleure lisibilité générale et une meilleure lecture dans la console.

J'ai ajouté quelques tests en solidity pour essayer le fuzz.  
J'ai voulu comparé la rapidité du test de résistance de tallyVotes en le portant sur solidity, mais je l'ai désactivé avec un vm.skip(true) suite à des soucis de stabilité/crash de VsCode sur mon PC quand le maxProposals dépassait les 10000.  
J'aurai des questions également par rapport à cette portabilité : différence de gasUsed (problème de mon code je suppose), à combien mettre la limite de gas par block/transacion pour un usage réaliste, etc...
