# Changelog — SONAR

Format inspiré de [Keep a Changelog](https://keepachangelog.com/). Ce fichier
est la version lisible de l'historique qui vivait jusqu'ici dans l'en-tête de
`sonar_master.sh`. À partir de maintenant, tout changement notable est décrit
ici ET dans un commit Git séparé — le script n'a plus besoin de porter tout
son propre historique en commentaire.

## [3.10.0-build-watermark] — 2026-08-17

### Contexte
Suite à la question sur les mécanismes anti-copie : rappel honnête d'abord —
rien en logiciel pur n'empêche un `dd` bit-à-bit d'une clé USB une fois
qu'elle existe (aucune puce sécurisée sur un support USB grand public). Ce
qui est réellement faisable : rendre une copie **traçable** jusqu'à son
build d'origine, pas l'empêcher.

### Ajouté
- Filigrane de build signé (`sonar_generate_build_watermark`), déposé sur
  chaque clé réellement déployée dans `MANIFEST/BUILD_WATERMARK.txt` :
  identifiant de build aléatoire, horodatage, identité de l'opérateur
  (si authentifié via le verrou de rôle), label du disque, signature
  HMAC-SHA256.
- **Secret de signature dédié**, volontairement séparé de celui du verrou de
  rôle (`SONAR_BUILD_SECRET_FILE` ≠ `SONAR_ROLE_SECRET_FILE`) — deux domaines
  de sécurité différents (qui peut agir vs. quel build est-ce), ne doivent
  jamais partager la même clé.
- `--verify-watermark <FICHIER|DOSSIER>` : recalcule la signature contre le
  secret local, confirme ou infirme l'authenticité, et croise un registre
  local (jamais copié sur la clé) pour retrouver le contexte du build.
- Registre local `Secure/Keys/build_registry.tsv` (horodatage, build id,
  opérateur, label) — reste uniquement sur la machine de l'admin.

### Corrigé (trouvé en écrivant le test, pas en l'écrivant puis en le lisant)
En écrivant le test fonctionnel de détection de falsification, un appel à
`sonar_verify_build_watermark` sur un filigrane volontairement corrompu
(censé échouer — c'est le test) était placé en instruction nue sous
`set -e`, ce qui faisait avorter tout le sous-shell de test **avant** de
pouvoir capturer son code de sortie — répétition, dans le code de test
cette fois, du même piège traqué plusieurs fois dans le script lui-même
depuis v3.2.1. Corrigé avec l'idiome sûr `if CMD; then rc=0; else rc=$?; fi`
au lieu d'un `$?` nu ou d'un `|| true` (qui aurait aussi perdu le vrai code
de sortie, `true` devenant la dernière commande de la liste).

### Testé
- Génération réelle d'un filigrane, contenu vérifié (build id, opérateur,
  label, signature).
- Vérification authentique → confirmée, registre local retrouvé.
- Filigrane falsifié (label modifié après coup) → authenticité rejetée,
  détecté correctement.
- Vérification sur une "machine" sans le secret local (cas réaliste : la
  clé retrouvée par quelqu'un d'autre) → métadonnées lisibles, authenticité
  explicitement non vérifiable, pas de fausse confirmation.
- self-audit 14/14, self-test 0 erreur, stable sur deux exécutions
  indépendantes consécutives.



### Contexte
`INCLUDE_VERACRYPT` existait depuis l'en-tête d'origine ("VeraCrypt: Oui")
mais **n'était consulté nulle part** — un drapeau mort, comme le statut
"Physical disk deployment NOT TOUCHED" corrigé en v3.2.1. Avant de coder un
correctif, vérification du fonctionnement réel de la persistance Ventoy :
elle attend un fichier ext4 brut monté directement au démarrage (aucune
intégration VeraCrypt native — voir ventoy.net/en/plugin_persistence.html).
**Chiffrer ce fichier aurait cassé le démarrage de la persistance tout en
donnant une fausse impression de sécurité** — un correctif pire que le bug.

### Ajouté
- `sonar_generate_vault_helper` : déploie `Scripts/sonar-vault.sh` sur la clé
  — un coffre chiffré autonome (gpg AES-256), exécuté plus tard sur le
  terrain par le technicien, **totalement indépendant** de la chaîne de
  démarrage/persistance Ventoy. Ne peut donc jamais casser le boot.
  - `sonar-vault.sh create <source> <coffre.enc>` / `open <coffre.enc> <sortie>`
  - Mot de passe jamais stocké, jamais écrit sur disque, saisie masquée
  - Refuse d'écraser un fichier existant ; refuse si confirmation ≠ mot de
    passe initial
  - Détecte `veracrypt` s'il est présent sur la machine où le script est
    *exécuté* (pas celle qui a construit la clé) et prévient clairement
    que ce script ne le pilote pas automatiquement, en repli sur gpg
- En-tête et aide corrigés : plus aucune mention de "VeraCrypt: Oui" pour
  quelque chose qui n'existe pas.

### Testé
- Round-trip réel : création d'un coffre, vérification par `file` que le
  contenu est bien `AES with 256-bit key salted & iterated`, contenu en
  clair absent du blob, ouverture avec le bon mot de passe restitue le
  contenu exact.
- Mauvais mot de passe → échec de déchiffrement confirmé.
- Refus d'écraser un coffre existant → confirmé.
- Mots de passe non concordants à la création → rejeté.
- Nouveau test fonctionnel automatisé dans `--self-test` : génère le script,
  fait un vrai aller-retour chiffrement/déchiffrement, compare le fichier
  récupéré à l'original (`diff`).
- self-audit 13/13, self-test 0 erreur.



### Contexte
Dette connue depuis le début du module forensique : `sonar_forensic_acquire`
copie les preuves et calcule les SHA-256, mais rien ne formalisait ça en
document de chaîne de possession exploitable — la dette explicitement notée
dans la roadmap ("pas de modèle de chaîne de possession"). Devenu réalisable
proprement maintenant que l'identité de l'opérateur se propage à tout
l'audit (v3.7.0) et que le hashchain est vérifiable à la demande (v3.2.0).

### Ajouté
- `--forensic-chain-of-custody <DOSSIER_PREUVES> [N_DOSSIER]` : génère un
  document de chaîne de possession à partir d'une acquisition existante.
  Croise automatiquement :
  - l'entrée d'audit `FORENSIC_ACQUIRE` correspondante (opérateur, identité,
    horodatage) ;
  - une empreinte SHA-256 de méta-intégrité sur la liste de hachage
    elle-même (détecte une modification de la liste après coup) ;
  - le statut du hashchain d'audit au moment de la génération (INTACT /
    COMPROMIS).
  Laisse un tableau à compléter manuellement pour les transferts de
  possession ultérieurs (transport, stockage, remise à un tiers) — hors du
  contrôle de SONAR par nature, mais ancré aux preuves cryptographiques que
  l'outil peut effectivement attester.
