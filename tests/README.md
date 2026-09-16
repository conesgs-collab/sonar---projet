# Tests

Il n'y a pas de framework de test séparé pour le moment : le script est sa
propre suite de tests, intégrée directement.

- `./sonar_master.sh --self-audit` — vérifie la structure du fichier lui-même
  (dispatch unique, pas de `/dev/sdb` en dur, pas de guard `|| return`
  dangereux, présence des modules critiques...).
- `./sonar_master.sh --self-test` — tests fonctionnels : dépendances système,
  hashchain (intégrité + falsification simulée), verrou de rôle (émission,
  révocation, expiration), modules recovery/backup/forensic/catalogue.

Le workflow CI (`.github/workflows/ci.yml`) est écrit et lance les deux,
plus un run complet `--disk --dry-run` sur un vrai périphérique
`/dev/loop` (pas juste un fichier) — mais il n'est pas encore actif : ce
dépôt n'a pas de remote Git distant, donc rien ne l'a jamais réellement
déclenché. Voir `ROADMAP.md` (P0) pour le statut actuel.

## Pourquoi pas Bats ou un vrai framework ?

Envisageable une fois le découpage modulaire fait (voir ROADMAP.md P1) — plus
facile de tester `lib/security.sh` en isolation qu'un monolithe de 3800
lignes. Pour l'instant, les smoke tests intégrés au script couvrent l'usage
réel bout-en-bout, ce qui a une valeur différente (et complémentaire) des
tests unitaires.
