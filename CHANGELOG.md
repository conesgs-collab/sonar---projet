# Changelog — SONAR

Format inspiré de [Keep a Changelog](https://keepachangelog.com/). Ce fichier
est la version lisible de l'historique qui vivait jusqu'ici dans l'en-tête de
`sonar_master.sh`. À partir de maintenant, tout changement notable est décrit
ici ET dans un commit Git séparé — le script n'a plus besoin de porter tout
son propre historique en commentaire.

## [3.4.0-role-lock-identity] — 2026-08-16

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
- Hachage à clé (SHA-256), pas un HMAC formel.
- Aucun audit de sécurité externe / pentest.
- Fichier monolithique (~3800 lignes) — refactor modulaire à faire une fois
  la CI en place (jamais avant, pour garder un filet de sécurité).
- Pas de chaîne de distribution signée (GPG) des releases.
- Portabilité Windows/macOS en trompe-l'œil (mentions PowerShell, cœur 100% Bash).
- Pas de documentation utilisateur ni de modèle de chaîne de possession
  (chain of custody) pour le module forensique.
