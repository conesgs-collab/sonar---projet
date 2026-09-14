# Roadmap SONAR

Priorisée pour un développeur solo. Règle d'ordre : **P0 avant P1, toujours**
— en particulier, ne jamais commencer le refactor modulaire (P1) avant que
la CI (P0) soit en place et verte. Sans elle, un refactor qui casse quelque
chose silencieusement ne sera détecté que par hasard.

Précision : le blocage matériel (P0, ci-dessous) est **indépendant** de la
CI. Le refactor P1 peut démarrer dès que la CI est verte, même si l'accès à
du matériel physique reste indisponible — la validation matérielle reste un
P0 ouvert en parallèle, pas une condition bloquante pour le reste.

## P0 — Filet de sécurité (à faire en premier, sans exception)

- [x] Dépôt Git initialisé, script versionné
- [x] CHANGELOG.md extrait de l'historique
- [x] Hook pre-commit local (self-audit/self-test avant tout commit touchant
      le script) — testé en conditions réelles (bloque un commit cassé,
      laisse passer un commit sain)
- [x] Tag `v3.4.0` créé sur le commit d'initialisation
- [ ] CI (`.github/workflows/ci.yml`) branchée sur un vrai remote (GitHub/GitLab/etc.)
      et vérifiée verte au moins une fois — **indépendant du point matériel
      ci-dessous**, peut avancer dès accès à une machine avec Git/réseau,
      même sans matériel de test physique
- [ ] **Validation matérielle réelle** (partiellement débloqué le
      2026-09-14) :
      - [x] Premier déploiement `--disk` complet sur un vrai périphérique
            bloc physique (SSD externe USB, via WSL2 + passthrough disque
            brut `wsl --mount --bare`) : Ventoy installé avec succès,
            persistance 5×8GiB créée, vérification post-déploiement OK,
            **0 erreur, 0 avertissement**. Deux bugs réels trouvés et
            corrigés dans la foulée (`AI_PROVIDER` non définie, `cp -a`
            incompatible avec exFAT) — voir CHANGELOG.md v3.11.2. Aucun
            des deux n'était détectable en `--dry-run`/`--self-test`.
      - [ ] **Boot effectif non encore testé** — le déploiement réussit,
            mais rien ne prouve encore que la clé démarre réellement
            (Secure Boot, ordre de boot BIOS/UEFI spécifique à une
            machine sont des causes d'échec indépendantes d'un
            déploiement propre). Prochaine étape concrète.
      - [ ] Testé sur 2-3 machines différentes (BIOS legacy + UEFI) — un
            seul support testé jusqu'ici, pas encore une validation large.
      **Mitigation logicielle en place depuis v3.5.0** : tout déploiement
      réel (`--disk` sans `--dry-run`) affiche un avertissement explicite
      et exige un acquiescement séparé (`JE COMPRENDS LE RISQUE` ou
      `--accept-hardware-risk`), tracé dans l'audit — toujours actif,
      le premier succès ci-dessus ne change rien à cette exigence pour
      les déploiements suivants.

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
      module forensique. Deux questions concrètes déjà identifiées
      (2026-09-14, voir le commentaire au-dessus de la génération de
      `policy.tsv` dans `sonar_master.sh` pour le détail) à trancher lors
      de cet audit, pas avant :
      - **DESTRUCTIVE vs DEPLOY** : `policy.tsv` refuse DESTRUCTIVE à
        Technician mais autorise DEPLOY (le vrai chemin d'écriture disque
        `--disk`, donc l'opération destructive elle-même) — colonnes en
        conflit. Faut-il exiger CONFIRM aussi pour Technician sur
        `--disk`, fusionner DESTRUCTIVE dans DEPLOY, ou autre chose ?
        Non tranchable sans matériel réel pour valider (même blocage P0
        que la validation matérielle ci-dessus).
      - **FORENSIC** : `sonar_forensic_acquire`/`backup_execute`/
        `forensic_chain_of_custody` restent volontairement en libre-service
        (Technician, sans jeton) — testé et voulu ainsi (v3.10.2/v3.10.3,
        voir CHANGELOG.md). Si un jour on veut restreindre qui peut
        *collecter* (pas seulement qui est *identifié* dans le journal),
        ça change ce cas de test documenté — décision produit, pas un bug.

## P2 — Maturité produit

- [ ] Signature GPG des releases + page de release officielle
- [ ] Documentation utilisateur complète (au-delà du `--help` intégré)
- [x] Modèle de chaîne de possession (chain of custody) formalisé pour le
      module forensique — `--forensic-chain-of-custody` (v3.8.0), croise
      identité opérateur (audit) + statut hashchain. Reste manuel : les
      transferts de possession après l'acquisition (hors du contrôle de
      l'outil par nature) ; usage judiciaire réel encore à valider avec un
      juriste si ce cas se présente.
- [ ] Vrai support Windows natif (au-delà des mentions PowerShell dans le
      catalogue — un pipeline de test qui tourne réellement sous Windows)
- [x] Choix et ajout d'une licence — Apache 2.0 (recommandation motivée :
      standard pour l'outillage d'infrastructure en entreprise, clause de
      brevet, largement accepté par les services juridiques). Copyright
      attribué à Sékou SANOU.

## Dette technique connue (voir aussi CHANGELOG.md)

- Comparaison "temps constant" best-effort, pas formellement vérifiée
- Fichier monolithique en attendant P1
- Aucune gestion multi-technicien concurrente sur le hashchain/audit partagé

## Cadence suggérée (solo)

Une session = un changement cohérent = un commit (ou une poignée de commits
liés) = re-passage de `--self-audit` + `--self-test` avant de considérer que
c'est fini. Éviter les sessions qui mélangent plusieurs sujets sans rapport
(ex : sécurité + renommage + nouvelle fonctionnalité) — ça complique la revue
et le `git bisect` le jour où quelque chose casse.
