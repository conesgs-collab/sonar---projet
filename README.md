# SONAR - SE

Outil de déploiement automatisé pour clé USB de maintenance IT (Ventoy +
persistance + module forensique/backup/recovery + couche RBAC), en un seul
script Bash auto-vérifiable. Le script lui-même reste `sonar_master.sh`
(pas de renommage de fichier, seulement du produit) — voir "Auteur" en bas
de page.

> **Ce que SONAR fait, et ne fait pas :** SONAR construit la clé et trace
> son origine (déploiement Ventoy, manifeste SHA-256, filigrane de build,
> verrou de rôle, journal d'audit chaîné). **Les outils qui dépannent
> réellement une machine sont ceux des profils `--profile <nom>`.
> Profils de dépannage : `boot-repair`, `data-recovery`, `malware`,
> `disk-clone`, `password-reset`, `hardware-diagnostic`,
> `peripherals-network`. Profil de distributions généralistes (pas liées
> à un scénario de réparation) : `general-os`. Et `full`, l'union de
> tous. — SONAR ne répare rien lui-même.** Le catalogue de 981 outils (`docs/CATALOG.md`) est une
> base de connaissance consultable, pas la source de vérité de ce qui va
> sur la clé.

> **Statut : validé sur un premier déploiement matériel réel** (SSD USB
> externe, boot UEFI + Secure Boot confirmé — voir `ROADMAP.md` section
> P0). Testé sur une seule machine/configuration à ce jour ; pas encore
> sur BIOS legacy ni sur un second modèle. Voir `CHANGELOG.md` avant tout
> usage en production sur du matériel inconnu.

## Démarrage rapide

```bash
chmod +x sonar_master.sh

# Activer le filet de sécurité local (bloque un commit si self-audit/self-test échoue)
git config core.hooksPath hooks/

# Vérifier que le script est structurellement sain
./sonar_master.sh --self-audit

# Suite de tests fonctionnels (dépendances, hashchain, verrou de rôle, etc.)
./sonar_master.sh --self-test

# Initialiser le verrou de rôle (une seule fois, avant de distribuer l'outil)
./sonar_master.sh --role-bootstrap

# Émettre un jeton nominatif pour un technicien (rôle Admin, 30 jours)
./sonar_master.sh --role-issue-token Admin j.dupont 30

# Analyse croisée de l'état du système (dépendances, intégrité, couverture)
./sonar_master.sh --smart-advisor

# Après une acquisition forensique, générer la chaîne de possession
./sonar_master.sh --forensic-chain-of-custody <DOSSIER_PREUVES> "DOSSIER-2026-042"

# Télécharger (sans installer) tout ce que le catalogue résout via apt —
# pas d'IA, couverture partielle par nature (voir CHANGELOG.md v3.13.0)
./sonar_master.sh --catalog-download-resolve   # rapport seul, rien à télécharger
./sonar_master.sh --catalog-download           # télécharge vers SOURCE_DIR/Portable/AptPackages

# Profils de dépannage fermés et documentés (scénario + outils + pourquoi) —
# c'est CECI, pas le catalogue 981, qui décide de ce qui va sur la clé
./sonar_master.sh --profile                    # vue d'ensemble des 8 profils (+ full)
./sonar_master.sh --profile boot-repair        # détail d'un profil précis

# Voir toutes les commandes disponibles
./sonar_master.sh --help
```

## Coffre chiffré autonome (sur le terrain)

Chaque clé déployée embarque `Scripts/sonar-vault.sh` — un coffre chiffré
gpg AES-256 exécuté **sur le terrain** par le technicien, pour ses propres
données sensibles. Complètement indépendant de la persistance Ventoy (qui
n'est **jamais** chiffrée par SONAR — voir `CHANGELOG.md` v3.9.0 pour le
raisonnement). Désactivable au build avec `--no-veracrypt`.

```bash
./sonar-vault.sh create <source> <coffre.enc>
./sonar-vault.sh open   <coffre.enc> <sortie>
```

## Filigrane de build (traçabilité, pas prévention)

Rien en logiciel n'empêche un `dd` bit-à-bit d'une clé USB déployée — c'est
une limite physique, pas un manque d'effort. Ce qui est réellement faisable :
chaque déploiement réel embarque un filigrane signé (HMAC-SHA256, secret
dédié, distinct de celui du verrou de rôle) dans
`MANIFEST/BUILD_WATERMARK.txt`. Si une copie non autorisée refait surface,
on peut prouver de quel build authentique elle provient.

```bash
./sonar_master.sh --verify-watermark <FICHIER_OU_DOSSIER>
```

Ne fonctionne que sur la machine possédant le secret de watermark local —
c'est le point : sur une autre machine, les métadonnées restent lisibles
mais l'authenticité n'est pas confirmable.

## Catalogue protégé (`--protect-catalog`)

Même limite physique que ci-dessus : rien n'empêche un clone brut de la
clé. `--protect-catalog` (rôle VAULT requis) chiffre en place
`MANIFEST/MANIFEST.tsv` — la curation complète (quel outil, pourquoi,
SHA-256) — avec gpg AES-256, sans jamais toucher au boot ni au dépannage
(ni Ventoy ni `sonar_field.sh` n'en dépendent). Un clone anarchique perd
la curation ; il garde le boot/dépannage fonctionnel. Mot de passe
toujours en variable d'environnement (`SONAR_PROTECT_PASSPHRASE`), jamais
en argument. Voir `docs/DEPLOYMENT.md`, section « Protéger le catalogue
contre une reproduction anarchique ».

Rappel déjà vrai sans rien activer : `Secure/Keys/role_secret.key` n'est
jamais copié sur la clé — un clone brut reste bloqué en
Technician/Viewer, sans accès Admin/Forensic/VAULT.

## Avant tout déploiement réel sur disque

Guide détaillé, étape par étape : [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).
**SONAR - SE ne redistribue pas de WinPE pré-construit** (raison de
licence, pas de flemme) — mais `tools/Build-SonarSE-WinPE.ps1` vous aide
à en construire un vous-même en une commande (Windows ADK officiel,
testé de bout en bout) : voir [`docs/WINPE.md`](docs/WINPE.md).
Base de connaissance de référence (981 outils, 73 domaines — **pas** la
source de vérité du déploiement, voir `--profile` ci-dessus) :
[`docs/CATALOG.md`](docs/CATALOG.md).

```bash
# TOUJOURS tester en dry-run d'abord
./sonar_master.sh --disk /dev/sdX --dry-run --source ./SONAR_SOURCE --yes
```

`--disk` **écrit sur le périphérique cible** (Ventoy + payload). Le script
refuse le disque de boot du système et exige une confirmation explicite
(`--yes` ou phrase tapée) avant toute opération destructrice.

## Structure du projet

```
sonar_master.sh     Le script (point d'entrée unique pour l'instant)
CHANGELOG.md          Historique des versions
ROADMAP.md             Ce qui reste à faire, priorisé
.github/workflows/       Workflow CI prêt (bash -n + self-audit + self-test)
```

**La CI n'est pas encore active** : le workflow `.github/workflows/ci.yml`
existe et est prêt, mais ce dépôt n'a pas encore de remote Git distant —
il n'a donc jamais été réellement déclenché par un push. Voir `ROADMAP.md`
(P0) pour le statut actuel.

Le script reste monolithique pour le moment — voir `ROADMAP.md` pour le plan
de découpage modulaire (prévu **après** la mise en place effective de la
CI, jamais avant, pour garder un filet de sécurité pendant le refactor).

## Sécurité — verrou de rôle

Le RBAC (`Viewer/Technician/Senior/Forensic/Admin/Expert`) est verrouillé :
`Viewer`/`Technician` sont en libre-service, mais tout rôle au-dessus exige
un jeton nominatif signé, avec expiration et révocation individuelle. Voir
`--help` (section "Verrou de rôle") pour le détail des commandes.

## Auteur

**Sékou SANOU** — maintenance informatique, Burkina Faso.

## Licence

Apache License 2.0 — voir `LICENSE`.
