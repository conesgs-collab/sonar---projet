# Audit de sécurité adversarial de `sonar_master.sh` — 2026-09-21

Périmètre demandé : module RBAC / verrou de rôle, gestion des secrets (HMAC, ECDSA), signature et vérification de
jetons, hashchain et intégrité de l'audit. Modèle de menace du projet (CHANGELOG 3.14.0) : un opérateur **au même
niveau OS** qui tente une auto-escalade occasionnelle — pas un attaquant réseau.

**Méthode.** Lecture des lignes 130-700 et 6350-6400, puis **chaque hypothèse d'attaque rejouée** sur une racine de
confiance isolée (`SONAR_ROOT` temporaire, WSL Ubuntu, root). Ce qui n'a pas pu être rejoué est marqué « à vérifier
manuellement ». Les numéros de ligne sont ceux de `sonar_master.sh` **avant** les correctifs de 3.49.2.

**Écarté car déjà documenté comme volontaire** : racine de confiance du secret de build créée à la première
utilisation (3.36.2, « Non résolu ») ; DESTRUCTIVE/FORENSIC non appliqués (3.36.2 et commentaire de
`sonar_security_init`) ; comparaison « constant-time » au mieux (commentaire l. 171-174) ; dépendance à `python3`.

**Contexte qui change la gravité** : le script exige root (`preflight_final`). Le RBAC sépare donc des opérateurs
équivalents à root : c'est de la **responsabilité et de la traçabilité**, pas un contrôle d'accès étanche. Un
opérateur root peut lire le secret. Les trouvailles ci-dessous comptent parce qu'elles contournent le verrou
**sans** avoir à lire le secret, et surtout parce qu'elles rendent la trace d'audit peu fiable.

## Corrigées dans 3.49.2 (avec test de non-régression)

### 1. HAUTE — verrou de rôle contourné par une variable d'environnement (l. 372-374)
`sonar_role_enforce_lock` retourne immédiatement si `SONAR_ROLE_LOCK_ENFORCED_SIG` égale `rôle:jeton:fichier`. La
variable n'était **jamais initialisée** : l'environnement la fournissait.
```
SONAR_ROLE=Admin SONAR_ROLE_LOCK_ENFORCED_SIG='Admin::' ./sonar_master.sh --security-status   →  role: Admin
```
Rôle Admin **sans aucun jeton**, une seule variable. Rejoué avant : `Admin` ; après : `Technician`.
**Correctif** : affectation simple `SONAR_ROLE_LOCK_ENFORCED_SIG=""` à la déclaration (1 ligne).

### 2. MOYENNE — falsification du journal via `SONAR_ROLE_IDENTITY` (l. 600-616)
`event` et `details` sont assainis (tabulation, saut de ligne) l. 600-601, **puis** l'identité est ajoutée l. 612/614,
**après** l'assainissement. Pour un rôle libre-service (Viewer/Technician), l'identité est une variable d'environnement
non vérifiée. Avec `SONAR_ROLE_IDENTITY=$'x\n2026-01-01T00:00:00Z\tAdmin\tROLE_ELEVATION_GRANTED\trole=Admin;identity=root'`,
4 lignes s'ajoutaient à `audit.log` dont une **fausse élévation Admin** plausible ; `--verify-hashchain` signalait
ensuite « COMPROMISE 4/5 » (fausse alerte qui ruine la crédibilité de la vérification).
**Correctif** : `sonar_sanitize_value` appliqué à l'identité au moment de l'ajout. Après : 1 ligne, chaîne intègre.

## NON corrigées — à trancher (décision produit ou risque de casser des workflows)

### 3. HAUTE — l'émission d'un jeton n'exige aucun rôle (l. 262-284, dispatch l. 6700)
`sonar_role_issue_token` ne consulte jamais `SONAR_ROLE`. Rejoué : en `SONAR_ROLE=Technician`,
`--role-issue-token Admin mallory` imprime un jeton valide ; `SONAR_ROLE=Admin SONAR_ROLE_TOKEN=<jeton>` donne
`role: Admin  identity: mallory`. L'audit consigne `ROLE_TOKEN_ISSUED` sous le rôle **Technician** : la trace existe,
le contrôle non. **Non corrigé** : les tests et le README (l. 45) utilisent l'émission sans rôle, et il faut décider de
la cérémonie du **premier** jeton Admin. **Options** : (a) refuser l'émission à un rôle libre-service dès qu'un premier
jeton élevé existe (ou exiger un jeton élevé), le premier étant émis au `--role-bootstrap` ; (b) assumer et documenter
que l'émission = « qui peut lire le secret », donc le RBAC est de la traçabilité.

