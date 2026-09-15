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
      - [x] **Boot effectif réussi** (2026-09-15, HP EliteBook 840 G3,
            Secure Boot activé) — Ventoy affiche son menu, Alpine Linux
            démarre. A révélé et fait corriger un vrai bug : le thème
            Ventoy personnalisé (1920×1080) faisait planter GRUB
            (`alloc magic is broken`) avant même l'affichage du menu —
            voir CHANGELOG.md v3.12.0. Chemin complet : enrôlement MOK
            pour Secure Boot, démarrage à froid pour la détection USB en
            pré-boot, puis désactivation du thème pour isoler le crash
            GRUB.
      - [ ] Testé sur 2-3 machines différentes (BIOS legacy + UEFI) — un
            seul support testé jusqu'ici (UEFI + Secure Boot), pas encore
            de test en mode Legacy/CSM ni sur un autre modèle.
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
      - [x] **Passe interne (2026-09-15)** — pas un substitut à l'audit
        externe, mais une revue adversariale sérieuse sur ce même
        périmètre en attendant. Deux vraies failles trouvées et
        corrigées (voir CHANGELOG.md v3.14.0) : secret HMAC exposé via
        `ps`/`/proc/<pid>/cmdline` (signature des jetons et du filigrane
        de build), et `--role-revoke-token` sans aucun contrôle de rôle
        (déni de service — n'importe quel Technician non authentifié
        pouvait révoquer le jeton de n'importe qui). Les deux questions
        DESTRUCTIVE/FORENSIC ci-dessus restent ouvertes, elles demandent
        une décision produit/matérielle, pas juste du code.

## P0bis — Recentrage stratégique (curation + acquisition)

Demandé explicitement le 2026-09-15 : le catalogue de 981 outils
documentait l'écosystème du dépannage sans jamais dire ce qui allait
réellement sur la clé, et rien ne le téléchargeait de façon ciblée et
vérifiée. Six étapes, un commit par étape, pas de nouvelle fonctionnalité
hors de ce périmètre tant qu'elles ne sont pas faites.

- [x] **Étape 1 — Profils de dépannage fermés et documentés**
      (v3.15.0-profiles-step1, 2026-09-15) : `--profile
      boot-repair|data-recovery|malware|disk-clone|password-reset|full`,
      scénario + outils + pourquoi pour chacun. Catalogue 981 gelé comme
      base de connaissance (`docs/CATALOG.md`), plus source de vérité du
      déploiement. IA/smart-advisor/`--builder` marqués `[EXPÉRIMENTAL]`
      dans `--help` sans suppression.
- [x] **Étape 2 — `--fetch <profil>`** (v3.16.0-fetch-step2, 2026-09-15) :
      télécharge chaque outil unique du profil depuis une URL connue,
      vérifie le SHA-256 contre `SONAR_FETCH_MANIFEST_TSV`, supprime le
      fichier et refuse sur non-correspondance, journalise source+SHA-256
      (audit hashchainé + `SOURCE_DIR/.../FETCH/MANIFEST_FETCH.tsv`). Le
      manifeste est scellé par HMAC (secret de build existant,
      `--fetch-manifest-seal`, rôle VAULT) — `--fetch` refuse tant qu'il
      n'est pas scellé. Les 6 entrées (SystemRescue, TestDisk/PhotoRec,
      ddrescue, ClamAV, Clonezilla, chntpw) ont chacune été vérifiées
      individuellement avant d'être figées (SHA-256 vendeur et/ou
      signature GPG amont contrôlée en direct — détail dans CHANGELOG
      v3.16.0). Testé de bout en bout en conditions réelles
      (téléchargement + vérification effectifs, pas seulement en
      isolation).
- [x] **Étape 3 — Environnement de boot complet** (v3.17.0-boot-env-step3,
      2026-09-15) : le SHA-256 ET la signature GPG amont de SystemRescue
      (cle Francois Dupoux) ont été vérifiés en direct sur l'ISO complète
      (1,3 Go, pas seulement sur un fichier `.sha256` — fermait une
      réserve explicitement laissée ouverte au CHANGELOG v3.16.0).
      L'intégration "par défaut" elle-même ne demandait pas de nouveau
      code de déploiement : `copy_payload_final` copie déjà
      `SOURCE_DIR/ISO` récursivement (`cp -a`), et `VTOY_DEFAULT_
      SEARCH_ROOT` de Ventoy scanne `/ISO` récursivement par défaut —
      donc tout ce que `--fetch boot-repair`/`--fetch disk-clone` dépose
      dans `ISO/Fetched/` atterrit sur la clé et devient bootable sans
      étape supplémentaire. Documenté dans `docs/DEPLOYMENT.md` (nouvelle
      Étape 0bis) plutôt que codé en dur, pour laisser `--disk` offline
      par défaut (pas de téléchargement réseau surprise pendant un
      déploiement).