- Accessible aussi via le launcher interactif (option 19).
- Nouveau test fonctionnel bout-en-bout dans `--self-test` : émet un jeton
  Forensic nominatif, effectue une acquisition, génère la chaîne de
  possession, vérifie que le document lie bien l'identité de l'opérateur et
  le statut du hashchain.

### Testé
- Flux complet manuel : jeton `e.legrand` (rôle Forensic) → acquisition de 2
  fichiers → génération avec numéro de dossier `DOSSIER-2026-042` → document
  vérifié contenant `Operateur: Forensic (identity=e.legrand)`, empreinte de
  méta-intégrité, statut `INTACT`.
- Dossier invalide (pas une acquisition SONAR) → rejeté proprement, message
  clair, hashchain resté intact après l'échec.
- self-audit 12/12, self-test 0 erreur (9 tests fonctionnels sur le verrou
  de rôle et la chaîne de possession).



### Contexte
Depuis v3.4.0, l'identité authentifiée (`SONAR_ROLE_IDENTITY`) n'apparaissait
que dans les événements du verrou de rôle lui-même
(`ROLE_ELEVATION_GRANTED`). Toute action effectuée *ensuite* sous ce rôle —
un diagnostic, une sauvegarde, une acquisition forensique, un vrai
déploiement `--disk` — ne traçait que le rôle, pas la personne. Ça limitait
la valeur réelle des jetons nominatifs pour la traçabilité d'ensemble.

### Changé
- `sonar_audit` ajoute désormais automatiquement `identity=<nom>` à *toute*
  entrée d'audit dès qu'une identité authentifiée est active pour la
  session — pas seulement aux événements de verrou. Source unique de
  vérité : les appelants n'ont plus besoin (et ne doivent plus) l'inclure
  manuellement.
- Suppression de la duplication manuelle dans `ROLE_ELEVATION_GRANTED`
  (redondante avec le nouveau comportement automatique).
- Nouveau test fonctionnel dans `--self-test` : émet un jeton, exécute une
  action sans rapport avec le verrou de rôle (`--diagnostic`), vérifie que
  l'entrée d'audit résultante porte bien `identity=`.

