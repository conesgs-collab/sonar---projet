# SONAR

Outil de déploiement automatisé pour clé USB de maintenance IT (Ventoy +
persistance + module forensique/backup/recovery + couche RBAC), en un seul
script Bash auto-vérifiable.

> **Statut : CANDIDATE.** Validé par tests automatisés (`--self-audit`,
> `--self-test`) et par des runs `--dry-run` sur périphérique bloc réel
> (`/dev/loop`). **Jamais encore testé sur un vrai déploiement USB /
> boot réel.** Voir `CHANGELOG.md` (section "Non résolu") et `ROADMAP.md`
> avant tout usage en production.

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

## Avant tout déploiement réel sur disque

Guide détaillé, étape par étape : [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).
Liste complète des 936 outils couverts (69 domaines) :
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
.github/workflows/       CI : bash -n + self-audit + self-test à chaque push
```

Le script reste monolithique pour le moment — voir `ROADMAP.md` pour le plan
de découpage modulaire (prévu **après** la mise en place de la CI, jamais
avant, pour garder un filet de sécurité pendant le refactor).

## Sécurité — verrou de rôle

Le RBAC (`Viewer/Technician/Senior/Forensic/Admin/Expert`) est verrouillé :
`Viewer`/`Technician` sont en libre-service, mais tout rôle au-dessus exige
un jeton nominatif signé, avec expiration et révocation individuelle. Voir
`--help` (section "Verrou de rôle") pour le détail des commandes.

## Auteur

**Sékou SANOU** — maintenance informatique, Burkina Faso.

## Licence

Apache License 2.0 — voir `LICENSE`.
