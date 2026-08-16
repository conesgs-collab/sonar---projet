# Roadmap SONAR

Priorisée pour un développeur solo. Règle d'ordre : **P0 avant P1, toujours**
— en particulier, ne jamais commencer le refactor modulaire (P1) avant que
la CI (P0) soit en place et verte. Sans elle, un refactor qui casse quelque
chose silencieusement ne sera détecté que par hasard.

## P0 — Filet de sécurité (à faire en premier, sans exception)

- [x] Dépôt Git initialisé, script versionné
- [x] CHANGELOG.md extrait de l'historique
- [ ] CI (`.github/workflows/ci.yml`) branchée sur un vrai remote (GitHub/GitLab/etc.)
      et vérifiée verte au moins une fois
- [ ] Premier tag `v3.4.0` pointant sur le commit actuel
- [ ] Validation matérielle réelle : au moins un déploiement complet sur une
      vraie clé USB jetable, avec boot effectif testé sur 2-3 machines
      différentes (BIOS legacy + UEFI). C'est un test physique, pas quelque
      chose qu'une session de chat peut faire à votre place.

## P1 — Une fois le filet en place

- [ ] Découpage modulaire (`lib/core.sh`, `lib/security.sh`, `lib/deploy.sh`,
      `lib/operational.sh`, `lib/catalog.sh`) — refactor mécanique, testé à
      chaque étape avec `--self-audit`/`--self-test`, jamais en un seul gros
      commit
- [ ] `shellcheck` intégré à la CI une fois le découpage fait (plus
      exploitable sur des fichiers de taille raisonnable que sur un
      monolithe de 3800 lignes)
- [ ] Audit de sécurité externe (pentest ou revue communautaire si le projet
      s'ouvre), en particulier sur le module RBAC/verrou de rôle et le
      module forensique

## P2 — Maturité produit

- [ ] Signature GPG des releases + page de release officielle
- [ ] Documentation utilisateur complète (au-delà du `--help` intégré)
- [ ] Modèle de chaîne de possession (chain of custody) formalisé pour le
      module forensique, si un usage réellement judiciaire est envisagé
- [ ] Vrai support Windows natif (au-delà des mentions PowerShell dans le
      catalogue — un pipeline de test qui tourne réellement sous Windows)
- [ ] Choix et ajout d'une licence

## Dette technique connue (voir aussi CHANGELOG.md)

- Hachage à clé SHA-256 pour les signatures de jeton, pas un HMAC formel
  (documenté comme compromis assumé pour une menace locale, pas réseau)
- Comparaison "temps constant" best-effort, pas formellement vérifiée
- Fichier monolithique en attendant P1
- Aucune gestion multi-technicien concurrente sur le hashchain/audit partagé

## Cadence suggérée (solo)

Une session = un changement cohérent = un commit (ou une poignée de commits
liés) = re-passage de `--self-audit` + `--self-test` avant de considérer que
c'est fini. Éviter les sessions qui mélangent plusieurs sujets sans rapport
(ex : sécurité + renommage + nouvelle fonctionnalité) — ça complique la revue
et le `git bisect` le jour où quelque chose casse.