### Testé
- Confirmé manuellement : un jeton émis pour `j.dupont`, utilisé pour lancer
  `--diagnostic`, produit une entrée `DIAGNOSTIC_REPORT` portant
  `identity=j.dupont` dans le journal d'audit.
- Hashchain vérifié intact malgré le changement de format des `details`
  (4 entrées, aucune rupture).
- self-audit 11/11, self-test 0 erreur (7 tests fonctionnels sur le verrou
  de rôle, dont le nouveau).



### Contexte
Dette technique documentée depuis v3.4.0 : la signature des jetons de rôle
était un hachage à clé maison (`sha256(secret|identity|role|expiry)`), pas un
HMAC formel — trade-off explicitement assumé faute d'`openssl` confirmé
disponible. `openssl` s'est avéré présent ; plus de raison de garder la
version plus faible.

### Changé
- `sonar_role_sign` utilise désormais un **vrai HMAC-SHA256** (RFC 2104, via
  `openssl dgst -sha256 -hmac`) au lieu du hachage à clé maison.
- Nouveau garde `sonar_require_openssl` : échec **net et explicite** si
  `openssl` est absent au moment de signer/vérifier un jeton — jamais de
  repli silencieux vers une construction plus faible. Le bootstrap du
  secret n'en a pas besoin (généré via `sha256sum`, inchangé) ; seules
  l'émission et la vérification de jeton l'exigent.
- `openssl` ajouté à la liste vérifiée par `--dependencies-report`.

### Testé
- Signature vérifiée : 64 caractères hex (SHA-256), format HMAC standard.
- Jeton légitime accordé, jeton avec signature falsifiée rejeté (motif
  "signature invalide").
- Absence d'`openssl` simulée par un `PATH` complet (1292 binaires du
  système réel) reconstruit sans lui : `--role-bootstrap` fonctionne toujours
  (n'en dépend pas), `--role-issue-token` échoue proprement avec message
  explicite (pas de crash silencieux, pas de repli affaibli).
- self-audit 11/11, self-test 0 erreur, pipeline `--disk --dry-run` sur
  `/dev/loop` : EXIT 0.



### Contexte
Aucun accès à du matériel physique pour valider un vrai boot Ventoy pour le
moment (bloqué côté opérateur, pas résolu). En attendant, il fallait combler
un vrai trou : rien n'avertissait l'opérateur d'un **vrai** déploiement
(`--disk` sans `--dry-run`) que ce build n'a jamais été validé sur du
matériel réel — le statut `NOT_TESTED` n'apparaissait que dans des rapports
consultés à part (`--self-test`, `--release-report`), jamais au moment où ça
compte : au moment d'écrire sur un vrai périphérique.

### Ajouté
- Garde-fou runtime `sonar_require_hardware_risk_ack` : tout déploiement réel
  affiche un avertissement explicite et exige soit la phrase tapée
  `JE COMPRENDS LE RISQUE`, soit `--accept-hardware-risk` /
  `SONAR_HARDWARE_RISK_ACK=true` pour l'automatisation.
- **Séparé de `--yes`** volontairement : scripter `--yes` seul (confirmation
  d'effacement) ne suffit plus à sauter cet acquiescement précis — les deux
  gardes sont indépendants et tous deux nécessaires pour un déploiement réel
  entièrement non interactif.
- Entrée d'audit `HARDWARE_RISK_ACKNOWLEDGED` (méthode : flag/env, interactif,
  ou refusé).
- Testé en conditions réelles sur `/dev/loop` (déploiement non-dry-run) :
  refus par défaut confirmé, acceptation par phrase tapée confirmée,
  acceptation par flag confirmée, traçabilité dans l'audit confirmée.

### Non résolu
Ceci est un **filet logiciel**, pas un remplacement du test matériel réel —
voir `ROADMAP.md` (P0, toujours ouvert, en attente d'accès à du matériel).



### Ajouté
- Jetons de rôle **par identité** (`identity:role:expiry:signature`) au lieu
  d'un jeton unique partagé par rôle.
- `--role-issue-token <ROLE> <IDENTITE> [JOURS=30]` — jeton nominatif avec
  expiration intégrée.
- `--role-revoke-token <JETON>` — révocation individuelle, sans effet sur les
  autres porteurs du même rôle, sans rotation du secret racine.
- `sonar_const_time_eq` — comparaison de signature best-effort à temps
  constant (remplace `[[ == ]]`, qui court-circuite au premier octet
  différent).
- L'identité authentifiée apparaît dans `--security-status` et dans les
  entrées d'audit `ROLE_ELEVATION_GRANTED`.
- 3 nouveaux tests fonctionnels dans `--self-test` : jeton nominatif accordé,
  jeton révoqué rejeté, jeton expiré (forgé et re-signé) rejeté.

### Corrigé
- Aucun (fonctionnalité pure sur la base v3.3.0).

## [3.3.0-role-lock] — 2026-08-16

### Ajouté
- Verrou de rôle : `SONAR_ROLE=Admin` / `--role Admin` sans jeton valide est
  désormais rétrogradé automatiquement vers `Technician`.
- `--role-bootstrap` — initialise le secret local une seule fois (chmod 600).
- `--role-issue-token <ROLE>` (v1, remplacé en 3.4.0) — émission par rôle.
- Garde-fou de non-régression dans `--self-audit` / `--self-test` contre le
  pattern `|| return` dangereux réintroduit.

### Sécurité
- **Faille corrigée** : avant ce correctif, n'importe qui pouvait s'attribuer
  n'importe quel rôle (y compris Admin/VAULT/FORENSIC) simplement en
  définissant la variable d'environnement `SONAR_ROLE`, sans aucune
  authentification.

## [3.2.1-smart-advisor] — 2026-08-15

### Corrigé
- **Bug critique trouvé par test réel** (`--dry-run` sur un vrai périphérique
  bloc, pas par relecture de code) : le pattern `[[ condition ]] || return`
  sans code de sortie explicite fait hériter à `return` le code d'échec du
  test quand la condition est fausse. Sous `set -e`, ceci terminait le script
  **silencieusement**, sans aucun message d'erreur, dès qu'une fonction
  utilisant ce pattern était appelée en instruction simple.
- Impact réel confirmé : tout `--dry-run` avortait sans un mot (via
  `generate_readme_final`), de même pour `--no-ai-assistant`, `--ai off`, ou
  `--persistence 0`.
- Corrigé dans `install_ai_layer_final`, `run_ai_final`,
  `create_persistence_final`, `generate_readme_final`.

## [3.2.0-smart-advisor] — 2026-08-15

### Ajouté
- **Smart Advisor** (`--smart-advisor`) — moteur de règles déterministe
  (aucun LLM impliqué) corrélant dépendances, intégrité du hashchain,
  fraîcheur du manifeste, couverture de validation du catalogue, scellé et
  rôle en un verdict priorisé avec raisonnement explicite.
- **Vérification réelle du hashchain** (`--verify-hashchain`) — recalcule
  toute la chaîne pour détecter une falsification a posteriori du journal
  d'audit (fonctionnalité absente jusque-là : on ajoutait des entrées sans
  jamais les vérifier).
- **Scellé d'intégrité du catalogue embarqué** (`--catalog-seal` /
  `--catalog-verify-seal`, rôle VAULT).