- [x] **Étape 4 — WinPE via Windows ADK, documentée comme non fournie**
      (v3.18.0-winpe-step4-documented-gap, 2026-09-15) : confirmé
      techniquement impossible à piloter depuis ce script (ADK est un
      outillage Windows uniquement ; le script exige Linux+root via
      `preflight_final` — les deux mondes ne se recoupent pas, ce n'est
      pas un manque d'effort). Suivant l'instruction explicite de
      l'auteur ("documenter plutôt que sauter en silence") :
      `docs/WINPE.md` explique pourquoi, ce qui en dépend
      (réparation côté Windows du profil `boot-repair`), et comment
      l'opérateur construit et ajoute son propre WinPE (`copype` +
      `MakeWinPEMedia`, puis dépôt dans `SOURCE_DIR/ISO/WinPE/` — même
      mécanisme de copie récursive que le reste). `--profile
      boot-repair`/`full` affichent désormais cette limite directement
      ("LIMITE CONNUE"), pas seulement dans un fichier séparé qu'on
      peut manquer.
- [ ] **Étape 5 — déplacée vers SONAR Field** (section dédiée
      ci-dessous, 2026-09-15). Le menu orienté tâche n'est plus vu comme
      un script annexe dans l'environnement de boot de SONAR, mais comme
      l'interface d'un second produit à part entière. Numéro conservé
      (référencé tel quel dans les commits/CHANGELOG existants) plutôt
      que renuméroté.
- [ ] **Étape 6 — Validation matérielle des profils** : au moins 3
      scénarios réels (boot Windows cassé réparé via `boot-repair`,
      fichier supprimé récupéré via `data-recovery`, machine infectée
      nettoyée via `malware`), documentés dans `CHANGELOG.md` — ce qui a
      marché, ce qui a échoué, ce qui a surpris. Dépend de l'accès
      matériel de l'opérateur. Reste une étape SONAR (le builder) :
      valide que les outils *choisis* pour chaque profil fonctionnent
      manuellement, indépendamment de l'existence ou non de SONAR Field.
- [ ] **Étape 7 — déplacée vers SONAR Field** (section dédiée
      ci-dessous, 2026-09-15) — l'accréditation à l'usage de la clé
      n'a de sens que pour un outil qui *agit* sur la machine cible ;
      elle devient le mécanisme d'identification de SONAR Field, pas
      une extension du RBAC de build de SONAR. Numéro conservé pour la
      même raison qu'étape 5.

## SONAR Field — second produit (décision du 2026-09-15)

SONAR (ce dépôt, `sonar_master.sh`) **construit la clé et trace son
origine** — Ventoy, manifeste, filigrane, RBAC, hashchain. Il ne répare
rien lui-même ; les étapes 1-6 ci-dessus ne font que curer, vérifier et
organiser ce qui va *sur* la clé.

**SONAR Field** est un second produit : une fois la clé bootée sur la
machine cible, il orchestre la réparation selon le profil choisi,
journalise ce qu'il fait, et laisse la clé comme trace de
l'intervention. Il ne remplace pas SONAR, il en dépend (une clé qu'il
n'a pas construite lui-même n'a ni profils ni format d'audit à
réutiliser).

- **Ce qui est partagé, concrètement (pas juste en principe)** :
  - Le même `SONAR_PROFILES_TSV`, copié sur la clé au build — les deux
    outils restent synchronisés par construction, pas par discipline
    de maintenance parallèle.
  - Le même format de hashchain d'audit que `sonar_master.sh` — un cas
    (préparation + intervention) se relit comme une seule histoire
    continue, pas deux journaux à recouper à la main.
  - La même discipline de confirmation : rien de destructif sans un
    accord explicite et tracé, mêmes principes que
    `SONAR_HARDWARE_RISK_ACK`/`--accept-hardware-risk` côté build.
  - La même règle de fond : ne jamais rien faire qu'on ne puisse pas
    expliquer après coup — non-destructif par défaut, journalisé,
    honnête sur ses limites.
- **Ce qui n'est PAS partagé** : le rôle. `sonar_master.sh` tourne en
  root sur la machine du technicien, avec RBAC complet (jetons signés,
  révocation en ligne). `sonar_field.sh` tourne sur la machine du
  client, potentiellement hors-ligne — un jeton signé révocable à
  distance n'a pas de sens dans ce contexte. Mécanisme d'identification
  à définir séparément (PIN local le plus probable), voir ancienne
  étape 7 ci-dessus pour le contexte de la demande.
- **Nom retenu** : *SONAR Field*, fichier `sonar_field.sh`, même dépôt,
  même philosophie un-seul-fichier (contrainte réelle : doit tourner
  dans un rescue Linux minimal, sans gestionnaire de paquets fiable).
- **Séquencement** : documenté maintenant, **implémentation non
  commencée** — bloquée sur l'étape 3 (SystemRescue) par nature : on ne
  peut pas écrire l'interface d'un environnement de boot qui n'existe
  pas encore sur la clé. Reprend l'ancien contenu des étapes 5
  (menu orienté tâche) et 7 (accréditation) ci-dessus, qui restent la
  référence du besoin fonctionnel.

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