### 4. HAUTE — la racine de confiance est surchargeable par l'environnement (l. 137-143, 176-177)
`SONAR_ROLE_SECRET_FILE`, `SONAR_ROLE_REVOKED_FILE`, `SONAR_POLICY_FILE`, `SONAR_AUDIT_LOG`, `SONAR_HASHCHAIN_LOG`,
`SONAR_SECURITY_DIR`, `SONAR_ROOT` sont tous en `${VAR:-défaut}`. Rejoué : un opérateur crée **son propre** secret
(`SONAR_ROLE_SECRET_FILE=/tmp/mine.key … --role-bootstrap`), s'émet un jeton Admin, et l'utilise avec le même
`SONAR_ROLE_SECRET_FILE` → `role: Admin` ; avec le secret officiel, le même jeton est refusé (le bypass ne marche que
si l'on choisit sa racine). Et `SONAR_AUDIT_LOG=/dev/null SONAR_HASHCHAIN_LOG=/dev/null` fait tourner n'importe quelle
commande **sans aucune trace** (code retour 0). **Non corrigé** : les 250 tests reposent sur `SONAR_ROOT` isolé.
**Correctif minimal** : n'honorer ces surcharges que si `SONAR_TEST_MODE=1` (posé par `--self-test`) ; sinon les
ignorer ou refuser avec un message. **À vérifier manuellement** : sous `sudo` avec `env_reset` (défaut), l'environnement
de l'appelant est effacé, ce qui limite ce vecteur — à confirmer sur la configuration `sudoers` réelle.

### 5. MOYENNE — la chaîne de hachage n'est pas ancrée : troncature et réécriture non détectées (l. 625-630, 653-663)
Chaîne SHA-256 **sans clé**. Rejoué sur 6 entrées : (a) suppression des 2 dernières → « **intègre**, 5 entrées » ;
(b) ligne 2 falsifiée puis **toute la chaîne recalculée** (10 lignes de Python) → « **intègre** ». Une modification
isolée sans recalcul **est** détectée (« Rupture à la ligne 3 »). Le journal détecte donc les éditions maladroites, pas
un attaquant qui connaît l'algorithme. **Correctif minimal** : écrire à chaque entrée un fichier `hashchain.head`
(nombre d'entrées + dernier hachage) signé par HMAC avec le secret de rôle, que `--verify-hashchain` compare.

### 6. MOYENNE — un `.lock` inutilisable fait perdre l'audit sans arrêter l'action (l. 623-631)
`{ … } 201>>"${SONAR_HASHCHAIN_LOG}.lock"` : si l'ouverture échoue, bash saute **tout le bloc** (aucune écriture dans
`audit.log` ni `hashchain.log`). Rejoué (`hashchain.log.lock` créé comme dossier) : le jeton est émis, **0 entrée**
ajoutée, une seule ligne sur stderr ; le code retour n'est non nul ici que parce que `sonar_audit` est la dernière
commande. **Correctif minimal** : ouvrir le verrou avant (`exec 201>>… || return 1`) et faire échouer les actions
sensibles si l'audit ne peut pas être écrit (fail-closed).

### 7. MOYENNE — le jeton passe en argument de ligne de commande (l. 1203, aussi `--role-revoke-token`, l. 6701)
`--role-token <JETON>` place un **identifiant porteur valable jusqu'à N jours** dans `argv`, lisible via `ps` /
`/proc/<pid>/cmdline` par tout processus local. C'est la même classe que la fuite du secret HMAC corrigée en 3.14.0,
pour un jeton. Lecture du code (le seul passage du jeton par argv est cette option). **Correctif minimal** : n'accepter
le jeton que par `SONAR_ROLE_TOKEN` / `SONAR_ROLE_TOKEN_FILE` / stdin, et déclarer l'option obsolète.

## BASSES

- **Révocation par sous-chaîne** (l. 252-256) : `grep -qF "$token_id"` sur toute la ligne ; si `sonar_hash_str` échoue
  (ni `sha256sum` ni `shasum`), `token_id` est vide et `grep -qF ""` correspond à tout → tous les jetons « révoqués »
  (fermeture par défaut, mais déni de service). Non exploitable pour contourner. Correctif : comparer la colonne 5 avec `awk`.
- **Aucune hiérarchie de révocation** (l. 300-304) : tout rôle élevé (Senior) peut révoquer le jeton d'un Admin.
- **Jetons identiques dans la même seconde** (l. 280-282) : HMAC déterministe ; deux émissions pour la même
  identité/rôle/seconde donnent le même jeton, révoquer l'un révoque l'autre.
- **Création des secrets** (l. 229-230, 6368-6369) : `printf > fichier; chmod 600` crée le fichier avec l'umask du
  processus avant le `chmod` ; atténué car le dossier passe en `700` juste avant. Le `chmod 700 "$(dirname …)"` s'applique
  aussi au dossier parent que désigne une surcharge d'environnement (ex. `SONAR_ROLE_SECRET_FILE=/x/secret` → `chmod 700 /x`).
  Correctif : `( umask 077; … )`.
- **`hash="UNAVAILABLE"`** (l. 629, 657) : sans outil SHA-256, les entrées sont écrites avec un hachage factice que la
  vérification, faite sans outil non plus, accepte. **À vérifier manuellement** (non rejoué : nécessite de retirer `sha256sum`).
- **`SONAR_ROLE_TOKEN_FILE`** (l. 378-380) : lu sans contrôle de propriétaire ni de droits. **À vérifier manuellement.**

## Ce qui a été revu et n'a rien donné
- **Ambiguïté de canonicalisation** du message HMAC `identité|rôle|expiration` : à l'émission l'identité est restreinte à
  `[A-Za-z0-9._@-]` et le rôle à une liste ; au contrôle, rôle et expiration (numérique) ne contiennent pas `|`, donc deux
  triplets distincts ne produisent pas le même message. Aucune collision trouvée.
- **Secret dans `argv`** : `sonar_hmac_sha256_file` ne fait passer que le chemin du secret (correctif 3.14.0 confirmé).
- **Signature ECDSA** (`sonar_diag.sh`, hors `sonar_master.sh`) : la clé privée n'est jamais passée en argument, seul son
  chemin ; `--sign-keygen` crée la clé en `umask 077` et refuse d'écraser. Rien de bloquant ; la rotation des clés n'est pas traitée.
- **Politique absente** : `sonar_role_can` échoue en refusant (fermeture par défaut).
- **Déni de service sur l'expiration** (entier énorme) : le dépassement rend le jeton expiré, jamais valide.

## Limites de cet audit
Un seul relecteur (moi), statique + rejeu ciblé ; pas de revue de `sonar_field_pin_*` ni du chemin `--disk` ; aucun test
sous `sudo` réel ni sur une machine multi-utilisateurs. Ce n'est pas l'audit externe que le ROADMAP réserve.