- **Vérification post-déploiement** intégrée au pipeline `--disk` : relit
  chaque fichier copié directement depuis la clé montée et compare au
  SHA-256, là où `validate_final` ne vérifiait que la structure.
- **Rapport de mission unifié** (`--mission-report`).

## [Renommage] — NEXUS → SONAR

Le projet s'appelait initialement NEXUS. Renommage global de toutes les
fonctions, variables d'environnement, bannières et messages.

## [3.1.0-final-integrated] et antérieur

Fusion de `nexus_master.sh` et `NEXUS_MASTER_FINAL_V3.sh` : racine
d'exécution stable, suivi des points de montage avec démontage automatique,
persistance via `dd` au lieu de `truncate`, correctifs de robustesse divers,
couche opérationnelle V2 (launcher, diagnostic, self-test, recovery/backup
plans, forensic workspace, diagnostic réseau, builder, rapports).

---

## Non résolu / dette connue

Ce qui manque encore pour que l'outil soit considéré mature — voir aussi
`ROADMAP.md` :

- **Jamais testé sur du vrai matériel.** Tout ce qui est validé l'a été en
  `--dry-run` et sur `/dev/loop`, jamais un vrai boot Ventoy/Secure Boot.
- Hachage à clé (SHA-256), pas un HMAC formel. ~~Résolu en v3.6.0~~
- Aucun audit de sécurité externe / pentest.
- Fichier monolithique (~3800 lignes) — refactor modulaire à faire une fois
  la CI en place (jamais avant, pour garder un filet de sécurité).
- Pas de chaîne de distribution signée (GPG) des releases.
- Portabilité Windows/macOS en trompe-l'œil (mentions PowerShell, cœur 100% Bash).
- Pas de documentation utilisateur ni de modèle de chaîne de possession
  (chain of custody) pour le module forensique.
