# Auditer un WinPE tiers avant de s'en servir (USM « 联盟版 » et cie)

## Ce qu'on sait, et ce qu'on ne sait pas

**USM** (U盘魔术师) est un WinPE chinois. Sa **« 联盟版 » (édition alliance)** est présentée par son
éditeur comme un PE qui « s'interface avec l'ID de promotion de l'utilisateur dans l'alliance » pour
« installer automatiquement des logiciels promotionnels sur le système cible » (page de l'éditeur :
[sysceo.com](https://www.sysceo.com/Software-softwarei-id-247.html)). Autrement dit, ce n'est pas un
piège caché : c'est le modèle économique. **Le technicien** touche une commission ; **le client** reçoit
les logiciels. Cette page ne mentionne pas de modification de la page d'accueil du navigateur ;
d'autres pages (forums, sites de téléchargement) affirment que des versions récentes en imposent une —
je n'ai pas pu le vérifier, ce sont des sources secondaires.

Ce que **je n'ai pas** : le binaire. Je n'ai rien téléchargé ni exécuté, donc **je ne peux affirmer
aucun comportement précis d'une version donnée**. C'est le rôle de `sonar_pe_audit.sh` : lire le fichier
que *vous* avez, sans l'exécuter, et montrer les preuves.

## Décision recommandée

1. **Ne jamais utiliser une édition d'affiliation sur une machine client.** Même si on n'utilise que
   les outils de diagnostic, la fonction « installer un système » est celle qui pose les logiciels
   promotionnels : un clic de trop suffit, et le client ne l'a pas demandé.
2. « Enlever la publicité » d'un PE repackagé n'est pas une solution : on ne sait pas ce qu'on n'a pas
   vu, et un binaire modifié n'est plus celui qu'on a audité. Si un USM doit être utilisé, ce doit être
   une édition **non affiliée**, auditée (ci-dessous), **dont on garde le hachage SHA-256**.
3. Pour ce que fait USM dont on a réellement besoin, le WinPE SONAR-SE (ADK Microsoft + BusyBox +
   PowerShell/BitLocker/WMI, voir `docs/WINPE.md`) couvre déjà réparation du démarrage, BitLocker,
   diagnostic, pilotes de stockage et outils portables de la clé, sans publicité ni affiliation.

## Analyse statique : `tools/sonar_pe_audit.sh`

```bash
# 1. une fois : la référence d'un WinPE PROPRE (ce que Microsoft fournit)
tools/sonar_pe_audit.sh --make-baseline adk_base.tsv \
    "C:/Program Files (x86)/Windows Kits/10/Assessment and Deployment Kit/Windows Preinstallation Environment/amd64/en-us/winpe.wim"

# 2. l'ISO suspecte
tools/sonar_pe_audit.sh USM_lianmeng.iso --baseline adk_base.tsv --out ./audit_usm
```

Dépendances (Debian/Ubuntu/SystemRescue) : `p7zip-full wimtools binutils libwin-hivex-perl`.
Lecture seule : l'ISO et ses WIM sont extraits dans un dossier temporaire, rien n'est exécuté.

| Contrôle | Cherche |
|---|---|
| P010 | `startnet.cmd`, `winpeshl.ini`, `autorun.inf` : adresse web, programme non standard au démarrage |
| P020 | ruches hors ligne : Run/RunOnce, Winlogon Shell/Userinit, IFEO « Debugger », page d'accueil, proxy, services hors de Windows |
| P030 | tâches planifiées embarquées |
| P040 | fichier `hosts` modifié |
| P050 | raccourcis `.url`/`.lnk` avec un lien (bureau, menu Démarrer) |
| P060 | fichiers **ajoutés ou modifiés** par rapport à la référence (sans référence : ce qui est hors de `\Windows`) |
| P070 | indicateurs de `tools/pe_audit_indicators.txt`, en chaînes ASCII **et UTF-16**, mots chinois compris : « 联盟 », « 推广 », « 锁定主页 », identifiant d'affiliation dans une URL (`unionid=`, `channel=`…), installateurs (NSIS, Inno…), `schtasks /create`, dépôt dans Démarrage, `reg load`… |
| P080 | domaines cités par ces fichiers, hors liste de confiance |

**Lecture du résultat.** `INDICATEURS FORTS` ou `À EXAMINER` : chaque constat montre sa preuve et le
fichier ; à vous de juger. **`aucun indicateur` ne veut jamais dire « sain »** : un code chiffré,
obfusqué ou téléchargé plus tard n'est pas vu par une analyse statique. Le mot d'affiliation seul est
`MEDIUM` ; il passe `HIGH` (« mécanisme d'affiliation probable ») s'il est accompagné d'un installateur
embarqué ou d'un identifiant de canal dans une URL. Codes retour : 0 / 10 (à examiner) / 20 (forts) / 2.

Les indicateurs sont des heuristiques éditables, pas des preuves : un outil de réparation légitime peut
charger une ruche ou écrire dans le dossier Démarrage.

## Analyse dynamique (ce que la statique ne voit pas)

À faire dans une **VM jetable**, jamais sur du matériel de travail :

1. VM sans réseau : démarrer l'ISO, prendre des captures ; comparer, dans la VM, `dir /s /b X:\` et le
   registre avant/après avoir ouvert chaque outil (surtout « installer un système »).
2. Réseau **interne** sans Internet, avec une machine qui journalise (DNS et connexions sortantes) :
   quels noms de domaine le PE cherche-t-il à joindre ? un PE de dépannage n'a aucune raison d'appeler
   un serveur de suivi au démarrage.
3. Sur un faux disque Windows (VHD) : lancer les fonctions d'installation, puis **monter le VHD hors de la
   VM** et le comparer à l'original — dossier Démarrage, tâches planifiées, `RunOnce`, page d'accueil,
   raccourcis, programmes installés. C'est l'endroit où l'affiliation se voit.
4. Conserver : SHA-256 de l'ISO, rapport d'audit, différences du VHD. Si un seul point contredit ce que
   l'éditeur annonce, l'ISO est écartée.

## Limites honnêtes de l'outil
- Il n'a été validé que sur des **arbres de test fabriqués** et sur notre propre WinPE ; **aucune vraie
  édition d'USM n'a été analysée**.
- Pas de vérification de signatures Authenticode (nécessiterait un outil dédié) : un binaire signé peut
  quand même être indésirable.
- Comparaison à la référence par chemin + taille (`--strict` : SHA-256) : un fichier remplacé par un
  autre de même taille n'est vu qu'avec `--strict`.
