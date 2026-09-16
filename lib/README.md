# Structure modulaire prévue (P1)

Ce répertoire contiendra les modules après le découpage du monolithe
`sonar_master.sh`. **Ne pas utiliser tant que la CI (P0) n'est pas verte.**

## Plan de découpage

```
lib/
├── core.sh           # Fonctions utilitaires, logging, hashing, paths
├── security.sh       # RBAC, jetons, audit, hashchain, verrou de rôle
├── deploy.sh         # Ventoy, persistance, payload, post-deploy verify
├── operational.sh    # Launcher, diagnostic, recovery, backup, forensic, network
├── catalog.sh        # Catalogue embarqué, AI queue, AI downloader
└── reports.sh        # Smart advisor, mission report, release report
```

## Règles du découpage

1. **Un commit par module** — jamais tout en un seul commit
2. **`--self-audit` + `--self-test` après CHAQUE module** — si ça casse, on
   corrige immédiatement, on ne continue pas
3. **`sonar_master.sh` devient un entry-point** — il source les modules et
   contient uniquement le dispatch
4. **Aucune dépendance circulaire** — `core.sh` ne source rien, `security.sh`
   ne source que `core.sh`, etc.
5. **Chaque module est autonome** pour le self-test — on peut tester
   `lib/security.sh` isolément

## Ordre d'extraction recommandé

1. `core.sh` (le plus simple, le moins de dépendances)
2. `security.sh` (RBAC + audit + hashchain)
3. `reports.sh` (smart advisor + rapports)
4. `operational.sh` (launcher + modules opérationnels)
5. `catalog.sh` (catalogue + AI)
6. `deploy.sh` (le plus complexe, à faire en dernier)

## État actuel

Depuis l'écriture de ce plan, le script a nettement grossi (SONAR Field,
profils de dépannage, `--fetch`, `--field-export`, WinPE...). Les
estimations de lignes par module ci-dessous datent du plan d'origine et
devront être recalculées au moment réel du découpage — gardées ici comme
ordre de grandeur relatif entre modules, pas comme chiffres à jour.

| Module | Lignes estimées (plan d'origine) | Statut |
|--------|----------------|--------|
| core.sh | ~400 | Planifié |
| security.sh | ~600 | Planifié |
| deploy.sh | ~800 | Planifié |
| operational.sh | ~1200 | Planifié |
| catalog.sh | ~900 | Planifié |
| reports.sh | ~400 | Planifié |

**Total à l'écriture de ce plan** : ~4 385 lignes.
**Total actuel** : ~5 608 lignes dans `sonar_master.sh` (mesuré le
2026-09-16) — la proportion relative entre modules reste indicative, le
découpage réel devra remesurer chaque périmètre.

## Quand commencer ?

- [x] CI workflow créé (`.github/workflows/ci.yml`)
- [ ] CI branchée sur un vrai remote GitHub
- [ ] CI vérifiée verte au moins une fois
- [ ] **Alors seulement** : commencer le découpage
