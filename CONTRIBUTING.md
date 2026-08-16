# Contribuer (guide solo)

Ce projet a un seul contributeur pour le moment. Ce document sert de
rappel à froid, pas de règlement pour une équipe.

## Avant de commencer une session

```bash
git pull   # une fois qu'un remote existe
git config --get core.hooksPath   # doit afficher "hooks/" — sinon: git config core.hooksPath hooks/
```

## Pendant la session

- **Un sujet par session.** Ne pas mélanger sécurité + renommage + nouvelle
  fonctionnalité dans les mêmes commits — ça complique la revue à froid et
  le `git bisect` le jour où quelque chose casse.
- Tout changement touchant `Secure/`, le RBAC, ou le verrou de rôle doit
  s'accompagner d'un test fonctionnel qui prouve l'attaque qu'il empêche
  (voir `tests/README.md` — c'est le pattern suivi pour le verrou de rôle
  et les jetons par identité : émission, révocation, expiration testées
  en conditions réelles avant tout commit).
- Respecter l'ordre de `ROADMAP.md` : ne jamais commencer un refactor
  structurel (P1) tant que le filet de sécurité (P0 — CI vérifiée verte
  sur un vrai remote) n'est pas en place.

## Avant de committer

Le hook `hooks/pre-commit` s'en charge automatiquement pour tout commit
touchant `sonar_master.sh` :
1. `bash -n` (syntaxe)
2. `--self-audit` (structure : dispatch unique, pas de guard dangereux, etc.)
3. `--self-test` (fonctionnel : dépendances, hashchain, verrou de rôle...)

Un commit est bloqué si l'une de ces étapes échoue. `SONAR_SKIP_HOOK=1`
permet de forcer en cas d'urgence réelle — à corriger au commit suivant,
jamais laisser traîner.

## Messages de commit

Format libre, mais toujours inclure :
- Ce qui a changé (une ligne de résumé)
- Pourquoi (le problème que ça résout, pas juste "fix bug")
- Comment ça a été validé (self-audit/self-test, ou test manuel spécifique
  — voir les commits existants pour le ton attendu)

## Versions

Bump `SONAR_VERSION` dans `sonar_master.sh` + entrée `CHANGELOG.md` +
tag Git (`git tag -a vX.Y.Z -m "..."`) à chaque changement notable — pas
seulement aux "grosses" versions. Un tag ne coûte rien et rend un
`git bisect` ou un retour en arrière immédiat.
