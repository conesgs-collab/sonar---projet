#!/bin/bash
#===============================================================================
# SONAR - SE — SCRIPT DE DÉPLOIEMENT AUTOMATISÉ - OUTIL DE MAINTENANCE IT PORTABLE
#===============================================================================
# Généré le        : 2026-08-15
# Disque cible     : (obligatoire, fourni via --disk /dev/sdX)
# Label            : IT-TOOLKIT
# Batch            : 1 disque(s)
# Accréditation    : Niveau 4
# Ventoy           : v1.1.17 (GPT + Secure Boot)
# Persistance      : 5 x 8 Go
# Coffre chiffré   : Oui (sonar-vault.sh, gpg AES-256 — sans lien avec la
#                    persistance Ventoy ci-dessus, jamais chiffrée par SONAR)
# Journalisation   : Oui
# Vérif. checksum  : Oui
# README auto      : Oui
# Effacement sécur : Non
# Test vitesse USB : Non
# Mode dry-run     : Non
# Taille totale    : 64.2 Go
# Outils           : 164 (29 ISO, 120 portables, 15 scripts)
#-------------------------------------------------------------------------------
# Statut de fusion : CANDIDATE — consolidation de sonar_master.sh avec les
#                    innovations de SONAR_MASTER_FINAL_V3 :
#                    - Racine d'exécution stable (SONAR_SCRIPT_DIR/SONAR_ROOT),
#                      indépendante du répertoire courant de l'appelant
#                    - Suivi des points de montage (SONAR_MOUNTED_PARTS) avec
#                      démontage automatique en cleanup() en cas d'erreur
#                    - Persistance créée via dd (progression visible) au lieu
#                      de truncate (fichiers réellement alloués, pas creux)
#                    - Correctifs de robustesse: xargs -0 -r, return 0 explicite
#                      après GPG/RBAC, rmdir de sécurité si montage échoue
#                    - Nouvelle couche opérationnelle V2 : launcher interactif,
#                      diagnostic, self-test, plans recovery/backup, espace
#                      forensic, diagnostic réseau, builder de profils, rapports
#                      de release/dépendances, catalogue d'outils embarqué V2
#                    - Modules recovery/backup/forensic "execute" séparés des
#                      modules "plan", avec confirmation explicite par phrase
#                    Revendications matériel/boot à valider sur poste réel.
#-------------------------------------------------------------------------------
# v3.2.0 — Couche « intelligence » (moteur de règles déterministe, PAS un LLM) :
#                    - Smart Advisor (--smart-advisor) : corrèle dépendances,
#                      intégrité du hashchain, fraîcheur du manifeste, couverture
#                      de validation du catalogue, scellé et rôle en un verdict
#                      priorisé avec raisonnement explicite (score /100 pondéré)
#                    - Vérification réelle du hashchain (--verify-hashchain) :
#                      recalcule toute la chaîne pour détecter une falsification
#                      a posteriori du journal d'audit (fonctionnalité absente
#                      jusqu'ici : on ajoutait des entrées sans jamais vérifier)
#                    - Scellé d'intégrité du catalogue embarqué (--catalog-seal /
#                      --catalog-verify-seal, rôle VAULT) : détecte une édition
#                      silencieuse du catalogue de 2900+ lignes
#                    - Vérification post-déploiement (sonar_post_deploy_verify_final)
#                      intégrée au pipeline --disk : relit chaque fichier copié
#                      directement depuis la clé montée et compare au SHA-256,
#                      là où validate_final ne vérifiait que la structure
#                    - Rapport de mission unifié (--mission-report)
#-------------------------------------------------------------------------------
# v3.2.1 — Correctif critique de fiabilité (trouvé par test réel --dry-run sur
#          un vrai périphérique bloc, pas par relecture) :
#          Le pattern `[[ condition ]] || return` (sans code de sortie explicite)
#          fait hériter à `return` le code d'échec du test quand la condition
#          est fausse. Sous `set -e`, ceci termine tout le script SILENCIEUSEMENT
#          (aucun message d'erreur), dès qu'une fonction utilisant ce pattern est
#          appelée en instruction simple. Impact réel confirmé : le déploiement
#          avortait sans un mot dès --dry-run (via generate_readme_final), et
#          aurait fait de même avec --no-ai-assistant, --ai off ou
#          --persistence 0. Corrigé dans install_ai_layer_final, run_ai_final,
#          create_persistence_final et generate_readme_final (`|| return 0`
#          explicite). Le pipeline --dry-run complet a été rejoué de bout en
#          bout après correctif (sur /dev/loop, EXIT CODE 0).
#-------------------------------------------------------------------------------
# v3.3.0 — Verrou de rôle (SONAR_ROLE / --role) :
#          Jusqu'ici SONAR_ROLE="${SONAR_ROLE:-Technician}" acceptait n'importe
#          quelle valeur non authentifiée — `SONAR_ROLE=Admin` ou `--role Admin`
#          donnait instantanément les droits VAULT/AUDIT/FORENSIC en écriture.
#          Correctif : Viewer/Technician restent en libre-service (aucune
#          régression sur l'usage courant) ; Senior/Forensic/Admin/Expert
#          exigent désormais un jeton dérivé d'un secret local
#          (Secure/Keys/role_secret.key, chmod 600, généré une seule fois via
#          --role-bootstrap). --role-issue-token <ROLE> émet le jeton pour un
#          rôle (n'importe qui pouvant déjà lire le secret protégé par le
#          système de fichiers). Sans jeton valide (--role-token /
#          SONAR_ROLE_TOKEN / SONAR_ROLE_TOKEN_FILE), le rôle demandé est
#          rétrogradé vers Technician avec avertissement + entrée d'audit
#          ROLE_ELEVATION_BLOCKED. Testé : escalade bloquée, jeton valide
#          accepté, jeton falsifié rejeté, hashchain intact après les tests,
#          --self-test inclut désormais un test fonctionnel d'escalade bloquée.
#-------------------------------------------------------------------------------
# v3.4.0 — Jetons par identité, expiration, révocation :
#          Le verrou v3.3.0 émettait un jeton unique par RÔLE, partagé par tous
#          les porteurs de ce rôle — impossible de révoquer un seul technicien
#          sans invalider tout le monde, et aucune expiration. Correctif :
#          format "identity:role:expiry:signature" ; --role-issue-token prend
#          désormais <ROLE> <IDENTITE> [JOURS=30] ; --role-revoke-token révoque
#          un jeton précis (identity+role+expiry) sans toucher aux autres, ni
#          faire tourner le secret ; expiration vérifiée à chaque usage ;
#          l'identité authentifiée apparaît dans --security-status et dans les
#          entrées d'audit ROLE_ELEVATION_GRANTED. Comparaison de signature
#          passée à sonar_const_time_eq (best-effort, remplace `[[ == ]]` qui
#          court-circuite au premier octet différent). Testé : jeton nominatif
#          accordé, jeton révoqué rejeté, jeton expiré (forgé avec un horodatage
#          passé et re-signé) rejeté — 3 nouveaux tests fonctionnels dans
#          --self-test.
#===============================================================================
# AVERTISSEMENT : Ce script formate le disque cible. Toutes les données seront
# effacées. Vérifiez le périphérique avant de continuer.
#===============================================================================
# Copyright 2026 Sékou SANOU
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#===============================================================================

set -euo pipefail
shopt -s extglob
umask 077

# Racine d'exécution stable : indépendante du répertoire courant de l'appelant.
# (Stable runtime root: does not depend on the caller's current directory.)
SONAR_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SONAR_ROOT="${SONAR_ROOT:-${SONAR_SCRIPT_DIR}}"

# === SONAR SECURITY & COMPATIBILITY LAYER ===
# Defensive, non-destructive helpers. Destructive operations remain behind the
# existing explicit confirmation/--yes workflow of the deployment engine.

SONAR_SECURITY_DIR="${SONAR_SECURITY_DIR:-${SONAR_ROOT}/Secure}"
SONAR_AI_DIR="${SONAR_AI_DIR:-${SONAR_ROOT}/AI}"
SONAR_POLICY_FILE="${SONAR_POLICY_FILE:-${SONAR_SECURITY_DIR}/Policies/policy.tsv}"
SONAR_AUDIT_LOG="${SONAR_AUDIT_LOG:-${SONAR_SECURITY_DIR}/Logs/audit.log}"
SONAR_HASHCHAIN_LOG="${SONAR_HASHCHAIN_LOG:-${SONAR_SECURITY_DIR}/Logs/hashchain.log}"
SONAR_MANIFEST="${SONAR_MANIFEST:-${SONAR_SECURITY_DIR}/MANIFEST.sha256}"
SONAR_FIELD_PINS_FILE="${SONAR_FIELD_PINS_FILE:-${SONAR_SECURITY_DIR}/Vault/field_pins.tsv}"
SONAR_ROLE="${SONAR_ROLE:-Technician}"

# ----------------------------------------------------------------------------
# ROLE LOCK v2: prevents `SONAR_ROLE=Admin` / `--role Admin` from silently
# granting elevated RBAC permissions. Viewer and Technician remain
# self-service (no behavior change for the common case). Any other role
# (Senior, Forensic, Admin, Expert) requires a bearer token bound to a named
# operator, with an expiry and individual revocability:
#
#   TOKEN = "<identity>:<role>:<expiry_epoch>:<signature>"
#   SIGNATURE = HMAC-SHA256(secret, identity | role | expiry_epoch)
#
# Per-identity: two technicians with the same role get different tokens, so
# one leaked/compromised token can be revoked without rotating the secret or
# affecting anyone else. Expiry is embedded in the token itself and checked
# at verification time — no server-side session needed. Revocation is a
# separate append-only list (token id = hash(identity|role|expiry), no
# secret needed to check membership), so revoking doesn't require re-issuing
# everyone else's tokens.
#
# The signature is a real HMAC-SHA256 (RFC 2104), not a bespoke keyed
# hash — computed via Python's stdlib hmac/hashlib (sonar_hmac_sha256_file),
# not `openssl dgst -hmac "$secret"`: that form puts the secret's bytes
# directly on the process command line, readable by any local process/
# user via `ps`/`/proc/<pid>/cmdline` while openssl runs (found
# 2026-09-15). python3 is already a hard preflight dependency, so this
# adds no new requirement and never exposes the secret outside this
# process. Comparison still goes through sonar_const_time_eq, a best-effort constant-time
# compare rather than a formally verified one — an accepted trade-off for a
# local, single-host Bash tool defending against casual privilege
# self-escalation, not a network attacker with a timing oracle.
# ----------------------------------------------------------------------------
SONAR_ROLE_SECRET_FILE="${SONAR_ROLE_SECRET_FILE:-${SONAR_SECURITY_DIR}/Keys/role_secret.key}"
SONAR_ROLE_REVOKED_FILE="${SONAR_ROLE_REVOKED_FILE:-${SONAR_SECURITY_DIR}/Keys/revoked_tokens.tsv}"
SONAR_SELF_SERVICE_ROLES="Viewer Technician"
SONAR_ROLE_TOKEN="${SONAR_ROLE_TOKEN:-}"
SONAR_ROLE_TOKEN_FILE="${SONAR_ROLE_TOKEN_FILE:-}"
SONAR_ROLE_IDENTITY="${SONAR_ROLE_IDENTITY:-}"
SONAR_ROLE_DENY_REASON=""
# Affectation SIMPLE (jamais "${VAR:-}") : cette variable memorise « le verrou a deja ete verifie pour ce
# (role, jeton, fichier) ». Si elle etait heritee de l'environnement, exporter SONAR_ROLE_LOCK_ENFORCED_SIG='Admin::'
# avec SONAR_ROLE=Admin faisait retourner sonar_role_enforce_lock avant toute verification : role Admin sans
# AUCUN jeton (verifie 2026-09-21, audit adversarial — voir CHANGELOG 3.49.2).
SONAR_ROLE_LOCK_ENFORCED_SIG=""

sonar_role_secret_exists() { [[ -s "${SONAR_ROLE_SECRET_FILE}" ]]; }

sonar_role_is_self_service() {
    local role="$1" r
    for r in ${SONAR_SELF_SERVICE_ROLES}; do
        [[ "$role" == "$r" ]] && return 0
    done
    return 1
}

# sonar_const_time_eq: best-effort constant-time string comparison — avoids
# bash's native `==` short-circuiting on the first mismatched byte, which is
# the textbook timing side-channel for secret comparison. Not a formal
# guarantee (bash arithmetic isn't timing-verified), but strictly better
# than the naive comparison it replaces.
sonar_const_time_eq() {
    local a="$1" b="$2" i diff=0 la lb ca cb
    la=${#a}; lb=${#b}
    diff=$(( la ^ lb ))
    local n=$la; (( lb > n )) && n=$lb
    for (( i=0; i<n; i++ )); do
        ca=0; cb=0
        (( i < la )) && ca=$(printf '%d' "'${a:i:1}")
        (( i < lb )) && cb=$(printf '%d' "'${b:i:1}")
        diff=$(( diff | (ca ^ cb) ))
    done
    [[ $diff -eq 0 ]]
}

# sonar_role_bootstrap_secret: one-time creation of the local role secret.
# Refuses to overwrite an existing secret (prevents a later attacker with
# write access from silently rotating the trust root out from under an
# admin). Must be run explicitly by the trusted operator right after
# installation, before the tool is handed to technicians.
sonar_role_bootstrap_secret() {
    mkdir -p "$(dirname "${SONAR_ROLE_SECRET_FILE}")"
    chmod 700 "$(dirname "${SONAR_ROLE_SECRET_FILE}")" 2>/dev/null || true
    if sonar_role_secret_exists; then
        echo "[SONAR] Un secret de rôle existe déjà: ${SONAR_ROLE_SECRET_FILE}" >&2
        echo "[SONAR] Refus d'écraser — supprimez-le manuellement pour une rotation volontaire." >&2
        return 1
    fi
    local secret
    secret="$(sonar_generate_secret_hex)" || { echo "[SONAR] Aucun moteur SHA-256 disponible pour générer le secret." >&2; return 1; }
    [[ -n "$secret" ]] || { echo "[SONAR] Échec de génération du secret." >&2; return 1; }
    printf '%s' "$secret" > "${SONAR_ROLE_SECRET_FILE}"
    chmod 600 "${SONAR_ROLE_SECRET_FILE}"
    : > "${SONAR_ROLE_REVOKED_FILE}"
    chmod 600 "${SONAR_ROLE_REVOKED_FILE}"
    sonar_audit "ROLE_SECRET_BOOTSTRAPPED" "file=${SONAR_ROLE_SECRET_FILE}"
    echo "[SONAR] Secret de verrouillage de rôle initialisé: ${SONAR_ROLE_SECRET_FILE} (chmod 600)."
    echo "[SONAR] Émettez des jetons avec: --role-issue-token <ROLE> <IDENTITE> [JOURS_VALIDITE=30]."
}

# sonar_role_sign IDENTITY ROLE EXPIRY -> HMAC-SHA256(secret, "identity|role|expiry")
sonar_role_sign() {
    local identity="$1" role="$2" expiry="$3"
    sonar_role_secret_exists || return 1
    sonar_hmac_sha256_file "${SONAR_ROLE_SECRET_FILE}" "${identity}|${role}|${expiry}"
}

# sonar_role_token_id IDENTITY ROLE EXPIRY -> revocation key (no secret needed:
# anyone holding a token can compute its own id, and so can the admin from the
# identity/role/expiry alone, without needing the token's signature).
sonar_role_token_id() {
    sonar_hash_str "$1|$2|$3"
}

sonar_role_is_revoked() {
    local token_id="$1"
    [[ -s "${SONAR_ROLE_REVOKED_FILE}" ]] || return 1
    grep -qF "${token_id}" "${SONAR_ROLE_REVOKED_FILE}"
}

# sonar_role_issue_token ROLE IDENTITY [DAYS=30]: prints "identity:role:expiry:sig"
# to stdout only — the signature is never written to the audit log (only the
# fact that a token was issued, to whom, for what role, until when), so the
# plaintext audit trail can't be used to reconstruct access.
sonar_role_issue_token() {
    local role="$1" identity="$2" days="${3:-30}" v known="Viewer Technician Senior Forensic Admin Expert" ok=0
    for v in $known; do [[ "$role" == "$v" ]] && ok=1; done
    [[ -n "$role" && $ok -eq 1 ]] || { echo "[SONAR] Usage: --role-issue-token <ROLE> <IDENTITE> [JOURS=30] (${known})" >&2; return 2; }
    if sonar_role_is_self_service "$role"; then
        echo "[SONAR] '${role}' est en libre-service — aucun jeton requis." >&2
        return 1
    fi
    if [[ -z "$identity" || "$identity" =~ [^A-Za-z0-9._@-] ]]; then
        echo "[SONAR] Identité requise (lettres/chiffres/./_/@/- uniquement, ex: j.dupont)." >&2
        return 2
    fi
    if ! [[ "$days" =~ ^[0-9]+$ ]] || (( days <= 0 )); then
        echo "[SONAR] JOURS doit être un entier positif." >&2
        return 2
    fi
    sonar_role_secret_exists || { echo "[SONAR] Aucun secret initialisé. Exécutez --role-bootstrap d'abord." >&2; return 1; }
    local expiry sig
    expiry=$(( $(date -u +%s) + days * 86400 ))
    sig="$(sonar_role_sign "$identity" "$role" "$expiry")" || { echo "[SONAR] Échec du calcul du jeton." >&2; return 1; }
    echo "${identity}:${role}:${expiry}:${sig}"
    sonar_audit "ROLE_TOKEN_ISSUED" "identity=${identity};role=${role};expires=$(date -u -d "@${expiry}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -r "${expiry}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "${expiry}")"
}

# sonar_role_revoke_token TOKEN_STRING: revokes a specific identity+role+expiry
# combination (recomputed from the token's own plaintext fields — no secret
# needed), independent of anyone else's tokens for the same role.
sonar_role_revoke_token() {
    # Gated on "not self-service" rather than one specific policy.tsv
    # column: none of AUDIT/DEPLOY/VAULT (the only enforced columns)
    # actually exclude Technician — all three show at least R/RW for it
    # — so reusing any of them here wouldn't have blocked anything.
    # Found 2026-09-15: without this, ANY unauthenticated Technician
    # could revoke ANY other operator's Admin/Forensic/Senior/Expert
    # token — a real denial-of-service, since sonar_role_token_id()
    # only needs the token's plaintext identity/role/expiry (no
    # signature check), and those are exactly the fields
    # ROLE_TOKEN_ISSUED already writes to audit.log in the clear.
    if sonar_role_is_self_service "${SONAR_ROLE}"; then
        echo "[SONAR] Rôle '${SONAR_ROLE}' insuffisant pour révoquer un jeton (rôle élevé requis)." >&2
        sonar_audit "ACCESS_DENIED" "action=ROLE_REVOKE_TOKEN"
        return 1
    fi
    local provided="$1" identity role expiry sig token_id
    IFS=':' read -r identity role expiry sig <<< "${provided}"
    [[ -n "$identity" && -n "$role" && -n "$expiry" ]] || { echo "[SONAR] Jeton illisible (format attendu: identite:role:expiry:signature)." >&2; return 2; }
    mkdir -p "$(dirname "${SONAR_ROLE_REVOKED_FILE}")"
    token_id="$(sonar_role_token_id "$identity" "$role" "$expiry")"
    if sonar_role_is_revoked "$token_id"; then
        echo "[SONAR] Jeton déjà révoqué (identity=${identity}, role=${role})."
        return 0
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$(sonar_iso_now)" "$identity" "$role" "$expiry" "$token_id" >> "${SONAR_ROLE_REVOKED_FILE}"
    chmod 600 "${SONAR_ROLE_REVOKED_FILE}" 2>/dev/null || true
    sonar_audit "ROLE_TOKEN_REVOKED" "identity=${identity};role=${role}"
    echo "[SONAR] Jeton révoqué: identity=${identity}, role=${role}."
}

# sonar_role_verify_token_string PROVIDED REQUESTED_ROLE: parses, checks role
# match, expiry, revocation, then signature. Sets SONAR_ROLE_IDENTITY and
# SONAR_ROLE_DENY_REASON as a side effect for the caller to log/report.
sonar_role_verify_token_string() {
    local provided="$1" requested_role="$2" identity role expiry sig now expected token_id
    SONAR_ROLE_DENY_REASON="jeton absent"
    [[ -n "$provided" ]] || return 1
    IFS=':' read -r identity role expiry sig <<< "${provided}"
    if [[ -z "$identity" || -z "$role" || -z "$expiry" || -z "$sig" ]]; then
        SONAR_ROLE_DENY_REASON="jeton malformé"
        return 1
    fi
    if [[ "$role" != "$requested_role" ]]; then
        SONAR_ROLE_DENY_REASON="jeton émis pour le rôle '${role}', pas '${requested_role}'"
        return 1
    fi
    if ! [[ "$expiry" =~ ^[0-9]+$ ]]; then
        SONAR_ROLE_DENY_REASON="jeton malformé (expiration)"
        return 1
    fi
    now="$(date -u +%s)"
    if (( expiry < now )); then
        SONAR_ROLE_DENY_REASON="jeton expiré le $(date -u -d "@${expiry}" '+%Y-%m-%d' 2>/dev/null || date -u -r "${expiry}" '+%Y-%m-%d' 2>/dev/null || echo "${expiry}")"
        return 1
    fi
    token_id="$(sonar_role_token_id "$identity" "$role" "$expiry")"
    if sonar_role_is_revoked "$token_id"; then
        SONAR_ROLE_DENY_REASON="jeton révoqué"
        return 1
    fi
    expected="$(sonar_role_sign "$identity" "$role" "$expiry")" || { SONAR_ROLE_DENY_REASON="secret indisponible"; return 1; }
    if ! sonar_const_time_eq "$sig" "$expected"; then
        SONAR_ROLE_DENY_REASON="signature invalide"
        return 1
    fi
    SONAR_ROLE_IDENTITY="$identity"
    return 0
}

# sonar_role_enforce_lock: the actual gate. Called once at startup (both CLI
# entry points). If the requested role is elevated and no valid token is
# presented, the role is downgraded to Technician — fail-safe rather than a
# hard exit, so read-only commands keep working; any elevated-only action
# then still gets denied a second time by the existing sonar_require_role
# checks, with its own ACCESS_DENIED audit entry. Both attempts are logged.
sonar_role_enforce_lock() {
    # Keyed on (role, token, token file) rather than a plain "already ran"
    # flag: this function is called once early (before any CLI flag is
    # parsed) and again after parse_final_args parses --role/--role-token.
    # A plain boolean would make the second call a permanent no-op the
    # instant the first call ran with the pre-parse defaults, silently
    # skipping verification of whatever role/token the CLI just requested.
    local sig="${SONAR_ROLE}:${SONAR_ROLE_TOKEN}:${SONAR_ROLE_TOKEN_FILE}"
    [[ "${SONAR_ROLE_LOCK_ENFORCED_SIG:-}" == "$sig" ]] && return 0
    SONAR_ROLE_LOCK_ENFORCED_SIG="$sig"
    sonar_role_is_self_service "${SONAR_ROLE}" && return 0
    local provided
    provided="$(tr -d ' \t\r\n' <<< "${SONAR_ROLE_TOKEN}")"
    if [[ -z "$provided" && -n "${SONAR_ROLE_TOKEN_FILE}" && -f "${SONAR_ROLE_TOKEN_FILE}" ]]; then
        provided="$(tr -d ' \t\r\n' < "${SONAR_ROLE_TOKEN_FILE}")"
    fi
    if sonar_role_verify_token_string "${provided}" "${SONAR_ROLE}"; then
        sonar_audit "ROLE_ELEVATION_GRANTED" "role=${SONAR_ROLE}"
        return 0
    fi
    echo "[SECURITY] Rôle '${SONAR_ROLE}' refusé (${SONAR_ROLE_DENY_REASON})." >&2
    echo "[SECURITY] Rétrogradation automatique vers 'Technician'." >&2
    sonar_audit "ROLE_ELEVATION_BLOCKED" "requested=${SONAR_ROLE};reason=${SONAR_ROLE_DENY_REASON};downgraded_to=Technician"
    SONAR_ROLE="Technician"
    SONAR_ROLE_IDENTITY=""
    return 1
}

sonar_security_init() {
    mkdir -p \
        "${SONAR_SECURITY_DIR}/Keys" \
        "${SONAR_SECURITY_DIR}/Policies" \
        "${SONAR_SECURITY_DIR}/Logs" \
        "${SONAR_SECURITY_DIR}/Reports" \
        "${SONAR_SECURITY_DIR}/Vault" \
        "${SONAR_AI_DIR}/Hardware"

    # NOTE (2026-09-14, revisited): AUDIT, DEPLOY and VAULT are the only
    # columns actively enforced via sonar_require_role (build/verify
    # manifest, disk deploy, catalog seal/verify-seal). DESTRUCTIVE and
    # FORENSIC are deliberately left unenforced — not an oversight still
    # to wire up, but a decision, because enforcing either one *as
    # currently specified* would conflict with tested/intended behavior:
    #
    #   - FORENSIC: gating sonar_forensic_acquire/backup_execute/
    #     forensic_chain_of_custody on it was tried in v3.10.3 and
    #     reverted — it broke --self-test's "acquisition works without an
    #     authenticated identity" case, which CHANGELOG.md v3.10.2 documents
    #     as intentional: evidence collection is meant to stay open to any
    #     local operator (Technician, no token); an elevated role+token only
    #     adds an *attributed* identity to the audit trail, it doesn't gate
    #     the ability to collect.
    #   - DESTRUCTIVE: Technician is "-" here, but Technician is "R" under
    #     DEPLOY, and the real `--disk` write path (main_final, checked via
    #     sonar_require_role DEPLOY only) IS the destructive operation —
    #     disk erase/partition/format. Enforcing DESTRUCTIVE literally would
    #     block the exact self-service deploy DEPLOY=R already allows, for
    #     every role except Senior/Admin/Expert. That's a real product
    #     decision (should Technician deploys require CONFIRM too? should
    #     DESTRUCTIVE and DEPLOY be merged into one column?), not something
    #     to resolve by adding a check — no self-test coverage exists for
    #     the real disk-write path (P0 hardware-validation blocker in
    #     ROADMAP.md) to verify a change here doesn't break it.
    #
    # Both are left declarative on purpose until the external RBAC/forensic
    # audit (ROADMAP.md P1) resolves them with someone who can validate
    # against real hardware and the project's actual policy intent — see
    # ROADMAP.md for the specific open questions above, spelled out there.
    #
    # CORRIGE 2026-09-17 : VAULT etait "R"/"RW" pour Viewer/Technician (les
    # deux roles libre-service, sans jeton) — sonar_role_can traite R/RW/
    # CONFIRM comme equivalents (aucune des trois n'est rejetee), donc
    # --fetch-manifest-seal / --field-pin-set / --catalog-seal ne
    # demandaient AUCUNE elevation reelle malgre le "[role VAULT]" affiche
    # dans --help. Trouve par un audit externe (voir CHANGELOG.md), verifie
    # par grep direct sur ce fichier. Viewer/Technician passes a "-" :
    # sceller un manifeste ou definir un PIN de terrain exige maintenant un
    # vrai jeton Senior/Forensic/Admin/Expert, comme le texte d'aide l'a
    # toujours affirme. La VERIFICATION d'un scelle (sonar_fetch_manifest_
    # verify_seal, sonar_catalog_verify_seal) reste volontairement ouverte a
    # tous — verifier ne cree pas de confiance, ca en controle une deja
    # etablie.
    if [[ ! -f "${SONAR_POLICY_FILE}" ]]; then
        cat > "${SONAR_POLICY_FILE}" <<'EOF'
ROLE	AUDIT	DIAGNOSE	DEPLOY	DESTRUCTIVE	FORENSIC	VAULT
Viewer	R	R	-	-	-	-
Technician	R	R	R	-	-	-
Senior	R	R	R	CONFIRM	R	RW
Forensic	R	R	-	-	RW	RW
Admin	RW	RW	R	CONFIRM	RW	RW
Expert	RW	RW	R	CONFIRM	RW	RW
EOF
    fi
    sonar_policy_check_stale

    touch "${SONAR_AUDIT_LOG}" "${SONAR_HASHCHAIN_LOG}"
}

# SHA-256 exacte du defaut policy.tsv d'avant le durcissement VAULT du
# 2026-09-17 (Viewer VAULT=R, Technician VAULT=RW — voir commit f457156).
# UNE seule valeur connue, figee, jamais recalculee dynamiquement : c'est
# la signature d'un etat historique precis, pas du defaut courant.
SONAR_POLICY_STALE_HASH_20260917="cae4d872be81284cf9c8641863bc0406754b3970e805fb0f1684fdd7a98f3d98"

# sonar_policy_check_stale: appelee a chaque sonar_security_init, donc a
# chaque invocation du script — sonar_security_init ne regenere JAMAIS un
# policy.tsv deja present, meme apres une mise a jour du script qui change
# le defaut. Trouve le 2026-09-18 : un policy.tsv local (gitignore, jamais
# commite) etait reste perime avec l'ancien defaut permissif malgre le fix
# VAULT deja livre dans le script, SANS AUCUN avertissement — la
# protection RBAC du 2026-09-17 n'etait donc pas reellement active sur
# cette machine tant que ce fichier n'a pas ete supprime manuellement.
#
# Ne compare PAS au defaut courant : un policy.tsv deliberement
# personnalise par l'operateur est une vraie decision produit, jamais a
# ecraser silencieusement. Seule la signature EXACTE de l'ancien defaut
# connu ci-dessus declenche une migration automatique (avec sauvegarde
# horodatee). Tout le reste (personnalise ou deja a jour) est laisse
# intact ; seul un ecart specifique et dangereux (VAULT ouvert a un role
# libre-service Viewer/Technician) declenche un avertissement, sans
# jamais modifier le fichier.
sonar_policy_check_stale() {
    [[ -s "${SONAR_POLICY_FILE}" ]] || return 0
    local h bak
    h="$(sonar_hash "${SONAR_POLICY_FILE}" 2>/dev/null)" || return 0
    if [[ "$h" == "${SONAR_POLICY_STALE_HASH_20260917}" ]]; then
        bak="${SONAR_POLICY_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
        cp -f "${SONAR_POLICY_FILE}" "${bak}"
        cat > "${SONAR_POLICY_FILE}" <<'EOF'
ROLE	AUDIT	DIAGNOSE	DEPLOY	DESTRUCTIVE	FORENSIC	VAULT
Viewer	R	R	-	-	-	-
Technician	R	R	R	-	-	-
Senior	R	R	R	CONFIRM	R	RW
Forensic	R	R	-	-	RW	RW
Admin	RW	RW	R	CONFIRM	RW	RW
Expert	RW	RW	R	CONFIRM	RW	RW
EOF
        sonar_audit "POLICY_MIGRATED" "from=pre-2026-09-17-default;backup=${bak}"
        echo "[SONAR][SECURITE] ${SONAR_POLICY_FILE} etait perime (defaut d'avant le durcissement VAULT du 2026-09-17, Viewer/Technician avaient encore acces VAULT). Migre automatiquement vers le defaut actuel. Ancienne version sauvegardee: ${bak}" >&2
        return 0
    fi
    local vv vt
    vv="$(awk -F'\t' '$1=="Viewer"{print $NF}' "${SONAR_POLICY_FILE}" 2>/dev/null)"
    vt="$(awk -F'\t' '$1=="Technician"{print $NF}' "${SONAR_POLICY_FILE}" 2>/dev/null)"
    if [[ -n "$vv" && "$vv" != "-" ]] || [[ -n "$vt" && "$vt" != "-" ]]; then
        sonar_audit "POLICY_PERMISSIVE_VAULT_DETECTED" "viewer_vault=${vv:-?};technician_vault=${vt:-?}"
        echo "[SONAR][ATTENTION] ${SONAR_POLICY_FILE}: acces VAULT non restreint ('-') pour un role libre-service (Viewer=${vv:-?}, Technician=${vt:-?}). Si ce n'est pas une personnalisation voulue, comparez avec le defaut actuel de sonar_security_init et corrigez manuellement." >&2
    fi
}

sonar_hash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        return 1
    fi
}

sonar_hash_str() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    else
        return 1
    fi
}

# sonar_hmac_sha256_file SECRET_FILE MESSAGE -> hex HMAC-SHA256.
# Deliberately NOT `openssl dgst -sha256 -hmac "$secret"`: that form puts
# the secret's actual bytes on the process command line, readable by any
# local process/user via `ps`/`/proc/<pid>/cmdline` for the (short but
# real) duration openssl runs — found 2026-09-15 while auditing the
# role-lock/build-watermark signing paths. Here only the secret's PATH
# crosses argv; Python reads the key bytes itself via `open(...)`, never
# exposing them outside this process. python3 is already a hard
# preflight dependency, so this adds no new requirement.
sonar_hmac_sha256_file() {
    local secret_file="$1" message="$2"
    python3 - "$secret_file" "$message" <<'PY'
import hashlib, hmac, sys
secret_file, message = sys.argv[1], sys.argv[2]
with open(secret_file, "rb") as f:
    key = f.read()
print(hmac.new(key, message.encode("utf-8"), hashlib.sha256).hexdigest())
PY
}

# sonar_generate_secret_hex: 32 bytes of /dev/urandom, hex-encoded via
# whichever SHA-256 engine is available. Shared by the two independent
# trust roots this script maintains (role-lock secret, build-watermark
# secret) so the derivation only needs to be right — or changed — in one
# place instead of two copies drifting apart.
sonar_iso_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

sonar_generate_secret_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        head -c 32 /dev/urandom | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        head -c 32 /dev/urandom | shasum -a 256 | awk '{print $1}'
    else
        return 1
    fi
}

# sonar_sanitize_value: neutralize a single operator-supplied token (case id,
# disk label, operator identity, ...) before it is embedded either in a
# `key=value;key=value` audit details string or in a line-based report/manifest
# file. Stricter than sonar_audit's own tab/newline stripping below (which only
# protects the log's column structure): a lone value sitting next to `;`/`=`
# delimiters must not be able to forge extra fields with them either.
sonar_sanitize_value() {
    local s="$1"
    s="${s//$'\t'/ }"; s="${s//$'\r'/ }"; s="${s//$'\n'/ }"
    s="${s//;/,}"; s="${s//=/-}"
    printf '%s' "$s"
}

sonar_audit() {
    local event="${1:-event}"
    local details="${2:-}"
    local ts prev hash
    ts="$(sonar_iso_now)"
    # audit.log and hashchain.log are tab-separated, newline-terminated.
    # Several callers pass caller/user-supplied free text into `details`
    # (forensic case ids, disk labels, etc.) — without this, an embedded
    # literal tab or newline corrupts the log's column structure, or (with
    # a newline) can make a single logical entry LOOK like a separate,
    # plausible-but-fake log line to anyone reading the raw file. The
    # hashchain still catches this as tampering on --verify-hashchain
    # (the hash covers the untouched string), but a naive `cat`/`awk` read
    # would be misled in the meantime. Sanitize centrally here so every
    # current and future caller is covered, not just the ones that remember.
    event="${event//$'\t'/ }"; event="${event//$'\n'/ }"
    details="${details//$'\t'/ }"; details="${details//$'\n'/ }"
    if [[ -n "${SONAR_ROLE_IDENTITY:-}" ]]; then
        # Roles libre-service (Viewer/Technician) ne passent jamais par la
        # verification de jeton (sonar_role_enforce_lock retourne avant) :
        # SONAR_ROLE_IDENTITY peut donc etre une simple variable d'env
        # positionnee par l'operateur lui-meme, sans preuve. Marquer ce cas
        # explicitement au lieu de le journaliser comme une identite
        # verifiee au meme titre qu'un jeton signe (roles elevated,
        # SONAR_ROLE_IDENTITY assigne en ligne 355 apres verification HMAC).
        # Trouve 2026-09-17 — voir CHANGELOG.md.
        # L'identite est assainie ICI, apres l'assainissement de event/details plus haut : elle est ajoutee
        # apres eux, et pour un role libre-service c'est une variable d'env NON verifiee — un saut de ligne ou une
        # tabulation dedans forgeait de fausses lignes dans audit.log/hashchain.log (verifie 2026-09-21).
        local _sid; _sid="$(sonar_sanitize_value "${SONAR_ROLE_IDENTITY}")"
        if sonar_role_is_self_service "${SONAR_ROLE}"; then
            details="${details:+${details};}identity=${_sid} (auto-declaree, non authentifiee)"
        else
            details="${details:+${details};}identity=${_sid}"
        fi
    fi
    # Serialize the read-prev/append sequence below with flock when available:
    # without it, two concurrent SONAR invocations can both read the same
    # "prev" hash and each append a link to it, producing a chain
    # --verify-hashchain reports as broken/tampered even though nothing was
    # actually falsified — just two legitimate writers racing. Best-effort
    # (skipped if flock isn't installed) — no worse than the prior behavior.
    {
        command -v flock >/dev/null 2>&1 && { flock -x 201 || true; }
        printf '%s\t%s\t%s\t%s\n' "$ts" "${SONAR_ROLE}" "$event" "$details" >> "${SONAR_AUDIT_LOG}"

        prev="$(tail -n 1 "${SONAR_HASHCHAIN_LOG}" 2>/dev/null | awk -F '\t' '{print $NF}')" || true
        prev="${prev:-GENESIS}"
        hash="$(sonar_hash_str "${prev}|${ts}|${SONAR_ROLE}|${event}|${details}")" || hash="UNAVAILABLE"
        printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "${SONAR_ROLE}" "$event" "$details" "$hash" >> "${SONAR_HASHCHAIN_LOG}"
    } 201>>"${SONAR_HASHCHAIN_LOG}.lock"
}

# sonar_verify_hashchain: recompute each hashchain entry from GENESIS forward and
# compare against the stored hash. Detects any insertion, deletion, reordering or
# edition of a past audit entry. Without this, the hashchain was write-only —
# tamper-evidence requires a reader that actually recomputes the chain.
sonar_verify_hashchain() {
    [[ -s "${SONAR_HASHCHAIN_LOG}" ]] || { echo "[SONAR] Hashchain vide ou absent: ${SONAR_HASHCHAIN_LOG}" >&2; return 1; }
    local prev="GENESIS" ts role event details stored_hash computed_hash lineno=0 broken=0 total=0
    # Meme verrou que sonar_audit (flock -x 201 sur le meme fichier .lock),
    # scope UNIQUEMENT a la lecture ci-dessous — pas a tout sonar_verify_
    # hashchain, dont le sonar_audit final (hors de ce bloc) prend lui-meme
    # ce verrou : l'englober aurait cause un auto-blocage (le meme processus
    # attendant un verrou qu'il detient deja). Sans ce verrou, une
    # verification concurrente a une ecriture pouvait lire un "prev" hash
    # incoherent et signaler une rupture qui n'existe pas — un faux positif
    # couteux en credibilite pour un outil dont l'argument central est "je
    # detecte la falsification". Trouve par un audit externe, verifie avant
    # correction.
    {
        command -v flock >/dev/null 2>&1 && { flock -x 201 || true; }
        while IFS=$'\t' read -r ts role event details stored_hash; do
            lineno=$((lineno+1))
            [[ -z "${ts:-}" ]] && continue
            total=$((total+1))
            computed_hash="$(sonar_hash_str "${prev}|${ts}|${role}|${event}|${details}")" || computed_hash="UNAVAILABLE"
            if [[ "${computed_hash}" != "${stored_hash}" ]]; then
                echo "[SONAR][TAMPER] Rupture de chaine a la ligne ${lineno} (event=${event}, ts=${ts})" >&2
                broken=$((broken+1))
            fi
            prev="${stored_hash}"
        done < "${SONAR_HASHCHAIN_LOG}"
    } 201>>"${SONAR_HASHCHAIN_LOG}.lock"
    if (( broken == 0 )); then
        echo "[SONAR] Hashchain integre: ${total} entree(s) verifiee(s), aucune rupture."
        sonar_audit "HASHCHAIN_VERIFIED" "entries=${total};status=INTACT"
        return 0
    else
        echo "[SONAR] Hashchain COMPROMISE: ${broken}/${total} rupture(s) detectee(s)." >&2
        sonar_audit "HASHCHAIN_VERIFIED" "entries=${total};status=BROKEN;breaks=${broken}"
        return 1
    fi
}

sonar_role_can() {
    local action="${1:-AUDIT}"
    [[ -f "${SONAR_POLICY_FILE}" ]] || return 1
    awk -F '\t' -v role="$SONAR_ROLE" -v action="$action" '
        NR==1 {
            for (i=1;i<=NF;i++) col[$i]=i
            next
        }
        $1==role {
            v=$(col[action])
            if (v=="R" || v=="RW" || v=="CONFIRM") found=1
        }
        END { exit(found ? 0 : 1) }
    ' "${SONAR_POLICY_FILE}"
}

sonar_require_role() {
    local action="$1"
    if ! sonar_role_can "$action"; then
        echo "[SECURITY] Access denied: role=${SONAR_ROLE}, action=${action}" >&2
        sonar_audit "ACCESS_DENIED" "action=${action}"
        return 1
    fi
    sonar_audit "ACCESS_GRANTED" "action=${action}"
    return 0
}

sonar_detect_arch() {
    local a
    a="$(uname -m 2>/dev/null || echo unknown)"
    case "$a" in
        x86_64|amd64) echo "x64" ;;
        aarch64|arm64) echo "ARM64" ;;
        armv7l|armv8l) echo "ARM32" ;;
        i386|i686) echo "x86" ;;
        *) echo "$a" ;;
    esac
}

sonar_detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID:-linux}"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "$(uname -s | tr '[:upper:]' '[:lower:]')"
    fi
}

sonar_collect_hardware() {
    local f="${SONAR_AI_DIR}/Hardware/inventory.tsv"
    {
        echo -e "FIELD\tVALUE"
        echo -e "OS\t$(sonar_detect_os)"
        echo -e "ARCH\t$(sonar_detect_arch)"
        echo -e "KERNEL\t$(uname -sr 2>/dev/null || true)"
        if command -v lscpu >/dev/null 2>&1; then
            echo -e "CPU\t$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')"
        fi
        if [[ -r /proc/meminfo ]]; then
            echo -e "RAM_MB\t$(awk '/MemTotal:/ {printf "%d",$2/1024}' /proc/meminfo)"
        fi
        if command -v lsblk >/dev/null 2>&1; then
            echo -e "BLOCK_DEVICES\t$(lsblk -dn -o NAME,SIZE,TYPE 2>/dev/null | tr '\n' ';')"
        fi
        if command -v mokutil >/dev/null 2>&1; then
            echo -e "SECURE_BOOT\t$(mokutil --sb-state 2>/dev/null | tr '\n' ' ')"
        fi
    } > "$f"
    sonar_audit "HARDWARE_INVENTORY" "file=${f}"
}

sonar_build_manifest() {
    local root="${1:-}"
    [[ -d "$root" ]] || return 1
    sonar_require_role AUDIT || return 1
    : > "${SONAR_MANIFEST}"
    if command -v sha256sum >/dev/null 2>&1; then
        find "$root" -type f \
            ! -path '*/Secure/Keys/*' \
            ! -path '*/Secure/Logs/*' \
            ! -path "${SONAR_MANIFEST}" \
            ! -path '*/AI/Logs/*' \
            -print0 | sort -z | xargs -0 -r sha256sum > "${SONAR_MANIFEST}" 2>/dev/null || true
    elif command -v shasum >/dev/null 2>&1; then
        find "$root" -type f \
            ! -path '*/Secure/Keys/*' \
            ! -path '*/Secure/Logs/*' \
            ! -path "${SONAR_MANIFEST}" \
            ! -path '*/AI/Logs/*' \
            -print0 | sort -z | while IFS= read -r -d '' f; do
                shasum -a 256 "$f"
            done > "${SONAR_MANIFEST}"
    else
        echo "[SECURITY] sha256sum/shasum indisponibles; manifeste non généré." >&2
        return 1
    fi
    sonar_audit "MANIFEST_BUILT" "file=${SONAR_MANIFEST}"
}

sonar_verify_manifest() {
    [[ -s "${SONAR_MANIFEST}" ]] || return 1
    sonar_require_role AUDIT || return 1
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "${SONAR_MANIFEST}"
    else
        echo "[SECURITY] sha256sum unavailable; manifest verification cannot run." >&2
        return 1
    fi
    sonar_audit "MANIFEST_VERIFIED" "file=${SONAR_MANIFEST}"
}

sonar_security_status() {
    echo "SONAR SECURITY"
    echo "  role: ${SONAR_ROLE}"
    echo "  identity: ${SONAR_ROLE_IDENTITY:-<libre-service>}"
    echo "  OS: $(sonar_detect_os)"
    echo "  ARCH: $(sonar_detect_arch)"
    echo "  audit: ${SONAR_AUDIT_LOG}"
    echo "  hashchain: ${SONAR_HASHCHAIN_LOG}"
    echo "  manifest: ${SONAR_MANIFEST}"
}

sonar_validate_role() {
    local role="$1"
    local valid_roles="Viewer Technician Senior Forensic Admin Expert"
    local v
    for v in $valid_roles; do
        [[ "$role" == "$v" ]] && return 0
    done
    error_exit "Rôle invalide: ${role}. Rôles valides: Viewer, Technician, Senior, Forensic, Admin, Expert."
}

# ============================================================================
# CONFIGURATION DU MOTEUR UNIQUE
# ============================================================================
DISK="${DISK:-}"
DISK_LABEL="${DISK_LABEL:-IT-TOOLKIT}"
VENTOY_VERSION="${VENTOY_VERSION:-1.1.17}"
VENTOY_SHA256="${VENTOY_SHA256:-7fb4ed08cef6a6b4d39dd19260d8c80291a78dfdf9af7d461571e23cbbc43805}"
PERSISTENCE_SIZE="${PERSISTENCE_SIZE:-8}"
PERSISTENCE_COUNT="${PERSISTENCE_COUNT:-5}"
BATCH_COUNT="${BATCH_COUNT:-1}"
# HONESTY NOTE (fixed from a dead flag): INCLUDE_VERACRYPT existed since the
# original header ("VeraCrypt: Oui") but nothing ever consulted it — no
# encryption of any kind was ever performed. It CANNOT mean "encrypt the
# Ventoy persistence images": Ventoy's persistence mechanism expects a raw
# ext4 image it mounts directly at boot (see ventoy.net/en/plugin_persistence.html)
# with no native VeraCrypt integration — encrypting that file would silently
# break boot-time persistence while giving a false sense of security. What
# it now does: deploy a standalone, gpg-backed vault HELPER SCRIPT onto the
# USB (Scripts/sonar-vault.sh) for the technician to create/open an
# encrypted container manually, in the field, for sensitive data — fully
# decoupled from Ventoy's boot chain, so it can never break boot.
INCLUDE_VERACRYPT="${INCLUDE_VERACRYPT:-true}"
INCLUDE_LOGGING="${INCLUDE_LOGGING:-true}"
GENERATE_README="${GENERATE_README:-true}"
# Ventoy boot-menu background/branding: purely cosmetic (GRUB-level PNG
# background via Ventoy's own theme plugin), never required for boot to
# work. Source image is supplied locally by the operator in
# SOURCE_DIR/Branding/ (never embedded as a binary blob in this script or
# its git history — same reasoning as Ventoy's own archive being
# downloaded/locally-supplied rather than embedded). Silently skipped if
# absent; never blocks a deploy.
INCLUDE_VENTOY_THEME="${INCLUDE_VENTOY_THEME:-false}"
SONAR_VENTOY_TITLE="${SONAR_VENTOY_TITLE:-SONAR - SE}"
SONAR_VENTOY_CREDIT="${SONAR_VENTOY_CREDIT:-Sekou SANOU - Burkina Faso}"
# Protection anti-reproduction anarchique (2026-09-18) : un clone dd brut de
# la cle reste toujours possible (media bootable = lisible par definition),
# donc l'objectif n'est pas de l'empecher mais de le rendre sans valeur pour
# la curation. MANIFEST.tsv (quel outil, pourquoi, SHA-256) n'est lu ni par
# Ventoy (qui scanne /ISO directement) ni par sonar_field.sh (qui ne lit que
# PROFILES.tsv) — le chiffrer ne casse donc jamais le boot/depannage. Opt-in
# (--protect-catalog), role VAULT requis, mot de passe jamais en argv (voir
# SONAR_PROTECT_PASSPHRASE, meme discipline que le reste du script).
SONAR_PROTECT_CATALOG="${SONAR_PROTECT_CATALOG:-false}"
DRY_RUN="${DRY_RUN:-false}"
YES="${YES:-false}"
# This build has never been validated on a real physical boot (Ventoy install
# + actual BIOS/UEFI boot). --dry-run and /dev/loop testing exercise the
# script's own logic, not the resulting bootable media. SONAR_HARDWARE_RISK_ACK
# (or --accept-hardware-risk) is a SEPARATE gate from --yes (disk-erase
# confirmation) — deliberately so that scripting `--yes` alone for automation
# can't silently skip acknowledging this specific, still-open risk.
SONAR_HARDWARE_RISK_ACK="${SONAR_HARDWARE_RISK_ACK:-false}"

# sonar_require_hardware_risk_ack: called once, only for a real (non
# --dry-run) --disk deployment. Blocks with a loud warning unless the
# operator already acknowledged via env var/flag, or types the exact phrase
# interactively. This is a software mitigation for a risk that can only be
# fully closed by an actual hardware/boot test matrix (tracked in
# ROADMAP.md, P0) — it does not replace that testing, it makes sure nobody
# hits the risk without having been told about it first.
sonar_require_hardware_risk_ack() {
    if [[ "${SONAR_HARDWARE_RISK_ACK}" == "true" ]]; then
        sonar_audit "HARDWARE_RISK_ACKNOWLEDGED" "method=flag_or_env"
        return 0
    fi
    echo "==============================================================" >&2
    echo "[SONAR] AVERTISSEMENT: ce build n'a JAMAIS été validé sur un"    >&2
    echo "[SONAR] démarrage physique réel (Ventoy + BIOS/UEFI). Seule la"  >&2
    echo "[SONAR] logique d'écriture a été testée (--dry-run, /dev/loop)." >&2
    echo "[SONAR] La clé produite peut échouer à démarrer sur du matériel"  >&2
    echo "[SONAR] réel. Voir ROADMAP.md (section P0)."                      >&2
    echo "==============================================================" >&2
    echo "Tapez exactement: JE COMPRENDS LE RISQUE" >&2
    read -r hw_ack
    if [[ "${hw_ack}" != "JE COMPRENDS LE RISQUE" ]]; then
        sonar_audit "HARDWARE_RISK_ACKNOWLEDGED" "method=refused"
        error_exit "Acquiescement du risque matériel refusé."
    fi
    sonar_audit "HARDWARE_RISK_ACKNOWLEDGED" "method=interactive"
}
DOWNLOAD_VENTOY="${DOWNLOAD_VENTOY:-1}"
SONAR_CA_CERT="${SONAR_CA_CERT:-}"
SONAR_GPG_KEY="${SONAR_GPG_KEY:-}"
SONAR_GPG_SIG="${SONAR_GPG_SIG:-}"
MIN_DISK_GIB="${MIN_DISK_GIB:-64}"
SOURCE_DIR="${SOURCE_DIR:-${SONAR_ROOT}/SONAR_SOURCE}"
ISO_SOURCE_DIR="${ISO_SOURCE_DIR:-${SOURCE_DIR}/ISO}"
PORTABLE_SOURCE_DIR="${PORTABLE_SOURCE_DIR:-${SOURCE_DIR}/Portable}"
SCRIPTS_SOURCE_DIR="${SCRIPTS_SOURCE_DIR:-${SOURCE_DIR}/Scripts}"
DRIVERS_SOURCE_DIR="${DRIVERS_SOURCE_DIR:-${SOURCE_DIR}/Drivers}"
MACOS_SOURCE_DIR="${MACOS_SOURCE_DIR:-${SOURCE_DIR}/macOS}"
MANIFEST_SOURCE="${MANIFEST_SOURCE:-${SOURCE_DIR}/MANIFEST.tsv}"
AI_MODE="${AI_MODE:-auto}"
AI_MODEL="${AI_MODEL:-}"
AI_ENDPOINT="${AI_ENDPOINT:-}"
# AI_PROVIDER is normally set by ai_detect_provider() (curl-probes Ollama/
# llama.cpp/openai-compatible endpoints), not given a real default here —
# but install_ai_layer_final() reads it before run_ai_final() ever calls
# ai_detect_provider() in deploy_single_disk_final's AI block, so under
# set -u this was an unconditional crash on every real --disk deploy
# (found 2026-09-14, first real hardware run). Placeholder default so the
# variable is never truly unbound regardless of call order; the real
# value is still filled in by ai_detect_provider() before it's written.
AI_PROVIDER="${AI_PROVIDER:-none}"
AI_ENABLE_DIAGNOSTICS="${AI_ENABLE_DIAGNOSTICS:-true}"
AI_ENABLE_INVENTORY="${AI_ENABLE_INVENTORY:-true}"
AI_ENABLE_RECOMMENDATIONS="${AI_ENABLE_RECOMMENDATIONS:-true}"
AI_ENABLE_ASSISTANT="${AI_ENABLE_ASSISTANT:-true}"
AI_DIR_NAME="AI"
SONAR_COMMAND="deploy"
MANIFEST_TARGET="${MANIFEST_TARGET:-${SONAR_ROOT}}"
WARN_COUNT=0
COPY_ERRORS=0
WORK_DIR=""
VENTOY_DIR=""
SONAR_MOUNTED_PARTS=""

log() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    if [[ "${INCLUDE_LOGGING}" == "true" && -n "${LOG_FILE:-}" ]]; then
        printf '[%s] %s\n' "$ts" "$1" | tee -a "${LOG_FILE}"
    else
        printf '[%s] %s\n' "$ts" "$1"
    fi
}
log_warn() { log "  [ATTENTION] $1"; WARN_COUNT=$((WARN_COUNT+1)); }
log_ok() { log "  [OK] $1"; }
log_err() { log "  [ERREUR] $1"; COPY_ERRORS=$((COPY_ERRORS+1)); }
cleanup() {
    local mp
    for mp in ${SONAR_MOUNTED_PARTS}; do
        if [[ -d "$mp" ]]; then
            umount "$mp" 2>/dev/null || true
            rmdir "$mp" 2>/dev/null || true
        fi
    done
    SONAR_MOUNTED_PARTS=""
    if [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR}" ]]; then rm -rf "${WORK_DIR}" 2>/dev/null || true; fi
    sync 2>/dev/null || true
}
error_exit() {
    log "ERREUR FATALE: $1"
    cleanup
    exit 1
}
sonar_err_trap() {
    local ec=$?
    local cmd="${BASH_COMMAND:-inconnue}"
    local where="ligne ${BASH_LINENO[0]:-?}"
    if [[ ${#FUNCNAME[@]} -gt 1 ]]; then
        where="${where}, fonction ${FUNCNAME[1]}"
    fi
    log "ERREUR FATALE (code ${ec}) à ${where}: ${cmd}"
    cleanup
    exit "${ec}"
}
trap 'error_exit "Interrompu par Ctrl-C"' INT
trap 'sonar_err_trap' ERR

prepare_workspace() {
    WORK_DIR="$(mktemp -d /tmp/sonar-deploy-XXXXXX)"
    VENTOY_DIR="${WORK_DIR}/ventoy"
    LOG_FILE="${WORK_DIR}/deploy.log"
    mkdir -p "${WORK_DIR}" "${VENTOY_DIR}"
    log "Workspace: ${WORK_DIR}"
}
usage_final() {
    cat <<'EOF'
SONAR - SE — moteur unique

Usage:
  sudo ./sonar_master.sh --disk /dev/sdX [options]

Déploiement:
  --disk DEV                 Disque USB cible (obligatoire)
  --source DIR               Racine SONAR_SOURCE (défaut: ./SONAR_SOURCE)
  --yes                      Confirmer l'effacement sans question
  --accept-hardware-risk       Acquitte le risque "jamais testé sur matériel réel"
                                sans invite (distinct de --yes ; les deux sont
                                nécessaires pour un déploiement réel non interactif)
  --dry-run                  Simulation sans modification du disque
  --batch N                  Nombre de disques (défaut: 1)
  --persistence N            Nombre de fichiers de persistance (défaut: 5)
  --persistence-size N       Taille de chaque fichier en GiB (défaut: 8)
  --no-ventoy-download       Ventoy doit être fourni localement
  --ca-certificate FILE      Bundle CA personnalisé pour les téléchargements HTTPS
  --gpg-key FILE             Clé publique GPG pour vérifier la signature Ventoy
  --gpg-sig FILE             Fichier de signature (.asc/.sig) de l'archive Ventoy

Sécurité:
  --role ROLE                Viewer|Technician|Senior|Forensic|Admin|Expert
  --security-status          Afficher l'état sécurité/compatibilité
  --hardware-inventory       Générer l'inventaire matériel
  --build-manifest [DIR]     Générer un manifeste SHA-256
  --verify-manifest          Vérifier le manifeste SHA-256

IA [EXPÉRIMENTAL — gelé depuis 2026-09-15, hors périmètre de --profile] :
  --ai MODE                  off|auto|local|online (défaut: auto)
  --ai-model MODEL           Modèle local/serveur
  --ai-endpoint URL          Endpoint compatible OpenAI
  --no-ai-diagnostics        Désactiver le diagnostic
  --no-ai-inventory          Désactiver l'inventaire
  --no-ai-recommendations    Désactiver les recommandations
  --no-ai-assistant          Désactiver l'assistant

Autres:
  --no-veracrypt              Ne pas déployer sonar-vault.sh (coffre chiffré
                                autonome, gpg AES-256 ; sans lien avec la
                                persistance Ventoy, jamais chiffrée par SONAR)
  --no-logging               Désactiver la journalisation principale
  --no-readme                Ne pas générer README
  --ventoy-theme             Active le fond d'écran Ventoy personnalisé
                                (voir SOURCE_DIR/Branding/) — DÉSACTIVÉ PAR
                                DÉFAUT depuis le 2026-09-15. Trois tailles
                                d'image radicalement différentes (6 Mo,
                                2,25 Mo, 480 Ko décodés) ont produit le
                                MÊME crash GRUB ("alloc magic is broken")
                                sur un HP EliteBook 840 G3 réel — ce n'est
                                probablement pas une question de taille
                                d'image mais d'incompatibilité du module
                                thème de Ventoy avec ce firmware. Réduire
                                l'image ne corrigera vraisemblablement rien
                                — voir CHANGELOG.md. N'activez qu'après
                                avoir testé sur le matériel cible précis.
  --no-ventoy-theme          Conservé pour compatibilité — sans effet,
                                c'est déjà le comportement par défaut.
  --protect-catalog          Chiffre MANIFEST/MANIFEST.tsv (gpg AES-256) sur
                                la clé — protège la curation (quel outil,
                                pourquoi, SHA-256) contre une reproduction
                                anarchique. N'affecte jamais le boot/dépannage
                                (ni Ventoy ni sonar_field.sh ne lisent ce
                                fichier). Rôle VAULT requis. Mot de passe
                                JAMAIS en argument — variable d'environnement
                                SONAR_PROTECT_PASSPHRASE uniquement. Se
                                déchiffre sur le terrain avec le coffre déjà
                                déployé : Scripts/sonar-vault.sh open
                                MANIFEST/MANIFEST.tsv.gpg MANIFEST/MANIFEST.tsv
  --help|-h                  Afficher cette aide

Commandes indépendantes (à la place de --disk):
  --self-audit               Auto-vérification structurelle du script
  --build-ai-queue           Générer la file IA depuis le catalogue (SONAR_CATALOGUE_EMBEDDED=/chemin pour un fichier externe personnalisé; jamais écrasé s'il existe déjà)
  --ai-audit [--queue F]     Rapport de simulation sur la file IA
  --ollama-audit [--queue F] Audit du catalogue via Ollama (lecture seule)
  --ai-download [--queue F]  Résolution + téléchargement vérifié via Ollama
  --ai-download-dry-run      Comme --ai-download, sans téléchargement réel
  --catalog-download-resolve Fait correspondre le catalogue aux paquets apt
                                disponibles (Debian/Ubuntu), sans télécharger —
                                rapport DOMAIN/CATALOG_NAME/APT_PACKAGE/STATUS
  --catalog-download-dry-run Comme --catalog-download, sans téléchargement réel
  --catalog-download          Télécharge (sans installer) chaque paquet apt
                                résolu vers SOURCE_DIR/Portable/AptPackages —
                                pas d'IA, pas d'URL codée en dur ; couverture
                                partielle par nature (rien ne peut auto-
                                télécharger un logiciel commercial/sous licence)
  --profile [NOM|list]        Profils de dépannage fermés et documentés :
                                boot-repair|data-recovery|malware|disk-clone|
                                password-reset|hardware-diagnostic|
                                peripherals-network|general-os|full —
                                scénario, outils, et POURQUOI ceux-là (pas le
                                catalogue 981, qui n'est qu'une base de
                                connaissance). peripherals-network et
                                general-os sont différents des autres par
                                nature : peripherals-network s'utilise depuis
                                un PC déjà démarré (câble branché sur un
                                téléphone Android), pas depuis le menu de
                                boot Ventoy ; general-os n'est pas un
                                scénario de dépannage mais un choix de
                                distributions Linux généralistes (bureau/
                                serveur/forensique) pour réinstallation ou
                                préférence opérateur. Sans argument (ou
                                "list") : vue d'ensemble.
  --fetch-manifest-seal       [rôle VAULT] Scelle (HMAC, secret de build) le
                                manifeste de téléchargement (URL+SHA256 par
                                outil) — à exécuter une fois avant tout
                                --fetch ("un manifeste non signé est une
                                porte ouverte").
  --fetch-manifest-verify-seal Vérifie que le manifeste n'a pas changé depuis
                                son scellement.
  --fetch <PROFIL>             Télécharge chaque outil du profil, vérifie son
                                SHA-256 contre le manifeste scellé, refuse et
                                supprime le fichier sur non-correspondance,
                                journalise source+SHA-256 (audit + MANIFEST_
                                FETCH.tsv). Refuse si le manifeste n'est pas
                                scellé.
  --field-pin-set <NIVEAU> <PIN> [PROFILS]
                                [rôle VAULT] Définit un PIN de terrain pour
                                SONAR Field (second produit,
                                Scripts/sonar_field.sh), associé à un
                                NIVEAU (libre) et à la liste de PROFILS
                                qu'il déverrouille : "ALL" (défaut) ou une
                                liste séparée par des virgules (ex.
                                "boot-repair,data-recovery"). Rejouer avec
                                le même NIVEAU met à jour sa ligne.
                                Optionnel : sans aucun PIN défini, SONAR
                                Field prévient explicitement que l'accès
                                n'est pas verrouillé.
  --field-export <MONTAGE>     Met à jour SONAR Field (MANIFEST/PROFILES*.
                                tsv, Scripts/sonar_field.sh, MANIFEST/
                                FIELD_PINS.tsv si défini) sur une clé déjà
                                déployée, sans repasser par --disk (ne
                                touche ni Ventoy ni ISO/Portable). Utile
                                pour rafraîchir une clé existante après un
                                --field-pin-set, ou après une mise à jour
                                de sonar_field.sh lui-même. Déploie aussi
                                le diagnostic intelligent (Scripts/
                                sonar_diag.sh + MANIFEST/DIAG_RULES.txt).
  --diag-analyze <FAITS> [--symptom S] [--ai]
                                Rejoue le moteur de règles du DIAGNOSTIC
                                INTELLIGENT (tools/sonar_diag.sh) sur des
                                faits collectés ailleurs (clé bootée sur
                                la machine en panne : Field-Logs/diag/*/
                                facts.tsv). --ai ajoute un commentaire
                                d'un Ollama LOCAL (consultatif, le rapport
                                déterministe fait foi). Lecture seule.

Couche opérationnelle V2:
  --launcher                  Launcher interactif SONAR
  --diagnostic                Rapport diagnostic matériel/système
  --self-test                 Self-Test opérationnel V2
  --recovery-plan             Générer le plan Recovery Windows/Linux/macOS
  --backup-plan               Générer le plan Backup/Clone sécurisé
  --forensic-workspace        Créer un espace forensic contrôlé
  --forensic-acquire SRC DST   Acquérir des preuves (copie + hachage SHA-256)
  --forensic-chain-of-custody <DOSSIER_PREUVES> [N_DOSSIER]
                                Génère la chaîne de possession pour une
                                acquisition (croise l'audit et le hashchain)
  --network-diagnostic        Rapport réseau non intrusif
  --builder [PROFILE]         [EXPÉRIMENTAL/GELÉ — concept distinct de
                                --profile ; profils MINIMAL/TECHNICIAN/
                                RECOVERY/FORENSIC/ADMIN/FULL/CUSTOM]
                                Construire un support logiciel local
  --release-report            Générer le rapport de release
  --dependencies-report       Générer le rapport des dépendances

Intelligence & intégrité (moteur déterministe, aucun appel LLM) [EXPÉRIMENTAL] :
  --smart-advisor              Analyse croisée (dépendances, hashchain, manifeste,
                                couverture catalogue, scellé, rôle) + score priorisé
  --mission-report              Rapport de mission unique (advisor + dépendances)
  --verify-hashchain             Vérifie l'intégrité du journal d'audit chaîné
  --catalog-seal                 Scelle le catalogue embarqué (SHA-256, rôle VAULT)
  --catalog-verify-seal          Vérifie le catalogue embarqué contre son scellé

Verrou de rôle (empêche SONAR_ROLE=Admin sans autorisation):
  --role-bootstrap                     Initialise le secret local (une seule fois, chmod 600)
  --role-issue-token <ROLE> <ID> [J]    Émet un jeton nominatif (Senior/Forensic/Admin/Expert),
                                        valide J jours (défaut 30), ex: Admin j.dupont 14
  --role-revoke-token <JETON>           Révoque un jeton précis (n'affecte pas les autres)
  --role-token <JETON>                  Fournit le jeton pour la session courante (avec --role)
  (env: SONAR_ROLE_TOKEN / SONAR_ROLE_TOKEN_FILE — utilisables sans --disk)

Filigrane de build (traçabilité, pas prévention — voir --help "matériel"):
  --verify-watermark <FICHIER|DOSSIER>  Vérifie l'authenticité d'un filigrane
                                          de build (MANIFEST/BUILD_WATERMARK.txt)
                                          contre le secret local de cette machine
EOF
}

parse_final_args() {
    SONAR_COMMAND="deploy"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --disk)
                [[ $# -ge 2 ]] || error_exit "--disk nécessite une valeur."
                DISK="$2"; shift 2 ;;
            --source)
                [[ $# -ge 2 ]] || error_exit "--source nécessite une valeur."
                SOURCE_DIR="$2"
                ISO_SOURCE_DIR="${SOURCE_DIR}/ISO"
                PORTABLE_SOURCE_DIR="${SOURCE_DIR}/Portable"
                SCRIPTS_SOURCE_DIR="${SOURCE_DIR}/Scripts"
                DRIVERS_SOURCE_DIR="${SOURCE_DIR}/Drivers"
                MACOS_SOURCE_DIR="${SOURCE_DIR}/macOS"
                MANIFEST_SOURCE="${SOURCE_DIR}/MANIFEST.tsv"
                shift 2 ;;
            --yes) YES=true; shift ;;
            --accept-hardware-risk) SONAR_HARDWARE_RISK_ACK=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --batch) [[ $# -ge 2 ]] || error_exit "--batch nécessite une valeur."; BATCH_COUNT="$2"; shift 2 ;;
            --persistence) [[ $# -ge 2 ]] || error_exit "--persistence nécessite une valeur."; PERSISTENCE_COUNT="$2"; shift 2 ;;
            --persistence-size) [[ $# -ge 2 ]] || error_exit "--persistence-size nécessite une valeur."; PERSISTENCE_SIZE="$2"; shift 2 ;;
            --no-ventoy-download) DOWNLOAD_VENTOY=0; shift ;;
            --ca-certificate) [[ $# -ge 2 ]] || error_exit "--ca-certificate nécessite une valeur."; SONAR_CA_CERT="$2"; [[ -f "${SONAR_CA_CERT}" ]] || error_exit "Certificat CA introuvable: ${SONAR_CA_CERT}"; shift 2 ;;
            --gpg-key) [[ $# -ge 2 ]] || error_exit "--gpg-key nécessite une valeur."; SONAR_GPG_KEY="$2"; [[ -f "${SONAR_GPG_KEY}" ]] || error_exit "Clé GPG introuvable: ${SONAR_GPG_KEY}"; shift 2 ;;
            --gpg-sig) [[ $# -ge 2 ]] || error_exit "--gpg-sig nécessite une valeur."; SONAR_GPG_SIG="$2"; [[ -f "${SONAR_GPG_SIG}" ]] || error_exit "Signature GPG introuvable: ${SONAR_GPG_SIG}"; shift 2 ;;
            --no-veracrypt) INCLUDE_VERACRYPT=false; shift ;;
            --protect-catalog) SONAR_PROTECT_CATALOG=true; shift ;;
            --no-logging) INCLUDE_LOGGING=false; shift ;;
            --no-readme) GENERATE_README=false; shift ;;
            --no-ventoy-theme) INCLUDE_VENTOY_THEME=false; shift ;;
            --ventoy-theme) INCLUDE_VENTOY_THEME=true; shift ;;
            --role) [[ $# -ge 2 ]] || error_exit "--role nécessite une valeur."; SONAR_ROLE="$2"; sonar_validate_role "$SONAR_ROLE"; shift 2 ;;
            --role-token) [[ $# -ge 2 ]] || error_exit "--role-token nécessite une valeur."; SONAR_ROLE_TOKEN="$2"; shift 2 ;;
            --security-status) SONAR_COMMAND="security-status"; shift ;;
            --hardware-inventory) SONAR_COMMAND="hardware-inventory"; shift ;;
            --build-manifest)
                SONAR_COMMAND="build-manifest"
                if [[ $# -ge 2 && "${2}" != --* ]]; then MANIFEST_TARGET="$2"; shift 2; else shift; fi ;;
            --verify-manifest) SONAR_COMMAND="verify-manifest"; shift ;;
            --ai) [[ $# -ge 2 ]] || error_exit "--ai nécessite une valeur."; AI_MODE="$2"; shift 2 ;;
            --ai-model) [[ $# -ge 2 ]] || error_exit "--ai-model nécessite une valeur."; AI_MODEL="$2"; shift 2 ;;
            --ai-endpoint) [[ $# -ge 2 ]] || error_exit "--ai-endpoint nécessite une valeur."; AI_ENDPOINT="$2"; shift 2 ;;
            --no-ai-diagnostics) AI_ENABLE_DIAGNOSTICS=false; shift ;;
            --no-ai-inventory) AI_ENABLE_INVENTORY=false; shift ;;
            --no-ai-recommendations) AI_ENABLE_RECOMMENDATIONS=false; shift ;;
            --no-ai-assistant) AI_ENABLE_ASSISTANT=false; shift ;;
            --help|-h) usage_final; exit 0 ;;
            *) error_exit "Option inconnue: $1" ;;
        esac
    done

    sonar_security_init
    sonar_role_enforce_lock || true

    case "${SONAR_COMMAND}" in
        security-status|hardware-inventory|build-manifest|verify-manifest) return 0 ;;
    esac

    [[ -n "${DISK}" ]] || error_exit "--disk est obligatoire."
    [[ -b "${DISK}" ]] || error_exit "Périphérique inexistant: ${DISK}"
    [[ "${BATCH_COUNT}" =~ ^[1-9][0-9]*$ ]] || error_exit "--batch invalide"
    [[ "${PERSISTENCE_COUNT}" =~ ^[0-9]+$ ]] || error_exit "--persistence invalide"
    [[ "${PERSISTENCE_SIZE}" =~ ^[1-9][0-9]*$ ]] || error_exit "--persistence-size invalide"
    [[ "${AI_MODE}" =~ ^(off|auto|local|online)$ ]] || error_exit "--ai invalide: ${AI_MODE}"
    if [[ "${SONAR_PROTECT_CATALOG}" == "true" && -z "${SONAR_PROTECT_PASSPHRASE:-}" ]]; then
        error_exit "--protect-catalog nécessite SONAR_PROTECT_PASSPHRASE (jamais en argument, voir --help)."
    fi
}

require_cmd_final() {
    command -v "$1" >/dev/null 2>&1 || error_exit "Dépendance manquante: $1"
}

# ============================================================================
# SONAR AI LAYER — diagnostic, inventaire, recommandations et assistant local
# ============================================================================
ai_log() { log "[IA] $1"; }

ai_detect_provider() {
    AI_PROVIDER="none"
    if [[ "${AI_MODE}" == "off" ]]; then return; fi
    # Ollama: API locale sans clé, idéale pour un mode hors-ligne.
    if [[ "${AI_MODE}" != "online" ]] && command -v curl >/dev/null 2>&1 && curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        AI_PROVIDER="ollama"
        return
    fi
    # llama.cpp: serveur compatible OpenAI sur localhost.
    if [[ "${AI_MODE}" != "online" ]] && command -v curl >/dev/null 2>&1 && curl -fsS --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
        AI_PROVIDER="llama.cpp"
        return
    fi
    if [[ "${AI_MODE}" == "online" && -n "${AI_ENDPOINT}" ]] && command -v curl >/dev/null 2>&1; then
        AI_PROVIDER="openai-compatible"
        return
    fi
    if [[ "${AI_MODE}" == "local" ]]; then
        ai_log "Aucun moteur IA local détecté; fonctions déterministes conservées."
    fi
}

ai_collect_hardware() {
    local out="$1"
    mkdir -p "$(dirname "$out")"
    {
        echo "timestamp=$(date -Iseconds)"
        echo "kernel=$(uname -srmo 2>/dev/null || true)"
        echo "arch=$(uname -m 2>/dev/null || true)"
        echo "cpu=$(awk -F: '/model name|Hardware/ {gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
        echo "ram_gib=$(awk '/MemTotal:/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo unknown)"
        echo "gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -5 | tr '\n' ';' || true)"
        echo "target=$(lsblk -dn -o NAME,SIZE,MODEL,TRAN "${DISK}" 2>/dev/null | tr '\n' ';' || true)"
    } > "$out"
}

ai_static_inventory() {
    local mp="$1" out="${2:-${WORK_DIR}/ai_inventory.tsv}"
    {
        printf 'type\tpath\tsize_bytes\tsha256\n'
        find "${mp}/ISO" "${mp}/Portable" "${mp}/Scripts" "${mp}/Drivers" "${mp}/macOS" -type f -print0 2>/dev/null |
        while IFS= read -r -d '' f; do
            local rel size hash type
            rel="${f#${mp}/}"; size=$(stat -c '%s' "$f" 2>/dev/null || echo 0); hash=$(sha256sum "$f" 2>/dev/null | awk '{print $1}' || echo unknown)
            case "$rel" in ISO/*) type=ISO;; Portable/*) type=PORTABLE;; Scripts/*) type=SCRIPT;; Drivers/*) type=DRIVER;; macOS/*) type=MACOS;; *) type=OTHER;; esac
            printf '%s\t%s\t%s\t%s\n' "$type" "$rel" "$size" "$hash"
        done
    } > "$out"
    echo "$out"
}

ai_static_diagnose() {
    local mp="$1" report="$2"
    local iso portable scripts macos drivers score=100
    iso=$(find "${mp}/ISO" -type f -iname '*.iso' 2>/dev/null | wc -l)
    portable=$(find "${mp}/Portable" -type f 2>/dev/null | wc -l)
    scripts=$(find "${mp}/Scripts" -type f 2>/dev/null | wc -l)
    macos=$(find "${mp}/macOS" -type f 2>/dev/null | wc -l)
    drivers=$(find "${mp}/Drivers" -type f 2>/dev/null | wc -l)
    (( iso > 0 )) || score=$((score-25))
    (( scripts > 0 )) || score=$((score-10))
    (( macos > 0 )) || score=$((score-10))
    (( drivers > 0 )) || score=$((score-5))
    (( score < 0 )) && score=0
    cat > "$report" <<EOF
SONAR AI — DIAGNOSTIC DETERMINISTE
Date: $(date -Iseconds)
Score structurel: ${score}/100
ISO: ${iso}
Portable: ${portable}
Scripts: ${scripts}
Drivers: ${drivers}
Ressources macOS: ${macos}

INTERPRETATION
- Ce score ne prouve pas le démarrage matériel.
- Les ISO doivent être vérifiées par SHA-256 et testées sur matériel réel.
- UEFI, Secure Boot, WinPE/WinRE, Linux Live/Rescue et macOS doivent être testés séparément.
EOF
    echo "$report"
}

ai_generate_recommendations() {
    local report="$1" inv="$2" out="$3"
    cat > "$out" <<EOF
SONAR AI — RECOMMANDATIONS
Date: $(date -Iseconds)

1. PRIORITE BOOT
Tester d'abord Ventoy, UEFI, Secure Boot et le menu ISO.

2. PRIORITE RECOVERY
Tester WinPE/WinRE, Linux Rescue, Clonezilla, GParted et récupération de données.

3. PRIORITE MACOS
Séparer explicitement Mac Intel, Apple Silicon et Recovery. Ne pas traiter une ressource macOS comme une ISO Linux générique.

4. INTEGRITE
Conserver les SHA-256 et vérifier les signatures officielles lorsqu'elles existent.

5. IA
Utiliser l'IA pour expliquer, classer, diagnostiquer et recommander; aucune opération destructive ne doit être décidée ou exécutée automatiquement par le modèle.

Inventaire: ${inv}
Diagnostic: ${report}
EOF
}

ai_parse_llm_response() {
    # Reads a provider JSON response on stdin; prints the extracted text and
    # returns 0, or prints nothing and returns 1 on any malformed/empty input.
    local provider="$1"
    python3 -c '
import json, sys
provider = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
try:
    if provider == "ollama":
        out = d.get("response", "")
    else:
        out = d.get("choices", [{}])[0].get("message", {}).get("content", "")
except Exception:
    out = ""
if not out:
    sys.exit(1)
sys.stdout.write(out)
' "$provider"
}

ai_query_local() {
    local prompt="$1" response
    [[ "${AI_PROVIDER}" != "none" ]] || { ai_log "Aucun fournisseur IA actif."; return 1; }
    case "${AI_PROVIDER}" in
        ollama)
            local model="${AI_MODEL:-gemma3}"
            # model/prompt passes par stdin, pas en argv : un argv est
            # lisible par tout autre processus local via /proc/<pid>/cmdline
            # (ou "ps") pendant l'execution — meme categorie de probleme deja
            # corrigee pour les secrets HMAC (v3.14.0). Impact ici plus
            # faible (prompt consultatif, pas un secret), mais meme
            # traitement pour rester coherent. Premiere ligne = model,
            # reste (y compris d'eventuels saut de ligne) = prompt.
            response=$(printf '%s\n%s' "$model" "$prompt" | python3 -c '
import json, sys
data = sys.stdin.read().split("\n", 1)
model = data[0]
prompt = data[1] if len(data) > 1 else ""
print(json.dumps({"model": model, "prompt": prompt, "stream": False}))
' | { curl -fsS --max-time 120 http://127.0.0.1:11434/api/generate \
              -H 'Content-Type: application/json' -d @-; }) || { ai_log "Ollama: échec de la requête HTTP."; return 1; }
            [[ -n "${response}" ]] || { ai_log "Ollama: réponse vide."; return 1; }
            ai_parse_llm_response "ollama" <<<"${response}" || { ai_log "Ollama: réponse JSON invalide ou vide."; return 1; }
            ;;
        llama.cpp)
            local model="${AI_MODEL:-local}"
            response=$(printf '%s\n%s' "$model" "$prompt" | python3 -c '
import json, sys
data = sys.stdin.read().split("\n", 1)
model = data[0]
prompt = data[1] if len(data) > 1 else ""
print(json.dumps({"model": model, "messages": [{"role": "system", "content": "Tu es Sonar AI. Tu es prudent, factuel et tu ne proposes jamais une action destructive sans validation humaine."}, {"role": "user", "content": prompt}], "temperature": 0.1}))
' | { curl -fsS --max-time 120 http://127.0.0.1:8080/v1/chat/completions \
              -H 'Content-Type: application/json' -d @-; }) || { ai_log "llama.cpp: échec de la requête HTTP."; return 1; }
            [[ -n "${response}" ]] || { ai_log "llama.cpp: réponse vide."; return 1; }
            ai_parse_llm_response "llama.cpp" <<<"${response}" || { ai_log "llama.cpp: réponse JSON invalide ou vide."; return 1; }
            ;;
        openai-compatible)
            [[ -n "${OPENAI_API_KEY:-}" ]] || { ai_log "openai-compatible: OPENAI_API_KEY absente."; return 1; }
            local -a curl_opts=(-fsS --max-time 120)
            [[ -n "${SONAR_CA_CERT:-}" ]] && curl_opts+=(--cacert "${SONAR_CA_CERT}")
            response=$(printf '%s\n%s' "${AI_MODEL:-gpt-4.1-mini}" "$prompt" | python3 -c '
import json, sys
data = sys.stdin.read().split("\n", 1)
model = data[0]
prompt = data[1] if len(data) > 1 else ""
print(json.dumps({"model": model, "messages": [{"role": "system", "content": "Tu es Sonar AI. Ne donne jamais d ordre destructif automatique. Réponds de façon factuelle."}, {"role": "user", "content": prompt}], "temperature": 0.1}))
' | { curl "${curl_opts[@]}" "${AI_ENDPOINT}" \
              -H 'Content-Type: application/json' -H "Authorization: Bearer ${OPENAI_API_KEY}" -d @-; }) || { ai_log "openai-compatible: échec de la requête HTTP."; return 1; }
            [[ -n "${response}" ]] || { ai_log "openai-compatible: réponse vide."; return 1; }
            ai_parse_llm_response "openai-compatible" <<<"${response}" || { ai_log "openai-compatible: réponse JSON invalide ou vide."; return 1; }
            ;;
        *)
            ai_log "Fournisseur IA inconnu: ${AI_PROVIDER}"
            return 1
            ;;
    esac
}

install_ai_layer_final() {
    [[ "${AI_ENABLE_ASSISTANT}" == "true" ]] || return 0
    [[ "${DRY_RUN}" == "true" ]] && { ai_log "[DRY-RUN] Couche IA installée."; return; }
    local mp="$1"
    mkdir -p "${mp}/${AI_DIR_NAME}" "${mp}/Docs/AI"
    cat > "${mp}/${AI_DIR_NAME}/sonar-ai.sh" <<'AIS'
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT/AI/ai_diagnostic.txt"
INV="$ROOT/AI/ai_inventory.tsv"
REC="$ROOT/AI/ai_recommendations.txt"
echo "SONAR AI"
echo "Diagnostic : $REPORT"
echo "Inventaire : $INV"
echo "Recommandations : $REC"
if command -v ollama >/dev/null 2>&1 && curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "Moteur local Ollama détecté."
  echo "Pour une analyse conversationnelle, utilisez Ollama avec les fichiers du dossier AI."
elif curl -fsS --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
  echo "Serveur llama.cpp détecté sur localhost:8080."
else
  echo "Aucun moteur LLM local détecté. Les fonctions déterministes restent disponibles."
fi
AIS
    chmod +x "${mp}/${AI_DIR_NAME}/sonar-ai.sh"
    cat > "${mp}/Docs/AI/README_AI.md" <<'EOF'
# SONAR AI

Sonar AI est conçu selon une stratégie **offline-first**.

## Fonctions
- inventaire automatique des ISO, scripts, pilotes et ressources macOS;
- contrôle d'intégrité SHA-256;
- diagnostic structurel;
- recommandations de maintenance;
- assistant LLM local optionnel;
- analyse des journaux;
- aide à la résolution d'incidents;
- classification et recherche dans le catalogue.

## Moteurs locaux
Ollama expose normalement son API locale sur `http://localhost:11434/api`.
llama.cpp peut exposer un serveur HTTP compatible OpenAI.

Sonar n'embarque pas de poids de modèle volumineux dans le script : les modèles
sont fournis séparément dans `AI/Models/` ou installés sur la machine hôte.

## Sécurité
L'IA est consultative. Elle ne doit jamais décider seule d'un formatage,
d'une suppression, d'une modification de partition ou d'une action de sécurité.
Toute opération destructive reste sous contrôle humain et du moteur Sonar.
EOF
    mkdir -p "${mp}/AI/Models" "${mp}/AI/Logs"
    printf 'provider\tmode\tmodel\tendpoint\n%s\t%s\t%s\t%s\n' "${AI_PROVIDER}" "${AI_MODE}" "${AI_MODEL:-auto}" "${AI_ENDPOINT:-local}" > "${mp}/AI/AI_CONFIG.tsv"
}

run_ai_final() {
    [[ "${AI_MODE}" != "off" ]] || return 0
    ai_detect_provider
    [[ "${DRY_RUN}" == "true" ]] && { ai_log "[DRY-RUN] IA: provider=${AI_PROVIDER}"; return; }
    local mp inv report prompt answer
    mp="${1:-}"
    [[ -n "$mp" ]] || return 0
    mkdir -p "${mp}/AI" "${mp}/AI/Logs"
    if [[ "${AI_ENABLE_DIAGNOSTICS}" == "true" ]]; then
        ai_collect_hardware "${mp}/AI/ai_hardware.txt"
    fi
    if [[ "${AI_ENABLE_INVENTORY}" == "true" ]]; then
        inv=$(ai_static_inventory "$mp" "${mp}/AI/ai_inventory.tsv")
    else
        inv="désactivé"
    fi
    if [[ "${AI_ENABLE_DIAGNOSTICS}" == "true" ]]; then
        report=$(ai_static_diagnose "$mp" "${mp}/AI/ai_diagnostic.txt")
    else
        report="désactivé"
    fi
    if [[ "${AI_ENABLE_RECOMMENDATIONS}" == "true" ]]; then
        ai_generate_recommendations "$report" "$inv" "${mp}/AI/ai_recommendations.txt"
    fi
    if [[ "${AI_PROVIDER}" != "none" && "${AI_ENABLE_ASSISTANT}" == "true" ]]; then
        prompt="Analyse le support Sonar. Donne seulement les risques et améliorations non destructives. Inventaire=${inv}; diagnostic=${report}. Ne demande jamais de supprimer, formater ou partitionner automatiquement."
        if answer=$(ai_query_local "$prompt" 2>/dev/null); then
            printf '%s\n' "$answer" > "${mp}/AI/ai_llm_analysis.txt"
            ai_log "Analyse LLM locale générée via ${AI_PROVIDER}."
        else
            ai_log "LLM non disponible ou échec; diagnostic déterministe conservé."
        fi
    fi
    printf 'provider=%s\nmode=%s\nmodel=%s\nendpoint=%s\n' "${AI_PROVIDER}" "${AI_MODE}" "${AI_MODEL:-auto}" "${AI_ENDPOINT:-local}" > "${mp}/AI/AI_STATUS.txt"
}

preflight_final() {
    log "=== PRE-FLIGHT SONAR FINAL ==="
    [[ "$(id -u)" -eq 0 ]] || error_exit "Exécuter avec sudo/root."
    for c in awk basename blockdev findmnt lsblk mount umount sync dd mkfs.ext4 sha256sum tar gzip sed grep find sort date head python3 wget curl cp; do
        require_cmd_final "$c"
    done
    [[ -d "${SOURCE_DIR}" ]] || error_exit "Source absente: ${SOURCE_DIR}"
    mkdir -p "${SOURCE_DIR}"/{ISO,Portable,Scripts,Drivers,macOS,Branding}
    local rootpk targetpk
    rootpk="$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -n1 || true)"
    targetpk="$(lsblk -no PKNAME "${DISK}" 2>/dev/null | head -n1 || true)"
    [[ -n "${targetpk}" ]] || targetpk="$(basename "${DISK}")"
    [[ -z "${rootpk}" || "${targetpk}" != "${rootpk}" ]] || error_exit "SÉCURITÉ: disque système détecté."
    local size_bytes size_gib
    size_bytes="$(blockdev --getsize64 "${DISK}")"
    size_gib=$((size_bytes / 1024 / 1024 / 1024))
    (( size_gib >= MIN_DISK_GIB )) || error_exit "Disque trop petit: ${size_gib} GiB < ${MIN_DISK_GIB} GiB"
    log_ok "Disque cible: ${DISK} (${size_gib} GiB)"
    if [[ "${DRY_RUN}" != "true" ]]; then
        sonar_require_hardware_risk_ack
    fi
    if [[ "${DRY_RUN}" != "true" && "${YES}" != "true" ]]; then
        echo "ATTENTION: ${DISK} sera ENTIEREMENT EFFACE."
        echo "Tapez exactement: EFFACER ${DISK}"
        read -r answer
        [[ "${answer}" == "EFFACER ${DISK}" ]] || error_exit "Confirmation refusée."
    fi
}

sha256_final() { sha256sum "$1" | awk '{print $1}'; }

sonar_gpg_verify() {
    local file="$1"
    if [[ -z "${SONAR_GPG_KEY}" || -z "${SONAR_GPG_SIG}" ]]; then
        log "[INFO] Vérification GPG non configurée (--gpg-key/--gpg-sig absents); SHA-256 seul fait foi."
        return 0
    fi
    command -v gpg >/dev/null 2>&1 || error_exit "gpg demandé (--gpg-key/--gpg-sig) mais introuvable sur le système."
    local gnupg_home
    gnupg_home="$(mktemp -d /tmp/sonar-gnupg-XXXXXX)"
    chmod 700 "${gnupg_home}"
    if ! GNUPGHOME="${gnupg_home}" gpg --batch --quiet --import "${SONAR_GPG_KEY}" >/dev/null 2>&1; then
        rm -rf "${gnupg_home}"
        error_exit "Import de la clé GPG échoué: ${SONAR_GPG_KEY}"
    fi
    if GNUPGHOME="${gnupg_home}" gpg --batch --quiet --verify "${SONAR_GPG_SIG}" "${file}" 2>/dev/null; then
        log_ok "Signature GPG vérifiée: ${file}"
        rm -rf "${gnupg_home}"
        return 0
    else
        rm -rf "${gnupg_home}"
        error_exit "Signature GPG invalide pour: ${file}"
    fi
}

download_ventoy_final() {
    local archive="${WORK_DIR}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
    local local1="${SOURCE_DIR}/Ventoy/ventoy-${VENTOY_VERSION}-linux.tar.gz"
    local local2="${SOURCE_DIR}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
    mkdir -p "${WORK_DIR}"
    if [[ -f "${local1}" ]]; then
        cp -f "${local1}" "${archive}"
    elif [[ -f "${local2}" ]]; then
        cp -f "${local2}" "${archive}"
    elif [[ "${DOWNLOAD_VENTOY}" -eq 1 && "${DRY_RUN}" != "true" ]]; then
        local url="https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
        log "Téléchargement Ventoy officiel"
        local -a wget_opts=(--https-only --tries=3 --timeout=30)
        [[ -n "${SONAR_CA_CERT}" ]] && wget_opts+=(--ca-certificate="${SONAR_CA_CERT}")
        wget "${wget_opts[@]}" -O "${archive}" "${url}" || error_exit "Téléchargement Ventoy échoué."
    elif [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] Ventoy serait téléchargé."
        return
    else
        error_exit "Archive Ventoy locale introuvable (${local1} ou ${local2}) et --no-ventoy-download actif."
    fi
    [[ "${DRY_RUN}" == "true" ]] && return
    local actual
    actual="$(sha256_final "${archive}")"
    [[ "${actual}" == "${VENTOY_SHA256}" ]] || error_exit "SHA256 Ventoy invalide."
    sonar_gpg_verify "${archive}"
    tar -xzf "${archive}" -C "${WORK_DIR}"
    VENTOY_DIR="${WORK_DIR}/ventoy-${VENTOY_VERSION}"
    [[ -x "${VENTOY_DIR}/Ventoy2Disk.sh" ]] || error_exit "Ventoy2Disk.sh introuvable."
}

install_ventoy_final() {
    log "=== INSTALLATION VENTOY ${VENTOY_VERSION} ==="
    [[ "${DRY_RUN}" == "true" ]] && { log "[DRY-RUN] GPT + Secure Boot seraient utilisés."; return; }
    "${VENTOY_DIR}/Ventoy2Disk.sh" -I -g -s "${DISK}" || error_exit "Installation Ventoy échouée."
    sync
}

get_ventoy_partition_final() {
    lsblk -lnpo NAME,TYPE "${DISK}" | awk '$2=="part" {print $1; exit}'
}

mount_ventoy_final() {
    local part mp
    part="$(get_ventoy_partition_final)"
    [[ -b "${part}" ]] || error_exit "Partition Ventoy introuvable."
    mp="$(mktemp -d /mnt/sonar-ventoy-XXXXXX)"
    if ! mount "${part}" "${mp}"; then
        rmdir "${mp}" 2>/dev/null || true
        error_exit "Montage impossible."
    fi
    SONAR_MOUNTED_PARTS="${SONAR_MOUNTED_PARTS} ${mp}"
    echo "${mp}"
}

unmount_final() {
    sync
    umount "$1" 2>/dev/null || error_exit "Démontage impossible: $1"
    rmdir "$1" 2>/dev/null || true
    SONAR_MOUNTED_PARTS="${SONAR_MOUNTED_PARTS/ $1/}"
}

copy_tree_final() {
    [[ -d "$1" ]] || { log "[INFO] Source absente: $1"; return; }
    mkdir -p "$2"
    # --no-preserve=ownership: the destination is Ventoy's exFAT data
    # partition, which has no concept of Unix uid/gid. Plain `cp -a`
    # always fails to chown there (found 2026-09-14, first real hardware
    # deploy) and reports a false "copie incomplète" — the file content
    # itself copies fine, only the (meaningless-on-exFAT) ownership bit
    # can't be applied. Keep the rest of archive mode (recursion,
    # timestamps, symlinks) — just drop the one attribute this
    # destination fundamentally can't represent.
    if ! cp -a --no-preserve=ownership "$1/." "$2/"; then
        log_err "Copie incomplète: $1 -> $2"
    fi
}

create_persistence_final() {
    (( PERSISTENCE_COUNT > 0 )) || return 0
    [[ "${DRY_RUN}" == "true" ]] && { log "[DRY-RUN] Persistance ${PERSISTENCE_COUNT} x ${PERSISTENCE_SIZE} GiB."; return; }
    local mp i img
    mp="$(mount_ventoy_final)"
    mkdir -p "${mp}/persistence"
    for ((i=1;i<=PERSISTENCE_COUNT;i++)); do
        img="${mp}/persistence/env${i}.dat"
        dd if=/dev/zero of="${img}" bs=1M count=$((PERSISTENCE_SIZE * 1024)) status=progress 2>&1 | \
            while IFS= read -r line; do log "    $line"; done
        mkfs.ext4 -F -L "SONAR_ENV${i}" "${img}" >/dev/null
    done
    unmount_final "${mp}"
    log_ok "Persistance créée: ${PERSISTENCE_COUNT} x ${PERSISTENCE_SIZE} GiB."
}

# sonar_prepare_ventoy_theme MOUNTPOINT: installs a background for
# Ventoy's boot menu (a GRUB-level PNG, via Ventoy's own documented theme
# plugin keys: file/gfxmode/boot_menu_language/ventoy_left/ventoy_top/
# ventoy_color in ventoy.json). Purely cosmetic — never required for
# boot, never blocks the deploy if anything here fails.
#
# Two sources, in priority order:
#   1. SOURCE_DIR/Branding/background.{png,jpg,jpeg} — supplied locally
#      by the operator at build time (never embedded in this script or
#      its git history, same reasoning as Ventoy's own archive being
#      downloaded/locally-supplied rather than embedded). If present,
#      SONAR_VENTOY_TITLE/SONAR_VENTOY_CREDIT are burned into it via
#      ImageMagick (`convert`) when available — GRUB only ever displays
#      a flat PNG, ventoy.json has no "overlay this text" field, so any
#      title/credit has to be part of the pixels. Without ImageMagick,
#      the operator's image is used as-is (no text), logged, never fatal.
#   2. Branding/default_background.png — shipped in this repo (the one
#      binary asset it carries; unlike the script itself, this doesn't
#      need to be text/self-auditable, it's inert boot-menu wallpaper).
#      Generated once, title/credit already baked in, used verbatim with
#      no further processing — this is the out-of-the-box look when the
#      operator hasn't supplied anything of their own.
# Neither present (e.g. repo asset removed) → silently does nothing,
# stock Ventoy behavior.
sonar_prepare_ventoy_theme() {
    local mp="$1" src="" cand out_dir out w prebaked=false
    [[ "${INCLUDE_VENTOY_THEME}" == "true" ]] || return 0
    for cand in "${SOURCE_DIR}/Branding/background.png" \
                "${SOURCE_DIR}/Branding/background.jpg" \
                "${SOURCE_DIR}/Branding/background.jpeg"; do
        [[ -s "$cand" ]] && { src="$cand"; break; }
    done
    if [[ -z "$src" && -s "${SONAR_ROOT}/Branding/default_background.png" ]]; then
        src="${SONAR_ROOT}/Branding/default_background.png"
        prebaked=true
    fi
    [[ -n "$src" ]] || return 0
    out_dir="${mp}/ventoy/theme"
    mkdir -p "${out_dir}"
    out="${out_dir}/background.png"
    if [[ "$prebaked" == "true" ]]; then
        cp -f "$src" "${out}"
    elif command -v convert >/dev/null 2>&1; then
        # -resize '800x600>' shrinks only if larger, never enlarges. This
        # resize+palette pipeline is kept because it's strictly cheaper
        # (never a regression) — NOT because it's confirmed to fix the
        # actual crash. Real-hardware history (HP EliteBook 840 G3,
        # 2026-09-15, see CHANGELOG v3.25.0/v3.26.0): THREE image variants
        # tested, ~6MB decoded (1920x1080 RGB), ~2.25MB (1024x768 RGB), and
        # ~480KB (800x600 indexed/palette, 1 byte/pixel) — all three
        # produced the IDENTICAL "alloc magic is broken" crash. A 12x
        # reduction in decoded image size made no observable difference,
        # which is strong evidence the decoded-image-size theory is WRONG
        # (or at best incomplete): the actual crash is more likely in
        # Ventoy's gfxmenu theme module itself on this firmware, not in
        # how large the PNG is. `--ventoy-theme` stays opt-in and
        # documented as unreliable rather than "fixed by a smaller image".
        local resized="${out_dir}/.resized.png"
        # Resize first, to a temp file, then measure THAT — sizing the
        # banner box from the pre-resize width would composite it onto a
        # canvas narrower than the box itself once a large image shrinks.
        if convert "$src" -resize '800x600>' "${resized}" 2>/dev/null; then
            w="$(identify -format '%w' "${resized}" 2>/dev/null || echo 800)"
            if ! convert "${resized}" \
                    \( -size "${w}x110" xc:'rgba(0,0,0,0.55)' \) -gravity south -compose over -composite \
                    -gravity south -fill white -pointsize 34 -annotate +0+58 "${SONAR_VENTOY_TITLE}" \
                    -gravity south -fill '#cccccc' -pointsize 18 -annotate +0+20 "${SONAR_VENTOY_CREDIT}" \
                    -colors 256 "PNG8:${out}" 2>/dev/null; then
                log "[SONAR] Filigrane du fond Ventoy : échec ImageMagick, copie de l'image redimensionnée telle quelle."
                cp -f "${resized}" "${out}"
            fi
            rm -f "${resized}"
        else
            log "[SONAR] Filigrane du fond Ventoy : échec ImageMagick, copie de l'image telle quelle (non redimensionnée)."
            cp -f "$src" "${out}"
        fi
    else
        log "[SONAR] ImageMagick (convert) absent — fond Ventoy déployé sans titre/crédit incrustés, ET sans redimensionnement de sécurité."
        cp -f "$src" "${out}"
    fi
    # Cause racine du crash "alloc magic is broken" identifiee le
    # 2026-09-16 (voir CHANGELOG.md) : la cle "file" de ventoy.json doit
    # pointer vers un fichier theme.txt (script de thème GRUB2), PAS
    # directement vers l'image PNG — documentation officielle
    # ventoy.net/en/plugin_theme.html, exemple `"file":
    # "/ventoy/theme/blur/theme.txt"`. generate_ventoy_json_final()
    # pointait par erreur "file" directement sur background.png : GRUB
    # tentait alors de PARSER les octets binaires du PNG comme un script
    # de thème, ce qui explique pourquoi la taille de l'image n'a jamais
    # eu d'influence sur le crash (3 tailles radicalement différentes,
    # même échec identique — la taille n'était jamais la variable en
    # cause).
    #
    # CORRIGE 2026-09-20 (test reel HP EliteBook 840 G3) : le theme.txt
    # precedent ne contenait QUE desktop-image/title-text — le crash GRUB
    # avait disparu, mais la clé restait figée sur le fond d'écran sans
    # aucun menu. Un theme GRUB2 (gfxmenu) ne dessine un menu que si le
    # composant "+ boot_menu" y est declare ; sans lui, seul le fond
    # s'affiche. Le commentaire d'origine ("une seule directive necessaire")
    # etait faux. Position choisie pour laisser le bandeau du bas
    # (titre/credit incrustes, ~74-92% de hauteur) degage.
    # Panneau sombre semi-transparent derriere le menu (menu_c.png,
    # style "menu_*") seulement si ImageMagick est present : le menu reste
    # fonctionnel sans, juste moins lisible sur le globe.
    local pixmap_line=""
    if command -v convert >/dev/null 2>&1 \
       && convert -size 8x8 xc:'rgba(0,10,4,0.80)' PNG32:"${out_dir}/menu_c.png" 2>/dev/null; then
        pixmap_line='    menu_pixmap_style = "menu_*"'
    fi
    cat > "${out_dir}/theme.txt" <<THEME_TXT_EOF
desktop-image: "background.png"
title-text: ""
terminal-font: "Unifont Regular 16"

+ boot_menu {
    left = 6%
    top = 10%
    width = 50%
    height = 58%
    item_font = "Unifont Regular 16"
    item_color = "#7dff7d"
    selected_item_color = "#ffffff"
    item_height = 28
    item_padding = 6
    item_spacing = 4
    scrollbar = false
${pixmap_line}
}
THEME_TXT_EOF
    sonar_audit "VENTOY_THEME_INSTALLED" "source=${src}"
}

generate_ventoy_json_final() {
    local mp="$1"
    python3 - "$mp" "$PERSISTENCE_COUNT" <<'PY'
import json, os, sys
mp=sys.argv[1]; n=int(sys.argv[2])
isos=[]
root=os.path.join(mp,"ISO")
for r,_,fs in os.walk(root):
    for f in fs:
        if f.lower().endswith(".iso"):
            isos.append("/ISO/"+os.path.relpath(os.path.join(r,f),root).replace(os.sep,"/"))
ubuntu=[x for x in sorted(isos) if "ubuntu" in os.path.basename(x).lower()]
cfg={"control":[
 {"VTOY_DEFAULT_SEARCH_ROOT":"/ISO"},
 {"VTOY_DEFAULT_KBD_LAYOUT":"azerty"},
 {"VTOY_TIMEOUT":"10"}],
 "persistence":[]}
for i,img in enumerate(ubuntu[:n],1):
    cfg["persistence"].append({"image":img,"backend":[f"/persistence/env{i}.dat"]})
theme_txt = os.path.join(mp, "ventoy", "theme", "theme.txt")
if os.path.isfile(theme_txt):
    # Keys per Ventoy's own documented theme plugin (ventoy.net) — file is
    # relative to the Ventoy data partition root, same convention as ISO
    # paths above. "file" DOIT pointer vers theme.txt (script de thème
    # GRUB2), pas vers l'image PNG directement — cause racine du crash
    # "alloc magic is broken" identifiee le 2026-09-16 (voir CHANGELOG.md
    # et le commentaire dans sonar_prepare_ventoy_theme, qui genere ce
    # theme.txt). sonar_prepare_ventoy_theme() est ce qui depose a la
    # fois background.png (indexed/palette, redimensionne si ImageMagick
    # disponible) et theme.txt (qui reference background.png via
    # desktop-image) ; ce bloc-ci se contente de cabler theme.txt dans
    # ventoy.json.
    cfg["theme"] = {
        "file": "/ventoy/theme/theme.txt",
        # "auto" d'abord (GRUB choisit via GOP/EDID du firmware -> résolution native de l'écran
        # au lieu d'un 4:3 basse résolution étiré) ; 1024x768 puis 800x600 restent en repli, dans
        # l'ordre PROUVE fonctionnel sur le HP EliteBook 840 G3 (voir CHANGELOG, 3.40.1/3.41.0) si
        # "auto" échoue sur un firmware donné. Non reconfirmé par un boot reel depuis ce changement.
        "gfxmode": "auto,1024x768,800x600",
        "boot_menu_language": "fr",
        "ventoy_left": "2%",
        "ventoy_top": "96%",
        "ventoy_color": "#7dff7d",
    }
os.makedirs(os.path.join(mp,"ventoy"),exist_ok=True)
with open(os.path.join(mp,"ventoy","ventoy.json"),"w",encoding="utf-8") as f:
    json.dump(cfg,f,indent=2)
PY
}

copy_payload_final() {
    [[ "${DRY_RUN}" == "true" ]] && { log "[DRY-RUN] Contenu SONAR copié."; return; }
    local mp
    mp="$(mount_ventoy_final)"
    mkdir -p "${mp}"/{ISO,Portable,Scripts,Drivers,macOS,persistence,Logs,Docs,MANIFEST,ventoy,AI-Downloads}
    copy_tree_final "${ISO_SOURCE_DIR}" "${mp}/ISO"
    copy_tree_final "${PORTABLE_SOURCE_DIR}" "${mp}/Portable"
    copy_tree_final "${SCRIPTS_SOURCE_DIR}" "${mp}/Scripts"
    copy_tree_final "${DRIVERS_SOURCE_DIR}" "${mp}/Drivers"
    copy_tree_final "${MACOS_SOURCE_DIR}" "${mp}/macOS"
    [[ -f "${MANIFEST_SOURCE}" ]] && cp -f "${MANIFEST_SOURCE}" "${mp}/MANIFEST/MANIFEST.tsv"
    # Outils résolus/vérifiés par --ai-download (SOURCE_DIR/Downloads) : copiés à part,
    # avec leur manifeste, pour rester traçables (source, SHA256, OS/ARCH cible) et ne
    # jamais se mélanger silencieusement aux outils choisis manuellement par l'opérateur.
    local ai_downloads="${SOURCE_DIR}/Downloads"
    local ai_results="${SOURCE_DIR}/MANIFEST_AI_RESULTS.tsv"
    if [[ -d "${ai_downloads}" ]]; then
        copy_tree_final "${ai_downloads}" "${mp}/AI-Downloads"
    fi
    [[ -f "${ai_results}" ]] && cp -f "${ai_results}" "${mp}/AI-Downloads/MANIFEST_AI_RESULTS.tsv"
    generate_tool_index_final "${mp}"
    sonar_prepare_ventoy_theme "${mp}"
    generate_ventoy_json_final "${mp}"
    [[ "${INCLUDE_VERACRYPT}" == "true" ]] && sonar_generate_vault_helper "${mp}/Scripts"
    sonar_export_field_files "${mp}"
    [[ -s "${SONAR_FIELD_PINS_FILE}" ]] && cp -f "${SONAR_FIELD_PINS_FILE}" "${mp}/MANIFEST/FIELD_PINS.tsv"
    # Une protection demandee mais impossible (gpg absent, role insuffisant, passphrase absente)
    # ne doit PAS interrompre le deploiement (set -e : le "return 1" laisserait la cle montee,
    # sans filigrane) : on continue, en le disant clairement.
    if ! sonar_protect_catalog_final "${mp}"; then
        log "[PROTECT] ATTENTION : protection du catalogue NON appliquee — le deploiement continue, MANIFEST.tsv reste EN CLAIR sur la cle."
        sonar_audit "CATALOG_PROTECTION_SKIPPED" "mount=${mp}"
    fi
    sonar_generate_build_watermark "${mp}"
    unmount_final "${mp}"
}

# sonar_field_export MOUNT_POINT: met à jour SONAR Field (profils, script,
# PIN) sur une clé déjà déployée, SANS repasser par --disk (donc sans
# retoucher Ventoy ni le contenu ISO/Portable déjà en place). Commande
# indépendante — mêmes deux lignes que copy_payload_final, isolées pour
# pouvoir rafraîchir juste la partie SONAR Field d'une clé existante.
# sonar_diag_analyze FACTS [--symptom S] [--ai] : rejoue le moteur de regles
# du diagnostic intelligent (tools/sonar_diag.sh) sur des faits collectes
# ailleurs (WinPE, Linux live, autre poste) — typiquement sur le PC du
# technicien, ou Ollama local permet --ai. Lecture seule : ne touche a aucune
# machine, n'ecrit rien. Role AUDIT requis (lecture) comme --diagnostic.
sonar_diag_analyze() {
    sonar_require_role AUDIT || return 1
    local tool="${SONAR_SCRIPT_DIR}/tools/sonar_diag.sh"
    [[ -f "$tool" ]] || { echo "[SONAR][ERROR] ${tool} introuvable." >&2; return 2; }
    [[ $# -ge 1 && "${1:-}" != --* ]] || { echo "Usage: --diag-analyze <faits.tsv> [--symptom boot|bsod|slow|data|password|virus|other] [--ai]" >&2; return 2; }
    local facts="$1"; shift
    sonar_audit "DIAG_ANALYZE" "facts=$(basename "$facts");ai=$([[ " $* " == *" --ai "* ]] && echo yes || echo no)"
    bash "$tool" --analyze "$facts" "$@"
}

sonar_field_export() {
    local mp="${1:-}"
    [[ -n "$mp" ]] || { echo "[SONAR][ERROR] --field-export nécessite un point de montage." >&2; return 2; }
    [[ -d "$mp" ]] || { echo "[SONAR][ERROR] '${mp}' n'est pas un dossier accessible." >&2; return 2; }
    sonar_export_field_files "${mp}"
    [[ -s "${SONAR_FIELD_PINS_FILE}" ]] && cp -f "${SONAR_FIELD_PINS_FILE}" "${mp}/MANIFEST/FIELD_PINS.tsv"
    sonar_audit "FIELD_EXPORT" "mount=${mp}"
    echo "[SONAR] Fichiers SONAR Field mis à jour sur ${mp} (MANIFEST/PROFILES*.tsv, Scripts/sonar_field.sh$([[ -s "${SONAR_FIELD_PINS_FILE}" ]] && echo ", MANIFEST/FIELD_PINS.tsv"))."
}

# sonar_generate_vault_helper DEST_DIR: writes a small standalone helper
# script (sonar-vault.sh) into DEST_DIR, which lands on the deployed USB.
# The script is run LATER, on whatever machine the technician is working
# on in the field — not at build time, not by SONAR itself, and it never
# touches Ventoy's persistence images. It uses gpg symmetric AES-256
# (near-universal) and prefers a real veracrypt container if the `veracrypt`
# CLI happens to be present on the machine where it's *run* — detected at
# use time, not baked in at build time, since that's a different machine
# with potentially different tooling than the one that built the USB.
sonar_generate_vault_helper() {
    local dest="$1"
    mkdir -p "${dest}"
    cat > "${dest}/sonar-vault.sh" <<'VAULT_EOF'
#!/bin/bash
# sonar-vault.sh — coffre chiffré autonome pour donnees sensibles de terrain.
#
# Independant du demarrage Ventoy et de la persistance : ce script chiffre/
# dechiffre des fichiers a la demande, sur la machine ou vous l'executez. Il
# ne stocke JAMAIS le mot de passe nulle part (ni sur disque, ni dans
# l'historique shell si vous le tapez a l'invite plutot qu'en argument).
#
# Usage:
#   ./sonar-vault.sh create <fichier_source> <coffre_sortie.enc>
#   ./sonar-vault.sh open   <coffre.enc> <fichier_sortie>
#
set -euo pipefail

usage() { echo "Usage: $0 create <source> <coffre.enc>  |  $0 open <coffre.enc> <sortie>" >&2; exit 2; }

backend="none"
if command -v veracrypt >/dev/null 2>&1; then
    echo "[vault] veracrypt detecte mais non pilote automatiquement par ce script (creation de conteneur VeraCrypt = operation manuelle plus lourde)." >&2
    echo "[vault] Utilisation de gpg (AES-256) a la place. Pour un vrai conteneur VeraCrypt, utilisez veracrypt directement." >&2
fi
if command -v gpg >/dev/null 2>&1; then
    backend="gpg"
else
    echo "[vault] ERREUR: gpg introuvable sur cette machine. Impossible de chiffrer/dechiffrer." >&2
    exit 1
fi

[[ $# -eq 3 ]] || usage
action="$1"; a="$2"; b="$3"

case "$action" in
    create)
        [[ -f "$a" ]] || { echo "[vault] Source introuvable: $a" >&2; exit 1; }
        [[ -e "$b" ]] && { echo "[vault] $b existe deja, refus d'ecraser." >&2; exit 1; }
        read -r -s -p "Mot de passe du coffre: " pw1; echo >&2
        read -r -s -p "Confirmer: " pw2; echo >&2
        [[ "$pw1" == "$pw2" ]] || { echo "[vault] Les mots de passe ne correspondent pas." >&2; exit 1; }
        printf '%s' "$pw1" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 -o "$b" "$a"
        unset pw1 pw2
        echo "[vault] Coffre cree: $b"
        ;;
    open)
        [[ -f "$a" ]] || { echo "[vault] Coffre introuvable: $a" >&2; exit 1; }
        [[ -e "$b" ]] && { echo "[vault] $b existe deja, refus d'ecraser." >&2; exit 1; }
        read -r -s -p "Mot de passe du coffre: " pw1; echo >&2
        printf '%s' "$pw1" | gpg --batch --yes --passphrase-fd 0 --decrypt -o "$b" "$a"
        unset pw1
        echo "[vault] Dechiffre vers: $b"
        ;;
    *) usage ;;
esac
VAULT_EOF
    chmod +x "${dest}/sonar-vault.sh"
    log_ok "Coffre chiffré autonome déployé: Scripts/sonar-vault.sh (gpg AES-256, jamais lié à la persistance/boot)."
}

# sonar_protect_catalog_final MOUNT_POINT: chiffre en place (gpg AES-256
# symétrique) le manifeste de curation déjà copié sur la clé
# (MANIFEST/MANIFEST.tsv -> MANIFEST/MANIFEST.tsv.gpg, plaintext supprimé).
# Opt-in (--protect-catalog), rôle VAULT requis — même famille de garde-fou
# que --field-pin-set/--fetch-manifest-seal. N'affecte jamais le boot ni
# sonar_field.sh (voir commentaire sur SONAR_PROTECT_CATALOG ci-dessus) :
# seule la table de curation devient illisible sans le mot de passe. Se
# déchiffre sur le terrain avec le helper déjà déployé (même format gpg) :
#   Scripts/sonar-vault.sh open MANIFEST/MANIFEST.tsv.gpg MANIFEST/MANIFEST.tsv
sonar_protect_catalog_final() {
    local mp="$1" plain out
    plain="${mp}/MANIFEST/MANIFEST.tsv"
    out="${plain}.gpg"
    [[ "${SONAR_PROTECT_CATALOG}" == "true" ]] || return 0
    sonar_require_role VAULT || { log "[PROTECT] Rôle insuffisant — catalogue laissé en clair."; return 1; }
    [[ -s "${plain}" ]] || { log "[PROTECT] Rien à protéger (MANIFEST.tsv absent ou vide)."; return 0; }
    command -v gpg >/dev/null 2>&1 || { log "[PROTECT] gpg introuvable — catalogue laissé en clair."; return 1; }
    [[ -n "${SONAR_PROTECT_PASSPHRASE:-}" ]] || { log "[PROTECT] SONAR_PROTECT_PASSPHRASE absente — catalogue laissé en clair."; return 1; }
    if printf '%s' "${SONAR_PROTECT_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 -o "${out}" "${plain}" 2>/dev/null; then
        rm -f "${plain}"
        sonar_audit "CATALOG_PROTECTED" "mount=${mp}"
        log_ok "Catalogue chiffré (gpg AES-256): MANIFEST/MANIFEST.tsv.gpg — plaintext retiré."
    else
        rm -f "${out}"
        log "[PROTECT] Échec du chiffrement gpg — catalogue laissé en clair."
        return 1
    fi
}

# sonar_export_field_files MOUNT_POINT: dépose sur la clé tout ce dont
# SONAR Field (second produit, sonar_field.sh — voir ROADMAP.md) a besoin
# pour fonctionner SANS sonar_master.sh présent sur la machine cible :
# les profils (mêmes données que --profile, exportées en TSV plutôt que
# dupliquées), et le script lui-même. Le(s) PIN de terrain (MANIFEST/
# FIELD_PINS.tsv), s'ils ont été définis via --field-pin-set <NIVEAU>
# <PIN> [PROFILS], sont copiés séparément par l'appelant — optionnel,
# non bloquant si absent.
sonar_export_field_files() {
    local mp="$1"
    mkdir -p "${mp}/MANIFEST" "${mp}/Scripts" "${mp}/Field-Logs"
    printf '%s\n' "${SONAR_PROFILES_TSV}" > "${mp}/MANIFEST/PROFILES.tsv"
    {
        printf 'PROFILE\tSCENARIO\n'
        local p
        for p in ${SONAR_PROFILE_NAMES}; do
            printf '%s\t%s\n' "$p" "$(sonar_profile_scenario "$p")"
        done
    } > "${mp}/MANIFEST/PROFILES_SCENARIOS.tsv"
    cat > "${mp}/Scripts/sonar_field.sh" <<'FIELD_SCRIPT_EOF'
#!/bin/bash
# sonar_field.sh — SONAR Field (second produit, distinct de sonar_master.sh
# qui a construit cette clé — voir ROADMAP.md, section "SONAR Field").
#
# Une fois la clé bootée sur la machine du client, ce script guide le
# technicien vers les bons outils pour le profil choisi et journalise ce
# qui a été consulté/tenté (même format de hashchain que sonar_master.sh)
# pour que l'intervention reste explicable après coup. Il ne répare RIEN
# automatiquement : c'est un guide + un journal, pas un orchestrateur qui
# exécute des commandes destructrices tout seul.
#
# Usage: sonar_field.sh [CHEMIN_PARTITION_CLE]
# Sans argument, cherche MANIFEST/PROFILES.tsv sous les points de montage
# courants — sinon montez la partition manuellement et passez son chemin.

set -uo pipefail

SONAR_FIELD_VERSION="0.1.0"

sonar_field_hash_str() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    else
        return 1
    fi
}

sonar_field_iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date; }

# sonar_field_audit EVENT [DETAILS] -> Field-Logs/{audit,hashchain}.log sur
# la clé, même format que sonar_master.sh (TS\tROLE\tEVENT\tDETAILS[\tHASH])
# pour qu'un cas (préparation + intervention) se relise comme une seule
# histoire, pas deux journaux à recouper à la main.
sonar_field_audit() {
    local event="$1" details="${2:-}"
    event="${event//$'\t'/ }"; event="${event//$'\n'/ }"
    details="${details//$'\t'/ }"; details="${details//$'\n'/ }"
    local ts role prev hash
    ts="$(sonar_field_iso_now)"
    role="Field:${SONAR_FIELD_IDENTITY:-non-identifie}"
    mkdir -p "${SONAR_FIELD_LOG_DIR}" 2>/dev/null || return 0
    printf '%s\t%s\t%s\t%s\n' "$ts" "$role" "$event" "$details" >> "${SONAR_FIELD_LOG_DIR}/audit.log" 2>/dev/null
    prev="$(tail -n 1 "${SONAR_FIELD_LOG_DIR}/hashchain.log" 2>/dev/null | awk -F '\t' '{print $NF}')"
    prev="${prev:-GENESIS}"
    hash="$(sonar_field_hash_str "${prev}|${ts}|${role}|${event}|${details}")" || hash="UNAVAILABLE"
    printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$role" "$event" "$details" "$hash" >> "${SONAR_FIELD_LOG_DIR}/hashchain.log" 2>/dev/null
}

# sonar_field_locate [CHEMIN]: trouve la partition de la clé (celle qui
# contient MANIFEST/PROFILES.tsv) — via l'argument, sinon en cherchant
# sous les points de montage usuels.
sonar_field_locate() {
    local cand
    if [[ -n "${1:-}" ]]; then
        cand="${1%/}"
        [[ -f "${cand}/MANIFEST/PROFILES.tsv" ]] && { echo "$cand"; return 0; }
        echo "[SONAR Field][ERREUR] ${cand}/MANIFEST/PROFILES.tsv introuvable." >&2
        return 1
    fi
    for cand in /mnt/* /media/*/* /run/media/*/*; do
        [[ -f "${cand}/MANIFEST/PROFILES.tsv" ]] && { echo "$cand"; return 0; }
    done
    return 1
}

# sonar_field_pin_gate KEY_PATH: si MANIFEST/FIELD_PINS.tsv existe (une
# ligne par niveau : NIVEAU\tSHA256(PIN)\tPROFILS), exige un PIN
# correspondant à l'une des lignes (3 essais au total) avant de
# continuer ; sinon avertit explicitement que l'accès n'est pas
# verrouillé plutôt que de le prétendre en silence. Le PIN saisi
# détermine à la fois l'identité (niveau) et les profils autorisés —
# pas de question séparée "quel niveau es-tu", un secret = une identité.
sonar_field_pin_gate() {
    local key="$1" pins_file="${1}/MANIFEST/FIELD_PINS.tsv"
    if [[ ! -s "$pins_file" ]]; then
        echo "[SONAR Field][ATTENTION] Aucun PIN configuré sur cette clé (--field-pin-set non utilisé au build) — accès libre, non identifié nominativement, tous profils visibles." >&2
        SONAR_FIELD_ALLOWED_PROFILES="ALL"
        SONAR_FIELD_NIVEAU="non identifié"
        return 0
    fi
    local attempt=1 pin hash line niveau expected profils
    while [[ $attempt -le 3 ]]; do
        read -r -s -p "PIN technicien : " pin; echo
        hash="$(sonar_field_hash_str "$pin")"
        line="$(awk -F'\t' -v h="$hash" '$2==h {print; exit}' "$pins_file")"
        if [[ -n "$line" ]]; then
            IFS=$'\t' read -r niveau expected profils <<< "$line"
            read -r -p "Identifiant (nom/matricule, pour le journal) : " SONAR_FIELD_IDENTITY
            SONAR_FIELD_IDENTITY="${SONAR_FIELD_IDENTITY:-technicien}(${niveau})"
            SONAR_FIELD_ALLOWED_PROFILES="$profils"
            SONAR_FIELD_NIVEAU="$niveau"
            echo "Accès accordé — niveau : ${niveau}  (profils autorisés : ${profils})"
            sonar_field_audit "FIELD_ACCESS_GRANTED" "niveau=${niveau};profils=${profils}"
            return 0
        fi
        echo "PIN incorrect (tentative ${attempt}/3)."
        attempt=$((attempt+1))
    done
    sonar_field_audit "FIELD_ACCESS_DENIED" "attempts=3"
    echo "[SONAR Field] Trop de tentatives — accès refusé." >&2
    return 1
}

sonar_field_profile_names() {
    awk -F'\t' 'NR>1 {print $1}' "${SONAR_FIELD_KEY}/MANIFEST/PROFILES_SCENARIOS.tsv"
}

sonar_field_scenario() {
    awk -F'\t' -v p="$1" 'NR>1 && $1==p {print $2; found=1} END{exit !found}' "${SONAR_FIELD_KEY}/MANIFEST/PROFILES_SCENARIOS.tsv"
}

sonar_field_tools() {
    awk -F'\t' -v p="$1" 'NR>1 && $1==p {print $2"\t"$3}' "${SONAR_FIELD_KEY}/MANIFEST/PROFILES.tsv"
}

# sonar_field_find_tool TOOL: cherche un fichier dont le nom contient TOOL
# (insensible a la casse) dans ISO/ et Portable/ (ou --fetch les depose) —
# indique juste OU il est, ne l'ouvre/n'execute jamais.
sonar_field_find_tool() {
    local tool="$1"
    find "${SONAR_FIELD_KEY}/ISO" "${SONAR_FIELD_KEY}/Portable" -iname "*${tool}*" 2>/dev/null
}

sonar_field_show_profile() {
    local profile="$1" scenario tools tool why found
    scenario="$(sonar_field_scenario "$profile")" || { echo "[SONAR Field] Profil inconnu."; return 1; }
    tools="$(sonar_field_tools "$profile")"
    echo
    echo "=== ${profile} ==="
    echo "Scenario : ${scenario}"
    echo
    echo "Outils :"
    while IFS=$'\t' read -r tool why; do
        [[ -z "$tool" ]] && continue
        echo "  - ${tool}"
        echo "      -> ${why}"
        found="$(sonar_field_find_tool "$tool" | head -n1)"
        if [[ -n "$found" ]]; then
            echo "      trouve sur la cle : ${found}"
        else
            echo "      PAS trouve sur la cle (--fetch ${profile} pas fait au build ?)"
        fi
    done <<< "$tools"
    if [[ "$profile" == "boot-repair" || "$profile" == "full" ]]; then
        echo
        local winpe_found
        winpe_found="$(find "${SONAR_FIELD_KEY}/ISO" -iname "*winpe*" 2>/dev/null | head -n1)"
        if [[ -n "$winpe_found" ]]; then
            echo "REPARATION WINDOWS (bootrec/bcdedit/DISM) : WinPE present sur cette cle -> ${winpe_found}"
        else
            echo "LIMITE CONNUE : reparation cote Windows (bootrec/bcdedit/DISM) non couverte — aucun WinPE sur cette cle. L'operateur peut en construire un avec tools/Build-SonarSE-WinPE.ps1 (voir docs/WINPE.md sur le depot source) et le deposer avant le prochain build."
        fi
    fi
    echo
    sonar_field_audit "FIELD_PROFILE_VIEWED" "profile=${profile}"
    local note
    read -r -p "Noter le resultat de cette intervention (une ligne, vide pour passer) : " note
    [[ -n "$note" ]] && sonar_field_audit "FIELD_INTERVENTION_NOTE" "profile=${profile};note=${note}"
}

sonar_field_menu() {
    local choice i p note
    while true; do
        echo
        echo "============================================================"
        echo " SONAR Field ${SONAR_FIELD_VERSION} — niveau : ${SONAR_FIELD_NIVEAU:-non identifié} — que dois-je depanner ?"
        echo "============================================================"
        i=1
        local -a names=()
        for p in $(sonar_field_profile_names); do
            if [[ "${SONAR_FIELD_ALLOWED_PROFILES:-ALL}" != "ALL" ]] && ! grep -qx "$p" <<< "$(tr ',' '\n' <<< "${SONAR_FIELD_ALLOWED_PROFILES}")"; then
                continue
            fi
            names+=("$p")
            printf '  %d) %-16s %s\n' "$i" "$p" "$(sonar_field_scenario "$p")"
            i=$((i+1))
        done
        [[ ${#names[@]} -eq 0 ]] && echo "  (aucun profil autorisé pour ce niveau)"
        [[ -f "${SONAR_FIELD_KEY}/Scripts/sonar_diag.sh" ]] && \
            echo "  d) DIAGNOSTIC INTELLIGENT — analyse la machine (lecture seule) et dit quoi faire"
        [[ -f "${SONAR_FIELD_KEY}/Scripts/client_report.awk" ]] && \
            echo "  c) RAPPORT CLIENT — PDF en langage simple, tire du dernier diagnostic"
        [[ -f "${SONAR_FIELD_KEY}/Scripts/sonar_bitlocker.sh" ]] && \
            echo "  b) BITLOCKER — ouvrir un volume chiffré en lecture seule (clé de récupération du propriétaire)"
        [[ -f "${SONAR_FIELD_KEY}/Scripts/sonar_recover.sh" ]] && \
            echo "  r) RÉCUPÉRATION DE DONNÉES — plan, image du disque, copie vérifiée (lecture seule)"
        echo "  q) Quitter"
        read -r -p "Choix : " choice
        [[ "$choice" == "q" ]] && break
        if [[ "$choice" == "d" && -f "${SONAR_FIELD_KEY}/Scripts/sonar_diag.sh" ]]; then
            sonar_field_audit "FIELD_DIAG_RUN" "outil=sonar_diag"
            bash "${SONAR_FIELD_KEY}/Scripts/sonar_diag.sh" --out "${SONAR_FIELD_LOG_DIR}/diag/DIAG_$(date +%Y%m%d-%H%M%S)" || true
        elif [[ "$choice" == "r" && -f "${SONAR_FIELD_KEY}/Scripts/sonar_recover.sh" ]]; then
            local _rdiag _rsrc _rdst _ract
            _rdiag="$(ls -d "${SONAR_FIELD_LOG_DIR}"/diag/DIAG_*/ 2>/dev/null | sort | tail -1)"
            bash "${SONAR_FIELD_KEY}/Scripts/sonar_recover.sh" plan ${_rdiag:+--diag "${_rdiag%/}"} || true
            read -r -p "Source (/dev/sdXN, image ou dossier monté en lecture seule ; Entrée = annuler) : " _rsrc
            if [[ -n "$_rsrc" ]]; then
                read -r -p "Destination (dossier sur un AUTRE disque que la source) : " _rdst
                read -r -p "Action : 1) image du disque (ddrescue)  2) copie des fichiers : " _ract
                if [[ -n "$_rdst" && ( "$_ract" == 1 || "$_ract" == 2 ) ]]; then
                    sonar_field_audit "FIELD_RECOVER" "action=${_ract};src=${_rsrc};dest=${_rdst}"
                    if [[ "$_ract" == 1 ]]; then
                        SONAR_AUDIT_FILE="${SONAR_FIELD_LOG_DIR}/recover.log" bash "${SONAR_FIELD_KEY}/Scripts/sonar_recover.sh" image --source "$_rsrc" --dest "$_rdst" || true
                    else
                        SONAR_AUDIT_FILE="${SONAR_FIELD_LOG_DIR}/recover.log" bash "${SONAR_FIELD_KEY}/Scripts/sonar_recover.sh" copy --source "$_rsrc" --dest "$_rdst" || true
                    fi
                else
                    echo "Annulé (destination ou action manquante)."
                fi
            fi
        elif [[ "$choice" == "b" && -f "${SONAR_FIELD_KEY}/Scripts/sonar_bitlocker.sh" ]]; then
            local _bd
            SONAR_AUDIT_FILE="${SONAR_FIELD_LOG_DIR}/bitlocker.log" bash "${SONAR_FIELD_KEY}/Scripts/sonar_bitlocker.sh" --list || true
            read -r -p "Périphérique à ouvrir (ex. /dev/sdb3, Entrée = annuler) : " _bd
            if [[ -n "$_bd" ]]; then
                sonar_field_audit "FIELD_BITLOCKER_UNLOCK" "dev=${_bd}"
                SONAR_AUDIT_FILE="${SONAR_FIELD_LOG_DIR}/bitlocker.log" bash "${SONAR_FIELD_KEY}/Scripts/sonar_bitlocker.sh" --unlock "$_bd" || true
            fi
        elif [[ "$choice" == "c" && -f "${SONAR_FIELD_KEY}/Scripts/client_report.awk" ]]; then
            local _cdir _cname
            _cdir="$(ls -d "${SONAR_FIELD_LOG_DIR}"/diag/DIAG_*/ 2>/dev/null | sort | tail -1)"
            if [[ -z "$_cdir" ]]; then
                echo "Aucun diagnostic sur la cle : lancez d'abord l'option d."
            else
                read -r -p "Nom du client (Entree = sans nom) : " _cname
                sonar_field_audit "FIELD_CLIENT_REPORT" "source=$(basename "$_cdir")"
                bash "${SONAR_FIELD_KEY}/Scripts/sonar_diag.sh" --client-report "${_cdir%/}" --client-name "$_cname" || true
            fi
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#names[@]} )); then
            sonar_field_show_profile "${names[$((choice-1))]}"
        else
            echo "Choix invalide."
        fi
    done
}

main() {
    SONAR_FIELD_KEY="$(sonar_field_locate "${1:-}")" || {
        echo "[SONAR Field][ERREUR] Partition de la cle SONAR introuvable (MANIFEST/PROFILES.tsv absent des points de montage courants)." >&2
        echo "Montez-la manuellement puis relancez : $0 /chemin/vers/la/cle" >&2
        exit 1
    }
    SONAR_FIELD_LOG_DIR="${SONAR_FIELD_KEY}/Field-Logs"
    mkdir -p "${SONAR_FIELD_LOG_DIR}" 2>/dev/null || {
        echo "[SONAR Field][ERREUR] Impossible d'ecrire sur ${SONAR_FIELD_KEY} (montee en lecture seule ?)." >&2
        exit 1
    }
    sonar_field_pin_gate "${SONAR_FIELD_KEY}" || exit 1
    sonar_field_menu
    echo "Journal de cette session : ${SONAR_FIELD_LOG_DIR}/audit.log"
}

main "$@"
FIELD_SCRIPT_EOF
    chmod +x "${mp}/Scripts/sonar_field.sh" 2>/dev/null || true
    # Diagnostic intelligent (tools/sonar_diag.sh + sa base de regles) : meme
    # logique que le reste de SONAR Field — fichiers copies tels quels depuis
    # le depot (pas de heredoc dupliquee, donc pas de derive possible entre
    # ce qui est teste et ce qui est deploye).
    local d="${SONAR_SCRIPT_DIR}/tools"
    if [[ -f "${d}/sonar_diag.sh" && -f "${d}/diag_rules.txt" && -f "${d}/diag_engine.awk" ]]; then
        cp -f "${d}/sonar_diag.sh" "${mp}/Scripts/sonar_diag.sh"
        cp -f "${d}/diag_rules.txt" "${mp}/MANIFEST/DIAG_RULES.txt"
        cp -f "${d}/diag_engine.awk" "${mp}/Scripts/diag_engine.awk"
        chmod +x "${mp}/Scripts/sonar_diag.sh" 2>/dev/null || true
    else
        log "[SONAR] tools/sonar_diag.sh, diag_rules.txt ou diag_engine.awk absent : diagnostic intelligent NON deploye sur la cle."
    fi
    # Rapport client (--client-report) : phrases pretes + mise en page PDF.
    if [[ -f "${d}/client_templates.txt" && -f "${d}/client_report.awk" && -f "${d}/text2pdf.awk" ]]; then
        cp -f "${d}/client_templates.txt" "${mp}/MANIFEST/CLIENT_TEMPLATES.txt"
        cp -f "${d}/client_report.awk" "${mp}/Scripts/client_report.awk"
        cp -f "${d}/text2pdf.awk" "${mp}/Scripts/text2pdf.awk"
    else
        log "[SONAR] tools/client_templates.txt, client_report.awk ou text2pdf.awk absent : rapport client NON deploye sur la cle."
    fi
    # Deverrouillage BitLocker cote Linux (lecture seule, cle de recuperation du proprietaire).
    if [[ -f "${d}/sonar_bitlocker.sh" ]]; then
        cp -f "${d}/sonar_bitlocker.sh" "${mp}/Scripts/sonar_bitlocker.sh"
        chmod +x "${mp}/Scripts/sonar_bitlocker.sh" 2>/dev/null || true
    else
        log "[SONAR] tools/sonar_bitlocker.sh absent : deverrouillage BitLocker NON deploye sur la cle."
    fi
    # Recuperation de donnees (garde INDEPENDANTE de celle de BitLocker).
    if [[ -f "${d}/sonar_recover.sh" ]]; then
        cp -f "${d}/sonar_recover.sh" "${mp}/Scripts/sonar_recover.sh"
        chmod +x "${mp}/Scripts/sonar_recover.sh" 2>/dev/null || true
    else
        log "[SONAR] tools/sonar_recover.sh absent : recuperation de donnees NON deployee sur la cle."
    fi
}

generate_tool_index_final() {
    local mp="$1"
    {
        printf 'FOLDER\tFILE\n'
        find "${mp}/ISO" "${mp}/Portable" "${mp}/AI-Downloads" -mindepth 1 -maxdepth 1 2>/dev/null \
            | while IFS= read -r p; do printf '%s\t%s\n' "$(basename "$(dirname "$p")")" "$(basename "$p")"; done
    } > "${mp}/Docs/INDEX.tsv" 2>/dev/null || true
    cat > "${mp}/Scripts/find-tool.sh" <<'FINDTOOL'
#!/bin/bash
# Recherche un outil sur cette clé SONAR, quel que soit l'environnement de boot
# (Linux Live/Rescue). Usage: ./find-tool.sh <mot-clé, ex: antivirus, clamav, gparted>
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kw="${1:-}"
[[ -n "$kw" ]] || { echo "Usage: $0 <mot-clé>"; exit 1; }
echo "=== Fichiers correspondants (ISO/Portable/AI-Downloads) ==="
find "${here}/ISO" "${here}/Portable" "${here}/AI-Downloads" -iname "*${kw}*" 2>/dev/null
echo
echo "=== Entrées catalogue correspondantes (nom/domaine) ==="
grep -i "$kw" "${here}/AI-Downloads/MANIFEST_AI_RESULTS.tsv" 2>/dev/null
FINDTOOL
    chmod +x "${mp}/Scripts/find-tool.sh"
    cat > "${mp}/Scripts/Find-Tool.ps1" <<'FINDTOOLPS1'
# Recherche un outil sur cette clé SONAR depuis un environnement Windows/WinPE.
# Usage: .\Find-Tool.ps1 -Keyword antivirus
param([Parameter(Mandatory=$true)][string]$Keyword)
$Root = Split-Path -Parent $PSScriptRoot
Write-Host "=== Fichiers correspondants (ISO/Portable/AI-Downloads) ==="
Get-ChildItem -Path "$Root\ISO","$Root\Portable","$Root\AI-Downloads" -Recurse -Filter "*$Keyword*" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName
Write-Host ""
Write-Host "=== Entrées catalogue correspondantes (nom/domaine) ==="
$manifest = Join-Path $Root "AI-Downloads\MANIFEST_AI_RESULTS.tsv"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern $Keyword }
FINDTOOLPS1
}

generate_macos_support_final() {
    [[ "${DRY_RUN}" == "true" ]] && return
    local mp
    mp="$(mount_ventoy_final)"
    mkdir -p "${mp}/macOS"
    cat > "${mp}/macOS/create_macos_installer_on_mac.sh" <<'MAC'
#!/bin/bash
set -euo pipefail
echo "SONAR — création officielle d'un installateur macOS"
APP="$(ls -dt /Applications/Install\ macOS\ *.app 2>/dev/null | head -n1 || true)"
[[ -n "$APP" ]] || { echo "Aucun Install macOS *.app dans /Applications."; exit 1; }
CMD="$APP/Contents/Resources/createinstallmedia"
[[ -x "$CMD" ]] || { echo "createinstallmedia introuvable."; exit 1; }
read -r -p "Nom du volume USB à EFFACER (ex: MyVolume): " VOL
[[ -n "$VOL" ]] || exit 1
echo "Installateur: $APP"
echo "Volume: /Volumes/$VOL"
read -r -p "Tapez OUI pour effacer et créer l'installateur: " OK
[[ "$OK" == "OUI" ]] || exit 1
if [[ "$(id -u)" -eq 0 ]]; then
    "$CMD" --volume "/Volumes/$VOL"
else
    sudo "$CMD" --volume "/Volumes/$VOL"
fi
echo "Installateur macOS créé."
MAC
    chmod +x "${mp}/macOS/create_macos_installer_on_mac.sh"
    cat > "${mp}/macOS/README_MACOS.txt" <<'EOF'
SONAR — MACOS

Le script create_macos_installer_on_mac.sh doit être exécuté sur un Mac
compatible avec l'installateur macOS présent dans /Applications.

Mac Apple Silicon:
  maintenir le bouton d'alimentation pour afficher les options de démarrage.

Mac Intel:
  maintenir Option/Alt au démarrage.

Mac T2:
  vérifier Startup Security Utility si le support externe est refusé.

SONAR ne prétend pas fabriquer un ISO macOS depuis Linux. La création
officielle de l'installateur utilise createinstallmedia fourni par Apple.
EOF
    unmount_final "${mp}"
}

generate_manifests_final() {
    [[ "${DRY_RUN}" == "true" ]] && return
    local mp
    mp="$(mount_ventoy_final)"
    # cd "$mp" avant find : sha256sum ecrit alors des chemins RELATIFS au
    # point de montage (ex. "ISO/foo.iso") plutot que des chemins absolus
    # ancres sur ce point de montage temporaire precis (mount_ventoy_final
    # utilise un mktemp -d different a chaque appel). sonar_post_deploy_
    # verify_final n'a alors plus besoin de reecrire ces chemins par regex
    # avant de relancer sha256sum -c depuis un nouveau point de montage —
    # supprime une classe de bug entiere plutot que de la rendre plus
    # precise (regex gloutonne sur des noms de dossiers qui pourraient, en
    # theorie, se repeter plus profond dans un chemin).
    : > "${mp}/MANIFEST/ISO.sha256"
    ( cd "${mp}" && while IFS= read -r -d '' f; do sha256sum "$f" >> "${mp}/MANIFEST/ISO.sha256"; done \
        < <(find ISO -type f -iname '*.iso' -print0 | sort -z) )
    : > "${mp}/MANIFEST/FILES.sha256"
    ( cd "${mp}" && while IFS= read -r -d '' f; do sha256sum "$f" >> "${mp}/MANIFEST/FILES.sha256"; done \
        < <(find Portable Scripts Drivers macOS -type f -print0 2>/dev/null | sort -z) )
    unmount_final "${mp}"
}

# sonar_post_deploy_verify_final: re-reads every hashed file straight off the
# mounted USB device and checks it against the manifests generate_manifests_final
# just wrote. validate_final (further below) only checks that directories/files
# EXIST — it never re-hashes content, so a corrupted write (bad sector, USB
# controller error, premature unplug) could pass structural validation while
# the actual bytes on the stick are wrong. This closes that gap immediately,
# while the disk is still mounted, instead of relying on the operator to run
# --verify-manifest manually afterwards.
sonar_post_deploy_verify_final() {
    [[ "${DRY_RUN}" == "true" ]] && { log "[DRY-RUN] Vérification post-déploiement simulée."; return; }
    local mp checked=0 failed=0 mf n
    mp="$(mount_ventoy_final)"
    for mf in "${mp}/MANIFEST/ISO.sha256" "${mp}/MANIFEST/FILES.sha256"; do
        [[ -s "$mf" ]] || continue
        n="$(wc -l < "$mf" | tr -d ' ')"
        checked=$((checked + n))
        # generate_manifests_final ecrit desormais des chemins deja relatifs
        # au point de montage (cd avant find) — plus besoin de les reecrire
        # ici par regex avant de relancer sha256sum -c depuis le nouveau
        # point de montage de cette verification. Ancienne regex gloutonne
        # (s#...#) ecartee 2026-09-17 : fragile si un nom de dossier ancre
        # (ex. "ISO/") pouvait en theorie se repeter plus profond dans un
        # chemin — corrige a la source plutot que rendu plus precis.
        if ! ( cd "$mp" && sha256sum -c --quiet "$mf" ) 2>>"${LOG_FILE:-/dev/null}"; then
            failed=$((failed+1))
            log_err "Vérification post-déploiement échouée: $(basename "$mf")"
        fi
    done
    unmount_final "${mp}"
    if (( failed > 0 )); then
        sonar_audit "POST_DEPLOY_VERIFY" "status=FAILED;checked=${checked};failed_manifests=${failed}"
        error_exit "Vérification post-déploiement: ${failed} manifeste(s) en échec sur ${checked} fichier(s) attendus — clé potentiellement corrompue."
    fi
    sonar_audit "POST_DEPLOY_VERIFY" "status=OK;checked=${checked}"
    log_ok "Vérification post-déploiement OK (${checked} fichier(s) relu(s) et confirmé(s) sur la clé)."
}

generate_readme_final() {
    [[ "${GENERATE_README}" == "true" && "${DRY_RUN}" != "true" ]] || return 0
    local mp
    mp="$(mount_ventoy_final)"
    cat > "${mp}/README.md" <<EOF
# ${DISK_LABEL} — SONAR

Multiboot et maintenance informatique Windows + Linux + macOS.

## Dossiers
ISO/ | Portable/ | Scripts/ | Drivers/ | macOS/ | AI-Downloads/ | persistence/ |
ventoy/ | MANIFEST/ | Logs/ | Docs/

- **ISO/** : images bootables (démarrage direct depuis le menu Ventoy — ex. Linux Rescue, WinPE).
- **Portable/** : exécutables/archives à lancer *depuis un OS déjà démarré* (Windows PE,
  session Windows de secours, ou Linux live monté).
- **AI-Downloads/** : outils résolus et vérifiés (SHA-256) via \`--ai-download\`, séparés des
  outils choisis manuellement. Indexés dans \`AI-Downloads/MANIFEST_AI_RESULTS.tsv\`
  (colonnes: ID, NAME, VERSION, OS, ARCH, URL, SHA256, SOURCE).
- **Scripts/** : utilitaires, dont \`find-tool.sh\` (Linux) et \`Find-Tool.ps1\` (Windows).

## Retrouver un outil une fois démarré, selon l'environnement
1. **Menu Ventoy (choix de boot)** : chaque fichier \`.iso\` de \`ISO/\` apparaît directement
   comme une entrée démarrable — c'est le point d'entrée pour un Linux Rescue/live
   totalement hors du système de la machine à traiter.
2. **Depuis un Linux live démarré** : ouvrir un terminal, puis
   \`bash /chemin/vers/la/clé/Scripts/find-tool.sh <mot-clé>\` (ex: \`antivirus\`, \`clamav\`,
   \`gparted\`) — cherche à la fois les fichiers présents et les entrées du manifeste IA.
3. **Depuis WinPE / une session Windows de secours** : PowerShell, puis
   \`.\Scripts\Find-Tool.ps1 -Keyword <mot-clé>\`.
4. **Recherche manuelle rapide** : \`Docs/INDEX.tsv\` liste tout le contenu de
   \`ISO/\`, \`Portable/\` et \`AI-Downloads/\` en une seule table (colonnes FOLDER/FILE).
5. **Pour du forensic/nettoyage** : le disque interne de la machine à traiter n'est
   *jamais* démarré — on boote uniquement sur cette clé, on monte le disque interne en
   lecture (et écriture si nécessaire) depuis l'environnement externe, et on agit dessus
   avec les outils ci-dessus. Voir la catégorie « Sécurité des postes » /
   « Forensic disque » du catalogue pour les outils pertinents (antivirus offline,
   récupération de données, imagerie disque).

## Validation
Présence et SHA-256 ne prouvent pas le boot matériel.
Tester UEFI, Secure Boot, Windows/WinPE/WinRE, Linux Live/Rescue et
macOS sur du matériel réel.

## macOS
La création d'un installateur officiel est réalisée depuis un Mac avec
createinstallmedia. Le support Apple Silicon et Intel est distinct.

## IA
SONAR inclut une couche d'intelligence offline-first : inventaire, diagnostic,
recommandations et assistant LLM local optionnel. L'IA ne peut pas déclencher
seule une opération destructive. Voir AI/ et Docs/AI/.
EOF
    unmount_final "${mp}"
}

validate_final() {
    [[ "${DRY_RUN}" == "true" ]] && { log "[DRY-RUN] Validation simulée."; return; }
    local mp errors=0 d
    mp="$(mount_ventoy_final)"
    for d in ISO Portable Scripts Drivers macOS persistence ventoy MANIFEST AI-Downloads; do
        [[ -d "${mp}/${d}" ]] || { log_warn "Dossier absent: ${d}"; ((errors++)) || true; }
    done
    if [[ "${AI_ENABLE_ASSISTANT}" == "true" ]]; then
        [[ -d "${mp}/AI" ]] || { log_warn "Dossier absent: AI"; ((errors++)) || true; }
    fi
    [[ -f "${mp}/ventoy/ventoy.json" ]] || { log_warn "ventoy.json absent"; ((errors++)) || true; }
    if [[ "${GENERATE_README}" == "true" ]]; then
        [[ -f "${mp}/README.md" ]] || { log_warn "README absent"; ((errors++)) || true; }
    fi
    log "ISO: $(find "${mp}/ISO" -type f -iname '*.iso' | wc -l)"
    log "Portable: $(find "${mp}/Portable" -mindepth 1 -maxdepth 1 -type d | wc -l)"
    log "Scripts: $(find "${mp}/Scripts" -type f | wc -l)"
    log "macOS resources: $(find "${mp}/macOS" -type f | wc -l)"
    log "IA: $(find "${mp}/AI" -type f 2>/dev/null | wc -l) fichiers"
    log "AI-Downloads: $(find "${mp}/AI-Downloads" -type f 2>/dev/null | wc -l) fichiers"
    unmount_final "${mp}"
    (( errors == 0 )) || error_exit "Validation structurelle échouée."
    log_ok "Validation structurelle OK."
}

deploy_single_disk_final() {
    local disk_index="$1"
    log "=============================================================="
    log " SONAR FINAL — DISQUE ${disk_index}/${BATCH_COUNT}"
    log "=============================================================="
    preflight_final
    sonar_require_role DEPLOY || error_exit "Rôle '${SONAR_ROLE}' insuffisant pour le déploiement."
    prepare_workspace
    download_ventoy_final
    install_ventoy_final
    copy_payload_final
    create_persistence_final
    generate_macos_support_final
    # Couche IA : inventaire, diagnostic, recommandations et LLM local optionnel
    if [[ "${DRY_RUN}" == "true" ]]; then
        run_ai_final ""
    else
        local local_ai_mp
        local_ai_mp="$(mount_ventoy_final)"
        # Detect before installing: install_ai_layer_final writes AI_PROVIDER
        # into AI_CONFIG.tsv, so it needs the real value, not just a
        # placeholder default — ai_detect_provider() is a pure probe (no
        # side effects beyond setting the variable), safe to call again
        # inside run_ai_final() right after.
        ai_detect_provider
        install_ai_layer_final "${local_ai_mp}"
        run_ai_final "${local_ai_mp}"
        unmount_final "${local_ai_mp}"
    fi
    generate_manifests_final
    sonar_post_deploy_verify_final
    generate_readme_final
    validate_final
    log "Résumé: ${WARN_COUNT} avertissement(s), ${COPY_ERRORS} erreur(s) de copie."
    (( COPY_ERRORS == 0 )) || error_exit "${COPY_ERRORS} erreur(s) de copie détectée(s) — disque ${DISK} incomplet."
    log_ok "Déploiement terminé pour ${DISK}."
}


sonar_cli() {
    case "${SONAR_COMMAND}" in
        security-status)
            sonar_security_status
            ;;
        hardware-inventory)
            sonar_require_role AUDIT || error_exit "Rôle '${SONAR_ROLE}' insuffisant pour AUDIT."
            sonar_collect_hardware
            cat "${SONAR_AI_DIR}/Hardware/inventory.tsv"
            ;;
        build-manifest)
            sonar_build_manifest "${MANIFEST_TARGET}" || error_exit "Échec de la génération du manifeste (répertoire absent ou outil de hachage indisponible)."
            echo "[SONAR] Manifest: ${SONAR_MANIFEST}"
            ;;
        verify-manifest)
            sonar_verify_manifest || error_exit "Manifeste absent, vide, ou vérification échouée: ${SONAR_MANIFEST}"
            ;;
        deploy)
            log "SONAR - SE — moteur unique"
            [[ "${DRY_RUN}" == "true" ]] && log "MODE DRY-RUN."
            for ((i=1;i<=BATCH_COUNT;i++)); do
                deploy_single_disk_final "$i"
                if (( i < BATCH_COUNT )); then
                    read -r -p "Insérez le disque suivant puis Entrée..."
                fi
            done
            log "SONAR - SE — TERMINÉ"
            ;;
        *)
            error_exit "Commande Sonar inconnue: ${SONAR_COMMAND}"
            ;;
    esac
}

main_final() {
    parse_final_args "$@"
    sonar_cli
}



# sonar_downloader_ai.sh
# Ollama-assisted discovery; Sonar remains the deterministic verifier.

SONAR_ROOT="${SONAR_ROOT}"
SONAR_SOURCE="${SONAR_SOURCE:-${SONAR_ROOT}/SONAR_SOURCE}"
SONAR_DOWNLOAD_DIR="${SONAR_DOWNLOAD_DIR:-${SONAR_SOURCE}/Downloads}"
SONAR_QUEUE="${SONAR_QUEUE:-${SONAR_SOURCE}/MANIFEST_AI_QUEUE.tsv}"
SONAR_RESULTS="${SONAR_RESULTS:-${SONAR_SOURCE}/MANIFEST_AI_RESULTS.tsv}"
SONAR_REJECTED="${SONAR_REJECTED:-${SONAR_SOURCE}/MANIFEST_AI_REJECTED.tsv}"
SONAR_AI_LOG="${SONAR_AI_LOG:-${SONAR_ROOT}/AI/Logs/downloader_ai.log}"
SONAR_AI_URL="${SONAR_AI_URL:-http://127.0.0.1:11434/api/generate}"
SONAR_AI_MODEL="${SONAR_AI_MODEL:-llama3.2}"
SONAR_MAX_RETRIES="${SONAR_MAX_RETRIES:-3}"
SONAR_TIMEOUT="${SONAR_TIMEOUT:-120}"
SONAR_DRY_RUN="${SONAR_DRY_RUN:-0}"
SONAR_ALLOW_NONOFFICIAL="${SONAR_ALLOW_NONOFFICIAL:-0}"

sonar_dl_log() {
    mkdir -p "$(dirname "$SONAR_AI_LOG")" 2>/dev/null || true
    printf '%s\t%s\n' "$(sonar_iso_now)" "$*" | tee -a "$SONAR_AI_LOG"
}
die() { sonar_dl_log "ERROR $*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Commande manquante: $1"; }

usage() {
cat <<'EOF'
Sonar AI Downloader
  --queue FILE
  --source DIR
  --model MODEL
  --ai-url URL
  --dry-run
  --retry N
  --timeout SEC
  --allow-nonofficial
EOF
}

url_host() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse
print((urlparse(sys.argv[1]).hostname or "").lower())
PY
}

ollama_available() {
    curl -fsS --max-time 5 "${SONAR_AI_URL%/api/generate}/api/tags" >/dev/null 2>&1
}

ollama_query() {
    # prompt passe par stdin, pas en argv (meme correctif que ai_query_local,
    # 2026-09-17) : url/model/timeout restent en argv (non sensibles), seul
    # le prompt (visible sinon via /proc/<pid>/cmdline pendant l'execution)
    # transite par stdin.
    printf '%s' "$1" | python3 - "$SONAR_AI_URL" "$SONAR_AI_MODEL" "$SONAR_TIMEOUT" <<'PY'
import json, sys, urllib.request
url, model, timeout = sys.argv[1], sys.argv[2], int(sys.argv[3])
prompt = sys.stdin.read()
payload=json.dumps({"model":model,"prompt":prompt,"stream":False,"format":"json"}).encode()
req=urllib.request.Request(url,data=payload,headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req,timeout=timeout) as r:
    print(json.load(r).get("response",""))
PY
}

extract_json() {
    python3 -c '
import json, sys
s = sys.stdin.read().strip()
# Try direct parse first
try:
    print(json.dumps(json.loads(s), ensure_ascii=False))
    raise SystemExit
except Exception:
    pass
# Brace-counting extraction: find the first balanced JSON object
depth = 0
start = -1
for i, c in enumerate(s):
    if c == "{":
        if depth == 0:
            start = i
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0 and start >= 0:
            try:
                obj = json.loads(s[start:i+1])
                print(json.dumps(obj, ensure_ascii=False))
                raise SystemExit
            except Exception:
                start = -1
            continue
raise SystemExit(1)
'
}

download_file() {
    local url="$1" out="$2"
    [[ "$SONAR_DRY_RUN" == "1" ]] && { sonar_dl_log "DRY-RUN $url -> $out"; return 0; }
    local -a curl_opts=(-fL --retry "$SONAR_MAX_RETRIES" --connect-timeout 20 --proto '=https' --tlsv1.2)
    [[ -n "${SONAR_CA_CERT:-}" ]] && curl_opts+=(--cacert "${SONAR_CA_CERT}")
    if ! curl "${curl_opts[@]}" -o "$out.part" "$url"; then
        rm -f "$out.part" 2>/dev/null || true
        return 1
    fi
    mv -f "$out.part" "$out"
}

valid_sha256() { [[ "$1" =~ ^[A-Fa-f0-9]{64}$ ]]; }

discover_one() {
    local id="$1" name="$2" os="$3" arch="$4" version="$5" official="$6"
    local prompt response json url sha confidence source host safe out actual

    prompt="Tu es le module de recherche de Sonar. Trouve les informations de téléchargement pour UN logiciel. N'invente aucune URL ni aucun SHA-256.
Nom: $name
ID: $id
OS: $os
Architecture: $arch
Version: $version
Site officiel attendu: $official

Retourne UNIQUEMENT JSON:
{\"name\":\"\",\"version\":\"\",\"os\":\"\",\"arch\":\"\",\"official_site\":\"\",\"download_url\":\"\",\"sha256\":\"\",\"sha256_source_url\":\"\",\"source_type\":\"official|vendor|unknown\",\"confidence\":\"high|medium|low\"}
Le SHA-256 doit correspondre exactement au fichier de l'URL. Si non vérifiable, laisse la valeur vide."

    response="$(ollama_query "$prompt")" || { sonar_dl_log "REJECT $id Ollama"; return 1; }
    json="$(printf '%s' "$response" | extract_json)" || { sonar_dl_log "REJECT $id JSON"; return 1; }

    url="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("download_url",""))' <<<"$json")"
    sha="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("sha256",""))' <<<"$json")"
    source="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("source_type","unknown"))' <<<"$json")"
    confidence="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("confidence","low"))' <<<"$json")"

    if [[ -z "$url" || -z "$sha" ]] || ! [[ "$url" =~ ^https:// ]] || ! valid_sha256 "$sha"; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "DISCOVERY_NOT_VERIFIED" "$url" "$sha" "$confidence" >> "$SONAR_REJECTED"
        return 2
    fi

    host="$(url_host "$url")"
    if [[ -n "$official" && "$official" != "AUTO" && "$host" != "$official" && "$host" != *".${official}" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "DOMAIN_MISMATCH" "$url" "$sha" "$confidence" >> "$SONAR_REJECTED"
        return 2
    fi
    if [[ -z "$official" || "$official" == "AUTO" ]] && [[ "$SONAR_ALLOW_NONOFFICIAL" != "1" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "NO_OFFICIAL_DOMAIN_POLICY" "$url" "$sha" "$confidence" >> "$SONAR_REJECTED"
        return 2
    fi

    safe="$(printf '%s-%s-%s-%s' "$id" "$os" "$arch" "$version" | tr -cs 'A-Za-z0-9._+-' '_' | cut -c1-180)"
    out="${SONAR_DOWNLOAD_DIR}/${safe}"

    if [[ "$SONAR_DRY_RUN" != "1" ]]; then
        download_file "$url" "$out" || {
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "DOWNLOAD_FAILED" "$url" "$sha" "$confidence" >> "$SONAR_REJECTED"
            return 3
        }
        actual="$(sonar_hash "$out")"
        if [[ "${actual,,}" != "${sha,,}" ]]; then
            rm -f "$out"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "SHA256_MISMATCH" "$url" "$sha" "$confidence" >> "$SONAR_REJECTED"
            return 4
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$version" "$os" "$arch" "$url" "$sha" "$source" >> "$SONAR_RESULTS"
    sonar_dl_log "VERIFIED $id $name $os/$arch"
}

sonar_ai_downloader_main() {
    local queue="$SONAR_QUEUE"
    while (($#)); do
        case "$1" in
            --queue) [[ $# -ge 2 ]] || die "--queue nécessite une valeur."; queue="$2"; shift 2 ;;
            --source) [[ $# -ge 2 ]] || die "--source nécessite une valeur."; SONAR_SOURCE="$2"; SONAR_DOWNLOAD_DIR="${SONAR_SOURCE}/Downloads"; SONAR_QUEUE="${SONAR_SOURCE}/MANIFEST_AI_QUEUE.tsv"; SONAR_RESULTS="${SONAR_SOURCE}/MANIFEST_AI_RESULTS.tsv"; SONAR_REJECTED="${SONAR_SOURCE}/MANIFEST_AI_REJECTED.tsv"; SONAR_AI_LOG="${SONAR_ROOT}/AI/Logs/downloader_ai.log"; shift 2 ;;
            --model) [[ $# -ge 2 ]] || die "--model nécessite une valeur."; SONAR_AI_MODEL="$2"; shift 2 ;;
            --ai-url) [[ $# -ge 2 ]] || die "--ai-url nécessite une valeur."; SONAR_AI_URL="$2"; shift 2 ;;
            --dry-run) SONAR_DRY_RUN=1; shift ;;
            --retry) [[ $# -ge 2 ]] || die "--retry nécessite une valeur."; SONAR_MAX_RETRIES="$2"; shift 2 ;;
            --timeout) [[ $# -ge 2 ]] || die "--timeout nécessite une valeur."; SONAR_TIMEOUT="$2"; shift 2 ;;
            --allow-nonofficial) SONAR_ALLOW_NONOFFICIAL=1; shift ;;
            --ca-certificate) [[ $# -ge 2 ]] || die "--ca-certificate nécessite une valeur."; SONAR_CA_CERT="$2"; [[ -f "${SONAR_CA_CERT}" ]] || die "Certificat CA introuvable: ${SONAR_CA_CERT}"; shift 2 ;;
            --help|-h) usage; return 0 ;;
            *) die "Option inconnue: $1" ;;
        esac
    done

    need_cmd curl
    need_cmd python3
    [[ -f "$queue" ]] || die "Queue introuvable: $queue"
    ollama_available || die "Ollama indisponible: http://127.0.0.1:11434"
    mkdir -p "$SONAR_DOWNLOAD_DIR"

    printf 'ID\tNAME\tVERSION\tOS\tARCH\tURL\tSHA256\tSOURCE\n' > "$SONAR_RESULTS"
    printf 'ID\tNAME\tSTATUS\tURL\tSHA256\tCONFIDENCE\n' > "$SONAR_REJECTED"

    while IFS=$'\t' read -r id name os arch version official; do
        [[ -z "$id" || "$id" == \#* || "$id" == "ID" ]] && continue
        discover_one "$id" "$name" "$os" "$arch" "$version" "$official" || true
    done < "$queue"
    sonar_dl_log "DONE"
}

# === SONAR EMBEDDED CATALOGUE V1 ===
# Source: user-provided "Fichier markdown.md collé"
# Purpose: seed the AI downloader; AUTO fields are deliberately resolved by AI
# and then checked by Sonar. The source itself does not specify OS/architecture
# for every entry, so Sonar must not invent them.
SONAR_CATALOGUE_EMBEDDED="${SONAR_CATALOGUE_EMBEDDED:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/catalogue.tsv}"

sonar_install_embedded_catalogue() {
    if [[ -s "$SONAR_CATALOGUE_EMBEDDED" ]]; then
        echo "[SONAR] Catalogue existant conservé (non écrasé): $SONAR_CATALOGUE_EMBEDDED"
        return 0
    fi
    mkdir -p "$(dirname "$SONAR_CATALOGUE_EMBEDDED")"
    cat > "$SONAR_CATALOGUE_EMBEDDED" <<'SONAR_CATALOGUE_EOF'
DOMAIN	SUBDOMAIN	NAME
	Systèmes d'exploitation & virtualisation	DomaineLogiciels
	Systèmes d'exploitation & virtualisation	Windows
	Systèmes d'exploitation & virtualisation	Windows 10/11, Windows Server, Windows PE, WinRE
	Systèmes d'exploitation & virtualisation	Linux
	Systèmes d'exploitation & virtualisation	Ubuntu, Debian, Fedora, Arch, Linux Mint, Rocky Linux, AlmaLinux, RHEL, Kali, openSUSE
	Systèmes d'exploitation & virtualisation	macOS
	Systèmes d'exploitation & virtualisation	macOS, RecoveryOS
	Systèmes d'exploitation & virtualisation	Virtualisation
	Systèmes d'exploitation & virtualisation	VMware Workstation/Fusion, VirtualBox, Hyper-V, QEMU/KVM, Parallels Desktop
	Systèmes d'exploitation & virtualisation	Conteneurs
	Systèmes d'exploitation & virtualisation	Docker, Podman, containerd
	Systèmes d'exploitation & virtualisation	Orchestration
	Systèmes d'exploitation & virtualisation	Kubernetes, K3s, Minikube, Helm
2. Administration système	Windows 🪟	PowerShell
2. Administration système	Windows 🪟	Windows Terminal
2. Administration système	Windows 🪟	RSAT
2. Administration système	Windows 🪟	Active Directory
2. Administration système	Windows 🪟	Group Policy
2. Administration système	Windows 🪟	Server Manager
2. Administration système	Windows 🪟	Sysinternals Suite
2. Administration système	Windows 🪟	DISM
2. Administration système	Windows 🪟	SFC
2. Administration système	Windows 🪟	WMI/CIM
2. Administration système	Windows 🪟	Windows Admin Center
2. Administration système	Linux 🐧	Bash
2. Administration système	Linux 🐧	Zsh
2. Administration système	Linux 🐧	systemd
2. Administration système	Linux 🐧	SSH/OpenSSH
2. Administration système	Linux 🐧	sudo
2. Administration système	Linux 🐧	cron
2. Administration système	Linux 🐧	Ansible
2. Administration système	Linux 🐧	Cockpit
2. Administration système	Linux 🐧	Webmin
2. Administration système	macOS 🍎	Terminal
2. Administration système	macOS 🍎	zsh
2. Administration système	macOS 🍎	launchd
2. Administration système	macOS 🍎	SSH
2. Administration système	macOS 🍎	Apple Remote Desktop
2. Administration système	macOS 🍎	diskutil
2. Administration système	macOS 🍎	system_profiler
2. Administration système	macOS 🍎	profiles
2. Administration système	macOS 🍎	networksetup
3. Réseaux		Wireshark
3. Réseaux		Nmap
3. Réseaux		Masscan
3. Réseaux		tcpdump
3. Réseaux		iperf3
3. Réseaux		Netcat
3. Réseaux		OpenVPN
3. Réseaux		WireGuard
3. Réseaux		Tailscale
3. Réseaux		ZeroTier
3. Réseaux		PuTTY
3. Réseaux		MobaXterm
3. Réseaux		SecureCRT
3. Réseaux		Termius
3. Réseaux		Cisco Packet Tracer
3. Réseaux		GNS3
3. Réseaux		EVE-NG
3. Réseaux	Infrastructure réseau	Cisco IOS
3. Réseaux	Infrastructure réseau	MikroTik RouterOS
3. Réseaux	Infrastructure réseau	pfSense
3. Réseaux	Infrastructure réseau	OPNsense
3. Réseaux	Infrastructure réseau	OpenWrt
3. Réseaux	Infrastructure réseau	VyOS
3. Réseaux	Infrastructure réseau	FortiOS
4. Cybersécurité	Analyse / défense	Microsoft Defender
4. Cybersécurité	Analyse / défense	Microsoft Sentinel
4. Cybersécurité	Analyse / défense	Wazuh
4. Cybersécurité	Analyse / défense	Splunk
4. Cybersécurité	Analyse / défense	Elastic Security
4. Cybersécurité	Analyse / défense	Graylog
4. Cybersécurité	Analyse / défense	CrowdStrike
4. Cybersécurité	Analyse / défense	SentinelOne
4. Cybersécurité	Analyse / défense	Sophos
4. Cybersécurité	Analyse / défense	ESET
4. Cybersécurité	Analyse / défense	Bitdefender
4. Cybersécurité	Pentest	Kali Linux
4. Cybersécurité	Pentest	Parrot Security
4. Cybersécurité	Pentest	Metasploit
4. Cybersécurité	Pentest	Burp Suite
4. Cybersécurité	Pentest	OWASP ZAP
4. Cybersécurité	Pentest	Nmap
4. Cybersécurité	Pentest	Nikto
4. Cybersécurité	Pentest	sqlmap
4. Cybersécurité	Pentest	Gobuster
4. Cybersécurité	Pentest	ffuf
4. Cybersécurité	Pentest	Hydra
4. Cybersécurité	Pentest	John the Ripper
4. Cybersécurité	Pentest	Hashcat
4. Cybersécurité	Forensics	Autopsy
4. Cybersécurité	Forensics	The Sleuth Kit
4. Cybersécurité	Forensics	Volatility
4. Cybersécurité	Forensics	FTK
4. Cybersécurité	Forensics	EnCase
4. Cybersécurité	Forensics	Magnet AXIOM
4. Cybersécurité	Forensics	Wireshark
4. Cybersécurité	Forensics	Plaso
4. Cybersécurité	Forensics	KAPE
5. Développement logiciel	Éditeurs / IDE	Visual Studio
5. Développement logiciel	Éditeurs / IDE	Visual Studio Code
5. Développement logiciel	Éditeurs / IDE	JetBrains IntelliJ IDEA
5. Développement logiciel	Éditeurs / IDE	PyCharm
5. Développement logiciel	Éditeurs / IDE	WebStorm
5. Développement logiciel	Éditeurs / IDE	PhpStorm
5. Développement logiciel	Éditeurs / IDE	Rider
5. Développement logiciel	Éditeurs / IDE	CLion
5. Développement logiciel	Éditeurs / IDE	Android Studio
5. Développement logiciel	Éditeurs / IDE	Xcode
5. Développement logiciel	Éditeurs / IDE	Eclipse
5. Développement logiciel	Éditeurs / IDE	NetBeans
5. Développement logiciel	Éditeurs / IDE	Vim
5. Développement logiciel	Éditeurs / IDE	Neovim
5. Développement logiciel	Éditeurs / IDE	Emacs
5. Développement logiciel	Éditeurs / IDE	Sublime Text
5. Développement logiciel	Langages	C
5. Développement logiciel	Langages	C++
5. Développement logiciel	Langages	C#
5. Développement logiciel	Langages	Java
5. Développement logiciel	Langages	Kotlin
5. Développement logiciel	Langages	Swift
5. Développement logiciel	Langages	Objective-C
5. Développement logiciel	Langages	Python
5. Développement logiciel	Langages	JavaScript
5. Développement logiciel	Langages	TypeScript
5. Développement logiciel	Langages	Go
5. Développement logiciel	Langages	Rust
5. Développement logiciel	Langages	PHP
5. Développement logiciel	Langages	Ruby
5. Développement logiciel	Langages	Dart
5. Développement logiciel	Langages	R
5. Développement logiciel	Langages	MATLAB
5. Développement logiciel	Langages	Lua
5. Développement logiciel	Langages	Perl
5. Développement logiciel	Langages	Bash
5. Développement logiciel	Langages	PowerShell
6. Gestion du code source		Git
6. Gestion du code source		GitHub
6. Gestion du code source		GitLab
6. Gestion du code source		Bitbucket
6. Gestion du code source		Azure DevOps
6. Gestion du code source		SVN
6. Gestion du code source		Mercurial
6. Gestion du code source	Interfaces Git	GitHub Desktop
6. Gestion du code source	Interfaces Git	GitKraken
6. Gestion du code source	Interfaces Git	Sourcetree
6. Gestion du code source	Interfaces Git	Fork
6. Gestion du code source	Interfaces Git	Tower
6. Gestion du code source	Interfaces Git	SmartGit
7. DevOps / CI-CD		Jenkins
7. DevOps / CI-CD		GitHub Actions
7. DevOps / CI-CD		GitLab CI/CD
7. DevOps / CI-CD		Azure Pipelines
7. DevOps / CI-CD		TeamCity
7. DevOps / CI-CD		CircleCI
7. DevOps / CI-CD		Travis CI
7. DevOps / CI-CD		Argo CD
7. DevOps / CI-CD		Flux
7. DevOps / CI-CD		Spinnaker
7. DevOps / CI-CD	Infrastructure as Code	Terraform
7. DevOps / CI-CD	Infrastructure as Code	OpenTofu
7. DevOps / CI-CD	Infrastructure as Code	Ansible
7. DevOps / CI-CD	Infrastructure as Code	Pulumi
7. DevOps / CI-CD	Infrastructure as Code	CloudFormation
8. Bases de données	SQL	PostgreSQL
8. Bases de données	SQL	MySQL
8. Bases de données	SQL	MariaDB
8. Bases de données	SQL	SQLite
8. Bases de données	SQL	Microsoft SQL Server
8. Bases de données	SQL	Oracle Database
8. Bases de données	SQL	IBM Db2
8. Bases de données	NoSQL	MongoDB
8. Bases de données	NoSQL	Redis
8. Bases de données	NoSQL	Cassandra
8. Bases de données	NoSQL	CouchDB
8. Bases de données	NoSQL	Elasticsearch
8. Bases de données	NoSQL	OpenSearch
8. Bases de données	NoSQL	Neo4j
8. Bases de données	Clients	DBeaver
8. Bases de données	Clients	DataGrip
8. Bases de données	Clients	pgAdmin
8. Bases de données	Clients	MySQL Workbench
8. Bases de données	Clients	SQL Server Management Studio
8. Bases de données	Clients	Azure Data Studio
8. Bases de données	Clients	Oracle SQL Developer
8. Bases de données	Clients	MongoDB Compass
9. Web / serveurs		Apache HTTP Server
9. Web / serveurs		Nginx
9. Web / serveurs		Caddy
9. Web / serveurs		IIS
9. Web / serveurs		Tomcat
9. Web / serveurs		Jetty
9. Web / serveurs		Node.js
9. Web / serveurs		Deno
9. Web / serveurs		Bun
9. Web / serveurs	PHP	PHP
9. Web / serveurs	PHP	Composer
9. Web / serveurs	PHP	Laravel
9. Web / serveurs	PHP	Symfony
9. Web / serveurs	PHP	WordPress
9. Web / serveurs	PHP	Drupal
9. Web / serveurs	PHP	Joomla
9. Web / serveurs	JavaScript	Node.js
9. Web / serveurs	JavaScript	npm
9. Web / serveurs	JavaScript	Yarn
9. Web / serveurs	JavaScript	pnpm
9. Web / serveurs	JavaScript	React
9. Web / serveurs	JavaScript	Angular
9. Web / serveurs	JavaScript	Vue
9. Web / serveurs	JavaScript	Svelte
9. Web / serveurs	JavaScript	Next.js
9. Web / serveurs	JavaScript	Nuxt
10. Cloud / infrastructure	AWS	AWS CLI
10. Cloud / infrastructure	AWS	EC2
10. Cloud / infrastructure	AWS	S3
10. Cloud / infrastructure	AWS	RDS
10. Cloud / infrastructure	AWS	Lambda
10. Cloud / infrastructure	AWS	CloudFormation
10. Cloud / infrastructure	AWS	CloudWatch
10. Cloud / infrastructure	Microsoft Azure	Azure CLI
10. Cloud / infrastructure	Microsoft Azure	Azure PowerShell
10. Cloud / infrastructure	Microsoft Azure	Azure DevOps
10. Cloud / infrastructure	Microsoft Azure	Azure Storage
10. Cloud / infrastructure	Microsoft Azure	Azure VM
10. Cloud / infrastructure	Google Cloud	gcloud CLI
10. Cloud / infrastructure	Google Cloud	GKE
10. Cloud / infrastructure	Google Cloud	Compute Engine
10. Cloud / infrastructure	Google Cloud	Cloud Storage
10. Cloud / infrastructure	Cloud multiplateforme	Terraform
10. Cloud / infrastructure	Cloud multiplateforme	Pulumi
10. Cloud / infrastructure	Cloud multiplateforme	Kubernetes
10. Cloud / infrastructure	Cloud multiplateforme	Docker
10. Cloud / infrastructure	Cloud multiplateforme	Ansible
11. Stockage / sauvegarde / récupération		Clonezilla
11. Stockage / sauvegarde / récupération		Rescuezilla
11. Stockage / sauvegarde / récupération		Veeam
11. Stockage / sauvegarde / récupération		Acronis
11. Stockage / sauvegarde / récupération		Macrium Reflect
11. Stockage / sauvegarde / récupération		EaseUS
11. Stockage / sauvegarde / récupération		MiniTool
11. Stockage / sauvegarde / récupération		Clone Hero
11. Stockage / sauvegarde / récupération		Timeshift
11. Stockage / sauvegarde / récupération		BorgBackup
11. Stockage / sauvegarde / récupération		Restic
11. Stockage / sauvegarde / récupération		Duplicati
11. Stockage / sauvegarde / récupération		UrBackup
11. Stockage / sauvegarde / récupération		rsync
11. Stockage / sauvegarde / récupération		Robocopy
11. Stockage / sauvegarde / récupération		dd
11. Stockage / sauvegarde / récupération	Disques / partitions	GParted
11. Stockage / sauvegarde / récupération	Disques / partitions	DiskPart
11. Stockage / sauvegarde / récupération	Disques / partitions	Disk Management
11. Stockage / sauvegarde / récupération	Disques / partitions	GNOME Disks
11. Stockage / sauvegarde / récupération	Disques / partitions	KDE Partition Manager
11. Stockage / sauvegarde / récupération	Disques / partitions	parted
11. Stockage / sauvegarde / récupération	Disques / partitions	fdisk
11. Stockage / sauvegarde / récupération	Disques / partitions	gdisk
11. Stockage / sauvegarde / récupération	Disques / partitions	diskutil
12. Boot / ISO / installation		Ventoy
12. Boot / ISO / installation		Rufus
12. Boot / ISO / installation		balenaEtcher
12. Boot / ISO / installation		Fedora Media Writer
12. Boot / ISO / installation		UNetbootin
12. Boot / ISO / installation		YUMI
12. Boot / ISO / installation		Easy2Boot
12. Boot / ISO / installation		GRUB
12. Boot / ISO / installation		systemd-boot
12. Boot / ISO / installation		Windows PE
12. Boot / ISO / installation		WinRE
12. Boot / ISO / installation		Clonezilla
12. Boot / ISO / installation		iPXE
12. Boot / ISO / installation		PXE
12. Boot / ISO / installation		netboot.xyz
12. Boot / ISO / installation	macOS	OpenCore
12. Boot / ISO / installation	macOS	OpenCore Legacy Patcher
12. Boot / ISO / installation	macOS	Clover
12. Boot / ISO / installation	macOS	bless
12. Boot / ISO / installation	macOS	macOS Recovery
12. Boot / ISO / installation	macOS	createinstallmedia
13. UEFI / BIOS / firmware		UEFI Shell
13. UEFI / BIOS / firmware		BIOS/UEFI Setup
13. UEFI / BIOS / firmware		fwupd
13. UEFI / BIOS / firmware		LVFS
13. UEFI / BIOS / firmware		flashrom
13. UEFI / BIOS / firmware		Dell BIOS tools
13. UEFI / BIOS / firmware		Lenovo firmware tools
13. UEFI / BIOS / firmware		HP firmware tools
13. UEFI / BIOS / firmware		Intel firmware tools
13. UEFI / BIOS / firmware	Analyse	dmidecode
13. UEFI / BIOS / firmware	Analyse	CPU-Z
13. UEFI / BIOS / firmware	Analyse	HWiNFO
13. UEFI / BIOS / firmware	Analyse	Speccy
13. UEFI / BIOS / firmware	Analyse	AIDA64
13. UEFI / BIOS / firmware	Analyse	HardInfo
13. UEFI / BIOS / firmware	Analyse	lshw
13. UEFI / BIOS / firmware	Analyse	inxi
14. Diagnostic matériel	Windows 🪟	HWiNFO
14. Diagnostic matériel	Windows 🪟	CPU-Z
14. Diagnostic matériel	Windows 🪟	GPU-Z
14. Diagnostic matériel	Windows 🪟	CrystalDiskInfo
14. Diagnostic matériel	Windows 🪟	CrystalDiskMark
14. Diagnostic matériel	Windows 🪟	MemTest86
14. Diagnostic matériel	Windows 🪟	OCCT
14. Diagnostic matériel	Windows 🪟	Prime95
14. Diagnostic matériel	Windows 🪟	FurMark
14. Diagnostic matériel	Windows 🪟	SMART tools
14. Diagnostic matériel	Linux 🐧	smartctl
14. Diagnostic matériel	Linux 🐧	nvme-cli
14. Diagnostic matériel	Linux 🐧	lm-sensors
14. Diagnostic matériel	Linux 🐧	stress-ng
14. Diagnostic matériel	Linux 🐧	memtest86+
14. Diagnostic matériel	Linux 🐧	lshw
14. Diagnostic matériel	Linux 🐧	lspci
14. Diagnostic matériel	Linux 🐧	lsusb
14. Diagnostic matériel	Linux 🐧	inxi
14. Diagnostic matériel	macOS 🍎	Apple Diagnostics
14. Diagnostic matériel	macOS 🍎	Disk Utility
14. Diagnostic matériel	macOS 🍎	diskutil
14. Diagnostic matériel	macOS 🍎	system_profiler
14. Diagnostic matériel	macOS 🍎	ioreg
14. Diagnostic matériel	macOS 🍎	pmset
14. Diagnostic matériel	macOS 🍎	log
14. Diagnostic matériel	macOS 🍎	fsck
15. Monitoring		Zabbix
15. Monitoring		Nagios
15. Monitoring		Prometheus
15. Monitoring		Grafana
15. Monitoring		PRTG
15. Monitoring		Datadog
15. Monitoring		New Relic
15. Monitoring		Checkmk
15. Monitoring		Icinga
15. Monitoring		Netdata
15. Monitoring		Telegraf
15. Monitoring		InfluxDB
16. Logs / SIEM		Splunk
16. Logs / SIEM		Elastic Stack
16. Logs / SIEM		Elasticsearch
16. Logs / SIEM		Logstash
16. Logs / SIEM		Kibana
16. Logs / SIEM		OpenSearch
16. Logs / SIEM		Graylog
16. Logs / SIEM		Loki
16. Logs / SIEM		Fluent Bit
16. Logs / SIEM		Fluentd
16. Logs / SIEM		Wazuh
17. Automatisation	Windows	PowerShell
17. Automatisation	Windows	PowerShell DSC
17. Automatisation	Windows	Task Scheduler
17. Automatisation	Windows	AutoHotkey
17. Automatisation	Windows	Chocolatey
17. Automatisation	Windows	winget
17. Automatisation	Windows	Scoop
17. Automatisation	Linux	Bash
17. Automatisation	Linux	Ansible
17. Automatisation	Linux	cron
17. Automatisation	Linux	systemd timers
17. Automatisation	Linux	Make
17. Automatisation	Linux	Python
17. Automatisation	macOS	zsh
17. Automatisation	macOS	Automator
17. Automatisation	macOS	Shortcuts
17. Automatisation	macOS	launchd
17. Automatisation	macOS	Homebrew
18. Gestion des paquets		WindowsLinuxmacOS
18. Gestion des paquets		winget
18. Gestion des paquets		apt
18. Gestion des paquets		Homebrew
18. Gestion des paquets		Chocolatey
18. Gestion des paquets		dnf
18. Gestion des paquets		MacPorts
18. Gestion des paquets		Scoop
18. Gestion des paquets		yum
18. Gestion des paquets		Nix
18. Gestion des paquets		MSIX
18. Gestion des paquets		pacman
18. Gestion des paquets		pkg
18. Gestion des paquets		NuGet
18. Gestion des paquets		zypper
18. Gestion des paquets		mas
19. Bureau / bureautique		Microsoft 365
19. Bureau / bureautique		Microsoft Office
19. Bureau / bureautique		LibreOffice
19. Bureau / bureautique		OnlyOffice
19. Bureau / bureautique		OpenOffice
19. Bureau / bureautique		WPS Office
19. Bureau / bureautique		Apple iWork
19. Bureau / bureautique		Google Workspace
19. Bureau / bureautique	PDF	Adobe Acrobat
19. Bureau / bureautique	PDF	Foxit PDF
19. Bureau / bureautique	PDF	PDF-XChange
19. Bureau / bureautique	PDF	Okular
19. Bureau / bureautique	PDF	Preview
19. Bureau / bureautique	PDF	Evince
20. Graphisme / design		Adobe Photoshop
20. Graphisme / design		Adobe Illustrator
20. Graphisme / design		Adobe InDesign
20. Graphisme / design		Adobe Lightroom
20. Graphisme / design		Affinity Photo
20. Graphisme / design		Affinity Designer
20. Graphisme / design		Affinity Publisher
20. Graphisme / design		GIMP
20. Graphisme / design		Krita
20. Graphisme / design		Inkscape
20. Graphisme / design		Blender
20. Graphisme / design		Sketch
20. Graphisme / design		Figma
20. Graphisme / design		Canva
21. Vidéo		Adobe Premiere Pro
21. Vidéo		DaVinci Resolve
21. Vidéo		Final Cut Pro
21. Vidéo		Avid Media Composer
21. Vidéo		Vegas Pro
21. Vidéo		Shotcut
21. Vidéo		Kdenlive
21. Vidéo		OpenShot
21. Vidéo		OBS Studio
21. Vidéo		HandBrake
21. Vidéo		FFmpeg
22. Audio		Audacity
22. Audio		Adobe Audition
22. Audio		FL Studio
22. Audio		Ableton Live
22. Audio		Logic Pro
22. Audio		Pro Tools
22. Audio		Reaper
22. Audio		Ardour
22. Audio		LMMS
22. Audio		VLC
22. Audio		ffmpeg
23. 3D / CAO / ingénierie		AutoCAD
23. 3D / CAO / ingénierie		SolidWorks
23. 3D / CAO / ingénierie		CATIA
23. 3D / CAO / ingénierie		Fusion 360
23. 3D / CAO / ingénierie		FreeCAD
23. 3D / CAO / ingénierie		Blender
23. 3D / CAO / ingénierie		Rhino
23. 3D / CAO / ingénierie		SketchUp
23. 3D / CAO / ingénierie		Revit
23. 3D / CAO / ingénierie		Inventor
23. 3D / CAO / ingénierie		Siemens NX
23. 3D / CAO / ingénierie		Abaqus
23. 3D / CAO / ingénierie		ANSYS
23. 3D / CAO / ingénierie		MATLAB
23. 3D / CAO / ingénierie		Simulink
24. IA / Machine Learning / Data Science		Python
24. IA / Machine Learning / Data Science		Jupyter
24. IA / Machine Learning / Data Science		JupyterLab
24. IA / Machine Learning / Data Science		Anaconda
24. IA / Machine Learning / Data Science		Miniconda
24. IA / Machine Learning / Data Science		PyTorch
24. IA / Machine Learning / Data Science		TensorFlow
24. IA / Machine Learning / Data Science		Keras
24. IA / Machine Learning / Data Science		scikit-learn
24. IA / Machine Learning / Data Science		Pandas
24. IA / Machine Learning / Data Science		NumPy
24. IA / Machine Learning / Data Science		SciPy
24. IA / Machine Learning / Data Science		Matplotlib
24. IA / Machine Learning / Data Science		R
24. IA / Machine Learning / Data Science		RStudio
24. IA / Machine Learning / Data Science		CUDA
24. IA / Machine Learning / Data Science		ROCm
24. IA / Machine Learning / Data Science		Ollama
24. IA / Machine Learning / Data Science		LM Studio
24. IA / Machine Learning / Data Science	LLM / IA locale	Ollama
24. IA / Machine Learning / Data Science	LLM / IA locale	llama.cpp
24. IA / Machine Learning / Data Science	LLM / IA locale	LM Studio
24. IA / Machine Learning / Data Science	LLM / IA locale	vLLM
24. IA / Machine Learning / Data Science	LLM / IA locale	Hugging Face Transformers
25. Data engineering / Big Data		Apache Spark
25. Data engineering / Big Data		Apache Hadoop
25. Data engineering / Big Data		Kafka
25. Data engineering / Big Data		Airflow
25. Data engineering / Big Data		Flink
25. Data engineering / Big Data		Databricks
25. Data engineering / Big Data		dbt
25. Data engineering / Big Data		Trino
25. Data engineering / Big Data		Presto
25. Data engineering / Big Data		Apache Beam
26. Blockchain / Web3		Bitcoin Core
26. Blockchain / Web3		Ethereum
26. Blockchain / Web3		Geth
26. Blockchain / Web3		Solidity
26. Blockchain / Web3		Hardhat
26. Blockchain / Web3		Foundry
26. Blockchain / Web3		MetaMask
26. Blockchain / Web3		Ganache
26. Blockchain / Web3		Remix
27. Messagerie / communication		Microsoft Teams
27. Messagerie / communication		Slack
27. Messagerie / communication		Discord
27. Messagerie / communication		Zoom
27. Messagerie / communication		Google Meet
27. Messagerie / communication		Thunderbird
27. Messagerie / communication		Outlook
27. Messagerie / communication		Apple Mail
27. Messagerie / communication		Evolution
27. Messagerie / communication		Mattermost
27. Messagerie / communication		Element
28. Navigateurs	Windows / Linux / macOS	Chrome
28. Navigateurs	Windows / Linux / macOS	Firefox
28. Navigateurs	Windows / Linux / macOS	Edge
28. Navigateurs	Windows / Linux / macOS	Safari 🍎
28. Navigateurs	Windows / Linux / macOS	Opera
28. Navigateurs	Windows / Linux / macOS	Brave
28. Navigateurs	Windows / Linux / macOS	Vivaldi
28. Navigateurs	Windows / Linux / macOS	Chromium
28. Navigateurs	Windows / Linux / macOS	Tor Browser
29. Télémaintenance		AnyDesk
29. Télémaintenance		TeamViewer
29. Télémaintenance		RustDesk
29. Télémaintenance		Chrome Remote Desktop
29. Télémaintenance		Windows Remote Desktop
29. Télémaintenance		SSH
29. Télémaintenance		VNC
29. Télémaintenance		NoMachine
29. Télémaintenance		Remmina
29. Télémaintenance		Apple Remote Desktop
30. Gestion de fichiers	Windows	Explorer
30. Gestion de fichiers	Windows	Total Commander
30. Gestion de fichiers	Windows	7-Zip
30. Gestion de fichiers	Windows	WinRAR
30. Gestion de fichiers	Linux	Nautilus
30. Gestion de fichiers	Linux	Dolphin
30. Gestion de fichiers	Linux	Thunar
30. Gestion de fichiers	Linux	PCManFM
30. Gestion de fichiers	Linux	Midnight Commander
30. Gestion de fichiers	macOS	Finder
30. Gestion de fichiers	macOS	Commander One
30. Gestion de fichiers	macOS	ForkLift
30. Gestion de fichiers	macOS	Keka
30. Gestion de fichiers	Compression	7-Zip
30. Gestion de fichiers	Compression	WinRAR
30. Gestion de fichiers	Compression	PeaZip
30. Gestion de fichiers	Compression	tar
30. Gestion de fichiers	Compression	gzip
30. Gestion de fichiers	Compression	bzip2
30. Gestion de fichiers	Compression	xz
30. Gestion de fichiers	Compression	zstd
31. Chiffrement / sécurité des données		BitLocker
31. Chiffrement / sécurité des données		VeraCrypt
31. Chiffrement / sécurité des données		FileVault
31. Chiffrement / sécurité des données		LUKS
31. Chiffrement / sécurité des données		GnuPG
31. Chiffrement / sécurité des données		OpenSSL
31. Chiffrement / sécurité des données		age
31. Chiffrement / sécurité des données		KeePass
31. Chiffrement / sécurité des données		Bitwarden
31. Chiffrement / sécurité des données		1Password
32. Gestion des mots de passe		Bitwarden
32. Gestion des mots de passe		KeePass
32. Gestion des mots de passe		KeePassXC
32. Gestion des mots de passe		1Password
32. Gestion des mots de passe		LastPass
32. Gestion des mots de passe		Dashlane
32. Gestion des mots de passe		Proton Pass
33. Analyse réseau avancée		Wireshark
33. Analyse réseau avancée		tshark
33. Analyse réseau avancée		tcpdump
33. Analyse réseau avancée		Nmap
33. Analyse réseau avancée		Zeek
33. Analyse réseau avancée		Suricata
33. Analyse réseau avancée		Snort
33. Analyse réseau avancée		ntopng
33. Analyse réseau avancée		Ettercap
33. Analyse réseau avancée		Bettercap
34. Reverse engineering		Ghidra
34. Reverse engineering		IDA Pro
34. Reverse engineering		Binary Ninja
34. Reverse engineering		radare2
34. Reverse engineering		Cutter
34. Reverse engineering		x64dbg
34. Reverse engineering		WinDbg
34. Reverse engineering		LLDB
34. Reverse engineering		GDB
34. Reverse engineering		Hopper
34. Reverse engineering		Frida
34. Reverse engineering		dnSpy
35. Débogage	Windows	WinDbg
35. Débogage	Windows	Visual Studio Debugger
35. Débogage	Windows	x64dbg
35. Débogage	Windows	Process Monitor
35. Débogage	Windows	Process Explorer
35. Débogage	Linux	GDB
35. Débogage	Linux	LLDB
35. Débogage	Linux	strace
35. Débogage	Linux	ltrace
35. Débogage	Linux	perf
35. Débogage	Linux	Valgrind
35. Débogage	macOS	LLDB
35. Débogage	macOS	Xcode Instruments
35. Débogage	macOS	DTrace
35. Débogage	macOS	Activity Monitor
36. Analyse mémoire / performances		RAMMap
36. Analyse mémoire / performances		Process Explorer
36. Analyse mémoire / performances		Process Monitor
36. Analyse mémoire / performances		Windows Performance Analyzer
36. Analyse mémoire / performances		perf
36. Analyse mémoire / performances		top
36. Analyse mémoire / performances		htop
36. Analyse mémoire / performances		btop
36. Analyse mémoire / performances		vmstat
36. Analyse mémoire / performances		iostat
36. Analyse mémoire / performances		sar
36. Analyse mémoire / performances		Activity Monitor
36. Analyse mémoire / performances		Instruments
37. Gestion de parc informatique		Microsoft Intune
37. Gestion de parc informatique		Microsoft Configuration Manager
37. Gestion de parc informatique		ManageEngine
37. Gestion de parc informatique		GLPI
37. Gestion de parc informatique		OCS Inventory
37. Gestion de parc informatique		FleetDM
37. Gestion de parc informatique		Lansweeper
37. Gestion de parc informatique		PDQ Deploy
37. Gestion de parc informatique		NinjaOne
37. Gestion de parc informatique		Datto RMM
38. ITSM / Helpdesk		GLPI
38. ITSM / Helpdesk		ServiceNow
38. ITSM / Helpdesk		Jira Service Management
38. ITSM / Helpdesk		Freshservice
38. ITSM / Helpdesk		Zendesk
38. ITSM / Helpdesk		ManageEngine ServiceDesk
38. ITSM / Helpdesk		OTRS
38. ITSM / Helpdesk		Zammad
39. Inventaire matériel / logiciel		GLPI
39. Inventaire matériel / logiciel		OCS Inventory
39. Inventaire matériel / logiciel		Lansweeper
39. Inventaire matériel / logiciel		HWiNFO
39. Inventaire matériel / logiciel		CPU-Z
39. Inventaire matériel / logiciel		Speccy
39. Inventaire matériel / logiciel		AIDA64
39. Inventaire matériel / logiciel		FleetDM
40. Serveurs de fichiers / NAS		TrueNAS
40. Serveurs de fichiers / NAS		OpenMediaVault
40. Serveurs de fichiers / NAS		Synology DSM
40. Serveurs de fichiers / NAS		QNAP QTS
40. Serveurs de fichiers / NAS		Samba
40. Serveurs de fichiers / NAS		NFS
40. Serveurs de fichiers / NAS		Ceph
40. Serveurs de fichiers / NAS		MinIO
41. Active Directory / identité		Active Directory
41. Active Directory / identité		Entra ID
41. Active Directory / identité		FreeIPA
41. Active Directory / identité		Samba AD
41. Active Directory / identité		OpenLDAP
41. Active Directory / identité		Keycloak
41. Active Directory / identité		Authentik
41. Active Directory / identité		Okta
42. PKI / certificats		OpenSSL
42. PKI / certificats		Let's Encrypt
42. PKI / certificats		Certbot
42. PKI / certificats		HashiCorp Vault
42. PKI / certificats		Microsoft AD CS
42. PKI / certificats		Smallstep
42. PKI / certificats		cfssl
43. DNS / DHCP		Windows DNS
43. DNS / DHCP		Windows DHCP
43. DNS / DHCP		BIND
43. DNS / DHCP		dnsmasq
43. DNS / DHCP		Unbound
43. DNS / DHCP		PowerDNS
43. DNS / DHCP		Kea DHCP
43. DNS / DHCP		ISC DHCP
44. Serveurs mail		Microsoft Exchange
44. Serveurs mail		Postfix
44. Serveurs mail		Sendmail
44. Serveurs mail		Exim
44. Serveurs mail		Dovecot
44. Serveurs mail		Zimbra
44. Serveurs mail		Mailcow
45. Messagerie sécurisée / collaboration		Nextcloud
45. Messagerie sécurisée / collaboration		ownCloud
45. Messagerie sécurisée / collaboration		Mattermost
45. Messagerie sécurisée / collaboration		Rocket.Chat
45. Messagerie sécurisée / collaboration		Matrix
45. Messagerie sécurisée / collaboration		Element
45. Messagerie sécurisée / collaboration		Syncthing
46. Gestion de projet		Jira
46. Gestion de projet		Trello
46. Gestion de projet		Asana
46. Gestion de projet		Monday.com
46. Gestion de projet		ClickUp
46. Gestion de projet		Redmine
46. Gestion de projet		OpenProject
46. Gestion de projet		Microsoft Project
47. Documentation / Wiki		Confluence
47. Documentation / Wiki		MediaWiki
47. Documentation / Wiki		DokuWiki
47. Documentation / Wiki		BookStack
47. Documentation / Wiki		MkDocs
47. Documentation / Wiki		Docusaurus
47. Documentation / Wiki		GitBook
48. Tests logiciels / QA		Selenium
48. Tests logiciels / QA		Playwright
48. Tests logiciels / QA		Cypress
48. Tests logiciels / QA		Appium
48. Tests logiciels / QA		Postman
48. Tests logiciels / QA		Insomnia
48. Tests logiciels / QA		JMeter
48. Tests logiciels / QA		k6
48. Tests logiciels / QA		pytest
48. Tests logiciels / QA		Jest
48. Tests logiciels / QA		PHPUnit
49. API / développement Web		Postman
49. API / développement Web		Insomnia
49. API / développement Web		Swagger / OpenAPI
49. API / développement Web		curl
49. API / développement Web		HTTPie
49. API / développement Web		REST Client
49. API / développement Web		GraphQL
49. API / développement Web		Apollo
50. Gestion de dépendances / build		Maven
50. Gestion de dépendances / build		Gradle
50. Gestion de dépendances / build		MSBuild
50. Gestion de dépendances / build		CMake
50. Gestion de dépendances / build		Ninja
50. Gestion de dépendances / build		Make
50. Gestion de dépendances / build		Cargo
50. Gestion de dépendances / build		Go modules
50. Gestion de dépendances / build		npm
50. Gestion de dépendances / build		pnpm
50. Gestion de dépendances / build		Yarn
50. Gestion de dépendances / build		Composer
50. Gestion de dépendances / build		pip
50. Gestion de dépendances / build		Poetry
50. Gestion de dépendances / build		uv
51. Électronique / embarqué / IoT		Arduino IDE
51. Électronique / embarqué / IoT		PlatformIO
51. Électronique / embarqué / IoT		ESP-IDF
51. Électronique / embarqué / IoT		STM32CubeIDE
51. Électronique / embarqué / IoT		Keil
51. Électronique / embarqué / IoT		MPLAB X
51. Électronique / embarqué / IoT		KiCad
51. Électronique / embarqué / IoT		Eagle
51. Électronique / embarqué / IoT		LTspice
51. Électronique / embarqué / IoT		Proteus
51. Électronique / embarqué / IoT		Quartus
51. Électronique / embarqué / IoT		Vivado
52. Robotique		ROS
52. Robotique		ROS 2
52. Robotique		Gazebo
52. Robotique		Webots
52. Robotique		MATLAB
52. Robotique		Simulink
52. Robotique		Arduino
52. Robotique		PlatformIO
53. Virtualisation réseau / sécurité		pfSense
53. Virtualisation réseau / sécurité		OPNsense
53. Virtualisation réseau / sécurité		Proxmox VE
53. Virtualisation réseau / sécurité		VMware ESXi
53. Virtualisation réseau / sécurité		Hyper-V
53. Virtualisation réseau / sécurité		KVM
53. Virtualisation réseau / sécurité		Xen
53. Virtualisation réseau / sécurité		QEMU
54. Haute disponibilité / clustering		Kubernetes
54. Haute disponibilité / clustering		Docker Swarm
54. Haute disponibilité / clustering		Proxmox Cluster
54. Haute disponibilité / clustering		Pacemaker
54. Haute disponibilité / clustering		Corosync
54. Haute disponibilité / clustering		Ceph
54. Haute disponibilité / clustering		GlusterFS
54. Haute disponibilité / clustering		Keepalived
54. Haute disponibilité / clustering		HAProxy
55. Reverse proxy / load balancing		Nginx
55. Reverse proxy / load balancing		HAProxy
55. Reverse proxy / load balancing		Traefik
55. Reverse proxy / load balancing		Caddy
55. Reverse proxy / load balancing		Envoy
55. Reverse proxy / load balancing		Apache
56. Web hosting		cPanel
56. Web hosting		Plesk
56. Web hosting		DirectAdmin
56. Web hosting		CyberPanel
56. Web hosting		ISPConfig
56. Web hosting		Webmin
56. Web hosting		Virtualmin
57. Systèmes embarqués / boot		GRUB
57. Systèmes embarqués / boot		U-Boot
57. Systèmes embarqués / boot		OpenCore
57. Systèmes embarqués / boot		Clover
57. Systèmes embarqués / boot		systemd-boot
57. Systèmes embarqués / boot		rEFInd
57. Systèmes embarqués / boot		Ventoy
57. Systèmes embarqués / boot		iPXE
58. Forensic disque		Autopsy
58. Forensic disque		FTK Imager
58. Forensic disque		EnCase
58. Forensic disque		Magnet AXIOM
58. Forensic disque		dd
58. Forensic disque		ddrescue
58. Forensic disque		TestDisk
58. Forensic disque		PhotoRec
58. Forensic disque		Sleuth Kit
58. Forensic disque		CAINE
58. Forensic disque		DEFT Linux
58. Forensic disque		Tsurugi Linux
58. Forensic disque		SIFT Workstation
58. Forensic disque		Guymager
58. Forensic disque		Bulk Extractor
59. Récupération de données		TestDisk
59. Récupération de données		PhotoRec
59. Récupération de données		R-Studio
59. Récupération de données		UFS Explorer
59. Récupération de données		DMDE
59. Récupération de données		Recuva
59. Récupération de données		Disk Drill
59. Récupération de données		Stellar Data Recovery
60. Gestion des partitions		DiskPart
60. Gestion des partitions		Disk Management
60. Gestion des partitions		GParted
60. Gestion des partitions		KDE Partition Manager
60. Gestion des partitions		fdisk
60. Gestion des partitions		cfdisk
60. Gestion des partitions		gdisk
60. Gestion des partitions		parted
60. Gestion des partitions		diskutil
61. Déploiement d'entreprise		MDT
61. Déploiement d'entreprise		Microsoft Configuration Manager
61. Déploiement d'entreprise		Windows Autopilot
61. Déploiement d'entreprise		Clonezilla
61. Déploiement d'entreprise		FOG
61. Déploiement d'entreprise		Cobbler
61. Déploiement d'entreprise		MAAS
61. Déploiement d'entreprise		PXE
61. Déploiement d'entreprise		iPXE
61. Déploiement d'entreprise		Ansible
62. Gestion des mises à jour	Windows	Windows Update
62. Gestion des mises à jour	Windows	WSUS
62. Gestion des mises à jour	Windows	Intune
62. Gestion des mises à jour	Windows	winget
62. Gestion des mises à jour	Windows	Chocolatey
62. Gestion des mises à jour	Linux	apt
62. Gestion des mises à jour	Linux	dnf
62. Gestion des mises à jour	Linux	yum
62. Gestion des mises à jour	Linux	pacman
62. Gestion des mises à jour	Linux	zypper
62. Gestion des mises à jour	Linux	unattended-upgrades
62. Gestion des mises à jour	macOS	Software Update
62. Gestion des mises à jour	macOS	MDM
62. Gestion des mises à jour	macOS	Munki
62. Gestion des mises à jour	macOS	Homebrew
63. MDM / gestion appareils		Microsoft Intune
63. MDM / gestion appareils		Jamf Pro
63. MDM / gestion appareils		Jamf Now
63. MDM / gestion appareils		Mosyle
63. MDM / gestion appareils		Kandji
63. MDM / gestion appareils		VMware Workspace ONE
63. MDM / gestion appareils		Apple Business Manager
63. MDM / gestion appareils		Google Endpoint Management
64. Apple / macOS spécialisé		Xcode
64. Apple / macOS spécialisé		OpenCore
64. Apple / macOS spécialisé		OpenCore Legacy Patcher
64. Apple / macOS spécialisé		Clover
64. Apple / macOS spécialisé		ProperTree
64. Apple / macOS spécialisé		GenSMBIOS
64. Apple / macOS spécialisé		MountEFI
64. Apple / macOS spécialisé		Hackintool
64. Apple / macOS spécialisé		IORegistryExplorer
64. Apple / macOS spécialisé		OCAT
64. Apple / macOS spécialisé		gibMacOS
64. Apple / macOS spécialisé		Mist
64. Apple / macOS spécialisé		createinstallmedia
64. Apple / macOS spécialisé		diskutil
64. Apple / macOS spécialisé		bless
64. Apple / macOS spécialisé		system_profiler
64. Apple / macOS spécialisé		Apple Configurator
64. Apple / macOS spécialisé		Apple Devices
64. Apple / macOS spécialisé		Apple Diagnostics
65. Windows spécialisé		PowerShell
65. Windows spécialisé		Windows Terminal
65. Windows spécialisé		DISM
65. Windows spécialisé		SFC
65. Windows spécialisé		BCDEdit
65. Windows spécialisé		DiskPart
65. Windows spécialisé		WinRE
65. Windows spécialisé		WinPE
65. Windows spécialisé		Windows ADK
65. Windows spécialisé		RSAT
65. Windows spécialisé		Sysinternals
65. Windows spécialisé		Process Explorer
65. Windows spécialisé		Autoruns
65. Windows spécialisé		Procmon
65. Windows spécialisé		PsExec
65. Windows spécialisé		Robocopy
65. Windows spécialisé		winget
65. Windows spécialisé		Chocolatey
65. Windows spécialisé		Rufus
65. Windows spécialisé		Ventoy
66. Linux spécialisé		Bash
66. Linux spécialisé		Zsh
66. Linux spécialisé		systemd
66. Linux spécialisé		GRUB
66. Linux spécialisé		apt
66. Linux spécialisé		dnf
66. Linux spécialisé		pacman
66. Linux spécialisé		snap
66. Linux spécialisé		Flatpak
66. Linux spécialisé		AppImage
66. Linux spécialisé		Docker
66. Linux spécialisé		Podman
66. Linux spécialisé		KVM
66. Linux spécialisé		QEMU
66. Linux spécialisé		LXC
66. Linux spécialisé		LXD
66. Linux spécialisé		OpenSSH
66. Linux spécialisé		Ansible
66. Linux spécialisé		Cockpit
67. Sécurité des postes		Microsoft Defender
67. Sécurité des postes		Bitdefender
67. Sécurité des postes		ESET
67. Sécurité des postes		Sophos
67. Sécurité des postes		Malwarebytes
67. Sécurité des postes		CrowdStrike
67. Sécurité des postes		SentinelOne
67. Sécurité des postes		ClamAV
67. Sécurité des postes		Little Snitch
67. Sécurité des postes		LuLu
67. Sécurité des postes		OpenSnitch
67. Sécurité des postes		Windows Firewall
67. Sécurité des postes		pfSense/OPNsense
68. Gestion des licences		Microsoft Volume Licensing
68. Gestion des licences		Microsoft 365 Admin
68. Gestion des licences		Adobe Admin Console
68. Gestion des licences		JetBrains Licensing
68. Gestion des licences		Autodesk Licensing
68. Gestion des licences		FlexNet
68. Gestion des licences		Sentinel HASP
69. Outils de productivité développeur		VS Code
69. Outils de productivité développeur		Git
69. Outils de productivité développeur		Docker
69. Outils de productivité développeur		Postman
69. Outils de productivité développeur		GitHub
69. Outils de productivité développeur		GitLab
69. Outils de productivité développeur		Jira
69. Outils de productivité développeur		npm
69. Outils de productivité développeur		Python
69. Outils de productivité développeur		Node.js
69. Outils de productivité développeur		WSL
69. Outils de productivité développeur		Homebrew
69. Outils de productivité développeur		Chocolatey
69. Outils de productivité développeur		Make
69. Outils de productivité développeur		CMake
70. Vidéosurveillance / CCTV		ONVIF Device Manager
70. Vidéosurveillance / CCTV		ZoneMinder
70. Vidéosurveillance / CCTV		Shinobi
70. Vidéosurveillance / CCTV		Blue Iris
70. Vidéosurveillance / CCTV		Agent DVR (iSpy)
70. Vidéosurveillance / CCTV		Synology Surveillance Station
70. Vidéosurveillance / CCTV		Milestone XProtect
70. Vidéosurveillance / CCTV		Hikvision SADP Tool
70. Vidéosurveillance / CCTV		Dahua ConfigTool
70. Vidéosurveillance / CCTV		Dahua SmartPSS
71. Téléphonie mobile		ADB (Android Debug Bridge)
71. Téléphonie mobile		Fastboot
71. Téléphonie mobile		Android SDK Platform Tools
71. Téléphonie mobile		Odin (Samsung)
71. Téléphonie mobile		Heimdall
71. Téléphonie mobile		SP Flash Tool (MediaTek)
71. Téléphonie mobile		Apple Configurator 2
71. Téléphonie mobile		libimobiledevice
71. Téléphonie mobile		3uTools
71. Téléphonie mobile		scrcpy
71. Téléphonie mobile		Cellebrite UFED
71. Téléphonie mobile		MSAB XRY
72. Imprimantes		CUPS
72. Imprimantes		Windows Print Management Console
72. Imprimantes		HP Smart
72. Imprimantes		Epson Connect
72. Imprimantes		Brother iPrint&Scan
72. Imprimantes		Canon IJ Network Tool
72. Imprimantes		PaperCut
72. Imprimantes		PrinterLogic
72. Imprimantes		Ghostscript
73. Serveurs (matériel & admin distante)		Dell iDRAC
73. Serveurs (matériel & admin distante)		HPE iLO
73. Serveurs (matériel & admin distante)		Lenovo XClarity
73. Serveurs (matériel & admin distante)		ipmitool
73. Serveurs (matériel & admin distante)		Supermicro IPMI/BMC
73. Serveurs (matériel & admin distante)		Redfish API tools
73. Serveurs (matériel & admin distante)		Dell Update Package (DUP)
73. Serveurs (matériel & admin distante)		HPE Service Pack for ProLiant
SONAR_CATALOGUE_EOF
    echo "[SONAR] Catalogue par défaut installé (première utilisation): $SONAR_CATALOGUE_EMBEDDED"
}

sonar_build_ai_queue_from_catalogue() {
    local out="${SONAR_QUEUE:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/MANIFEST_AI_QUEUE.tsv}"
    sonar_install_embedded_catalogue
    mkdir -p "$(dirname "$out")"
    printf 'ID\tNAME\tOS\tARCH\tVERSION\tOFFICIAL_DOMAIN\n' > "$out"
    awk -F '\t' 'NR>1 {
        id="cat-" NR-1
        name=$3
        gsub(/^[ \t]+|[ \t]+$/, "", name)
        printf "%s\t%s\tAUTO\tAUTO\tlatest\tAUTO\n", id, name
    }' "$SONAR_CATALOGUE_EMBEDDED" >> "$out"
    echo "[SONAR] AI queue générée: $out"
    echo "[SONAR] Entrées catalogue: $(($(wc -l < "$out") - 1))"
}

# === SONAR CATALOG APT DOWNLOAD ENGINE V1 ===
# Real, non-AI automatic download of the reference catalog, using apt's
# own live package index instead of an LLM (--ollama-audit/--ai-download)
# or a hand-maintained table of download URLs (which goes stale the
# moment a project renames a file or moves host). apt is the only
# package manager it makes sense to target here: preflight_final
# requires this script to run as root on Linux, so a Windows winget/
# choco integration would never execute in this script's own runtime —
# apt matches where the script actually runs.
#
# Coverage is necessarily partial and that is expected, not a bug: a
# large share of the 981-entry catalogue is commercial/licensed software
# behind an account or EULA (Adobe, JetBrains, Cellebrite UFED...), or an
# OS-builtin feature rather than a discrete download (Active Directory,
# PowerShell...) — nothing can legally or technically auto-fetch those,
# regardless of method. The resolve report names every entry that didn't
# match, so the gap is visible instead of silently assumed away.
SONAR_CATALOG_RESOLVE_REPORT="${SONAR_CATALOG_RESOLVE_REPORT:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/CATALOG_APT_RESOLVE.tsv}"
SONAR_CATALOG_DOWNLOAD_DIR="${SONAR_CATALOG_DOWNLOAD_DIR:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/Portable/AptPackages}"

# sonar_catalog_resolve_apt: matches every catalogue NAME cell (split on
# commas — many cells list several tools at once, e.g. "Ubuntu, Debian,
# Fedora...") against `apt-cache pkgnames`, plus a small curated alias
# table for well-known tools whose apt package name doesn't match their
# catalogue name (VS Code -> code, 7-Zip -> p7zip-full, Docker ->
# docker.io, ...). Writes a full DOMAIN/CATALOG_NAME/APT_PACKAGE/STATUS
# report — never downloads anything itself.
sonar_catalog_resolve_apt() {
    command -v apt-cache >/dev/null 2>&1 || { echo "[SONAR][ERROR] apt-cache introuvable — nécessite une distribution basée Debian/Ubuntu." >&2; return 127; }
    command -v python3 >/dev/null 2>&1 || { echo "[SONAR][ERROR] python3 requis." >&2; return 127; }
    sonar_install_embedded_catalogue
    mkdir -p "$(dirname "$SONAR_CATALOG_RESOLVE_REPORT")"
    local pkgnames_tmp
    pkgnames_tmp="$(mktemp)"
    apt-cache pkgnames > "$pkgnames_tmp" 2>/dev/null || true
    python3 - "$SONAR_CATALOGUE_EMBEDDED" "$pkgnames_tmp" "$SONAR_CATALOG_RESOLVE_REPORT" <<'PY'
import csv, re, sys

catalogue_path, pkgnames_path, out_path = sys.argv[1:4]

with open(pkgnames_path, encoding="utf-8", errors="replace") as f:
    apt_pkgs = set(line.strip() for line in f if line.strip())

# Small, deliberately non-exhaustive alias table: catalogue name (once
# normalized) -> real apt package name, for well-known cases where they
# differ. Anything not listed here just falls through to exact/normalized
# matching against apt_pkgs — this table exists to raise coverage on
# common tools, not to be a complete mapping.
ALIASES = {
    "vs-code": "code", "visual-studio-code": "code",
    "7-zip": "p7zip-full", "7zip": "p7zip-full",
    "docker": "docker.io",
    "node.js": "nodejs",
    "python": "python3",
    "ssh": "openssh-client", "openssh": "openssh-client",
    "kubernetes": "kubectl",
    "postgresql": "postgresql",
    "mysql": "mysql-server", "mariadb": "mariadb-server",
    "nginx": "nginx",
    "apache": "apache2", "apache-http-server": "apache2",
    "sqlite": "sqlite3",
    "vim": "vim", "neovim": "neovim",
    "putty": "putty",
    "openvpn": "openvpn", "wireguard": "wireguard",
    "gimp": "gimp",
    "inkscape": "inkscape",
    "blender": "blender",
    "audacity": "audacity",
    "obs-studio": "obs-studio", "obs": "obs-studio",
    "handbrake": "handbrake-cli",
    "ffmpeg": "ffmpeg",
    "rsync": "rsync",
    "netcat": "netcat-openbsd",
    "john-the-ripper": "john", "hydra": "hydra",
    "hashcat": "hashcat",
    "sleuth-kit": "sleuthkit", "the-sleuth-kit": "sleuthkit",
    "guymager": "guymager",
    "bulk-extractor": "bulk-extractor",
    "ddrescue": "gddrescue",
    "clamav": "clamav",
    "rkhunter": "rkhunter",
    "openjdk": "default-jdk", "java": "default-jdk",
}


def normalize(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"\([^)]*\)", "", s)          # drop parenthetical notes
    s = re.sub(r"[^a-z0-9+.\- ]", "", s)
    s = re.sub(r"\s+", "-", s).strip("-")
    return s


rows = []
with open(catalogue_path, encoding="utf-8", newline="") as f:
    reader = csv.reader(f, delimiter="\t")
    next(reader, None)  # header
    for row in reader:
        if len(row) < 3:
            continue
        domain = row[0].strip()
        for cand in (c.strip() for c in row[2].split(",")):
            if not cand:
                continue
            norm = normalize(cand)
            pkg = ""
            if norm in apt_pkgs:
                pkg = norm
            elif ALIASES.get(norm) in apt_pkgs:
                pkg = ALIASES[norm]
            status = "RESOLVED" if pkg else "UNRESOLVED"
            rows.append((domain, cand, pkg, status))

with open(out_path, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f, delimiter="\t", lineterminator="\n")
    w.writerow(["DOMAIN", "CATALOG_NAME", "APT_PACKAGE", "STATUS"])
    w.writerows(rows)
PY
    rm -f "$pkgnames_tmp"
    local total resolved
    total=$(($(wc -l < "$SONAR_CATALOG_RESOLVE_REPORT") - 1))
    resolved=$(awk -F'\t' 'NR>1 && $4=="RESOLVED"' "$SONAR_CATALOG_RESOLVE_REPORT" | wc -l)
    echo "[SONAR] Résolution catalogue -> apt : ${resolved}/${total} entrées résolues."
    echo "[SONAR] Rapport: $SONAR_CATALOG_RESOLVE_REPORT"
    sonar_audit "CATALOG_APT_RESOLVED" "total=${total};resolved=${resolved}"
}

# sonar_catalog_download_final [--dry-run]: sonar_catalog_resolve_apt()
# then `apt-get download` (fetches the .deb, does NOT install it — same
# "touch the running system as little as possible" posture as the rest
# of SONAR's operational layer) for every uniquely RESOLVED package,
# into SOURCE_DIR/Portable/AptPackages. --dry-run stops after the
# resolve report, same convention as --ai-download-dry-run.
sonar_catalog_download_final() {
    local dry_run=false
    [[ "${1:-}" == "--dry-run" ]] && dry_run=true
    sonar_catalog_resolve_apt || return $?
    if [[ "$dry_run" == "true" ]]; then
        echo "[SONAR] --dry-run : aucun téléchargement effectué, voir le rapport de résolution."
        return 0
    fi
    if ! apt-get update >/dev/null 2>&1; then
        echo "[SONAR][WARN] 'apt-get update' a échoué (réseau ou permissions) — le cache local existant, potentiellement périmé, sera utilisé." >&2
    fi
    mkdir -p "$SONAR_CATALOG_DOWNLOAD_DIR"
    local pkgs_tmp total ok=0 fail=0 pkg
    pkgs_tmp="$(mktemp)"
    awk -F'\t' 'NR>1 && $4=="RESOLVED" {print $3}' "$SONAR_CATALOG_RESOLVE_REPORT" | sort -u > "$pkgs_tmp"
    total=$(wc -l < "$pkgs_tmp")
    echo "[SONAR] ${total} paquet(s) apt unique(s) à télécharger vers ${SONAR_CATALOG_DOWNLOAD_DIR}"
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if (cd "$SONAR_CATALOG_DOWNLOAD_DIR" && apt-get download "$pkg" >/dev/null 2>&1); then
            ok=$((ok+1))
        else
            fail=$((fail+1))
            echo "[SONAR][WARN] Échec du téléchargement: $pkg" >&2
        fi
    done < "$pkgs_tmp"
    rm -f "$pkgs_tmp"
    echo "[SONAR] Téléchargement terminé : ${ok} réussi(s), ${fail} échec(s) sur ${total}."
    sonar_audit "CATALOG_APT_DOWNLOADED" "total=${total};ok=${ok};fail=${fail}"
}


# === SONAR TROUBLESHOOTING PROFILES V1 ===
# Recentrage strategique (2026-09-15) : le catalogue de reference embarque
# (981 outils, SONAR_CATALOGUE_EMBEDDED) documente ce qui EXISTE dans
# l'ecosysteme du depannage ; il ne dit pas ce qui va reellement sur la
# cle, et rien ne le telechargeait jusqu'ici de facon ciblee et verifiee.
# A partir de cette version, ce qui va sur la cle est decide par un petit
# nombre de profils FERMES, documentes, avec une raison explicite par
# outil. Le catalogue 981 reste consultable comme base de connaissance
# (voir docs/CATALOG.md) mais n'est plus la source de verite du
# deploiement — cette source de verite, ce sont les profils ci-dessous.
#
# Chaque outil est choisi pour etre librement telechargeable et
# redistribuable (pas de compte, pas de licence commerciale) : c'est ce
# qui rend --fetch (etape 2 de la feuille de route) possible sans jamais
# demander a l'operateur un identifiant/mot de passe pour un tiers.
#
# Format: PROFILE\tTOOL\tWHY (une ligne par outil ; un outil peut
# apparaitre dans plusieurs profils, ex. SystemRescue dans boot-repair ET
# disk-clone — c'est voulu, ca mutualise le support de boot). "full"
# n'est pas repete ligne par ligne ici : c'est l'union calculee des cinq
# autres profils (voir sonar_profile_tools full).
SONAR_PROFILES_TSV="$(cat <<'PROFILES_EOF'
PROFILE	TOOL	WHY
boot-repair	SystemRescue	Environnement de boot Linux maintenu activement (Arch-based, ISO signee GPG, ~1.3 Go) regroupant GParted, TestDisk, ddrescue et ClamAV dans un seul support — base commune de ce profil et du profil disk-clone.
boot-repair	GParted	Inspection et reparation de la table de partitions (inclus dans SystemRescue) — necessaire quand le boot casse a cause d'une table de partitions endommagee.
boot-repair	TestDisk	Reconstruction de secteur de boot / table de partitions (inclus dans SystemRescue, aussi telechargeable seul sur cgsecurity.org) — c'est son cas d'usage d'origine.
data-recovery	TestDisk	Recuperation de partitions et systemes de fichiers a partir d'un disque endommage ou mal reformate.
data-recovery	PhotoRec	Recuperation de fichiers par recherche de signatures (file carving), independante des metadonnees du systeme de fichiers — complementaire a TestDisk quand la structure elle-meme est perdue. Livre dans la meme archive que TestDisk (cgsecurity.org).
data-recovery	ddrescue	Cree une image secteur par secteur d'un disque en train de mourir AVANT toute tentative de recuperation — etape standard qui evite d'aggraver les dommages en ecrivant/lisant a repetition sur le disque source.
malware	ClamAV	Seul moteur antivirus open-source majeur, librement redistribuable et a signatures mises a jour (freshclam) — Malwarebytes et ESET Online Scanner ecartes : logiciels proprietaires non redistribuables librement, plusieurs exigent un compte en ligne, donc non automatisables par --fetch. Desormais disponible aussi cote WinPE (Portable\ClamAV-Windows, menu option 19), pas seulement sur ce profil SystemRescue.
malware	Dr.Web LiveDisk	Deuxieme moteur (signatures Dr.Web, differentes de ClamAV) en secours si ClamAV ne suffit pas — ISO de demarrage autonome, gratuite, sans compte. Concurrents verifies et ecartes : Comodo Rescue Disk (liens officiels morts), AVG Rescue CD (produit autonome abandonne), Trend Micro Rescue Disk (discontinue au 25/04/2025). Assurance plus faible que ClamAV : editeur ne publie qu'un MD5 (pas de GPG), verifie en direct cette session.
malware	Antivirus Live CD	Alternative "boot puis scan" plus rapide que SystemRescue quand le technicien veut juste lancer un scan hors-ligne sans passer par un shell — memes signatures ClamAV, montage automatique des partitions detectees. Fork 4MLinux, GPL-3.0.
malware	Process Explorer	Gestionnaire des taches avance (Sysinternals/Microsoft) : arborescence des processus, DLL chargees, editeur/signature de chaque binaire — la triage manuelle classique pour reperer un processus malveillant deguise en processus systeme. Freeware officiel Microsoft (EULA Sysinternals), aucun compte requis.
malware	Autoruns	Sysinternals/Microsoft : liste exhaustive de tout ce qui demarre automatiquement avec Windows (services, taches planifiees, extensions explorateur, pilotes...) — la plupart des malwares persistants s'installent dans un de ces points d'entree. Meme licence/provenance que Process Explorer.
disk-clone	SystemRescue	Meme environnement de boot que boot-repair (mutualisation du support) — fournit le shell Linux pour piloter Clonezilla/GParted/ddrescue depuis une seule cle.
disk-clone	Clonezilla	Clonage/imagerie de disque ou partition, standard open-source du secteur, supporte de nombreux systemes de fichiers.
disk-clone	GParted	Redimensionnement et gestion de partitions independamment d'un clonage complet (inclus dans SystemRescue).
disk-clone	ddrescue	Clonage secteur par secteur d'un disque physiquement defaillant, avant ou a la place d'un clonage logique classique.
disk-clone	Rescuezilla	Interface graphique conviviale pour cloner/restaurer disques et partitions — alternative accessible a Clonezilla (ligne de commande/ncurses) pour un technicien moins a l'aise avec le clavier seul, ou pour montrer l'ecran a un client. Fork de Clonezilla sous le capot (memes formats d'image, compatibles entre les deux), GPL-3.0, projet actif (rescuezilla/rescuezilla sur GitHub). ISO bootable independante (~1,5 Go, base Ubuntu 24.04 LTS choisie pour son support materiel long terme), pas un paquet installe dans SystemRescue.
password-reset	chntpw	Seul outil libre maintenu de longue date qui edite directement la ruche registre SAM de Windows pour reinitialiser un mot de passe de compte local hors-ligne — support minuscule (~18 Mo), integrable sans alourdir la cle.
hardware-diagnostic	Memtest86+	Testeur de memoire RAM autonome (boot direct, hors de tout systeme d'exploitation) — seul moyen fiable de confirmer ou d'ecarter une RAM defaillante comme cause de plantages/ecrans bleus aleatoires. GPLv2, activement maintenu (memtest86plus/memtest86plus sur GitHub), aucune restriction d'usage.
hardware-diagnostic	CrystalDiskInfo	Lecture des attributs SMART d'un disque (temperature, secteurs defectueux, heures de fonctionnement, indicateur de sante global) — complementaire a Memtest86+ : distingue une RAM defaillante d'un disque en fin de vie, deux causes frequentes confondues autrement. Licence MIT, source ouverte (hiyohiyo/CrystalDiskInfo).
hardware-diagnostic	CrystalDiskMark	Mesure les vitesses reelles de lecture/ecriture d'un disque (sequentiel et aleatoire) — un SSD qui repond mais dont les performances se sont effondrees est un symptome distinct d'un disque qui remonte des erreurs SMART. Meme editeur/licence que CrystalDiskInfo.
hardware-diagnostic	Prime95	Stress-test CPU/alimentation intensif (GIMPS) — complementaire a Memtest86+ : detecte les plantages intermittents sous charge (surchauffe, alimentation limite) que Memtest86+ seul (RAM au repos, hors charge CPU) ne revele pas. Freeware avec EULA specifique GIMPS (pas open-source au sens strict, mais usage libre sans compte ni restriction pertinente ici — voir mersenne.org/legal).
boot-repair	BlueScreenView	Analyse automatiquement les fichiers de vidage (.dmp) apres un ecran bleu pour identifier le pilote/module responsable — cible la reparation au lieu de deviner. Freeware NirSoft (personnel et commercial), aucun compte requis.
boot-repair	Rufus	Cree une cle USB d'installation Windows amorcable a partir d'une ISO — utile quand le diagnostic conclut a une reinstallation plutot qu'une reparation. Open source (GPLv3), binaires signes Authenticode (editeur verifie : Akeo Consulting) en plus du telechargement direct GitHub.
boot-repair	Super Grub2 Disk	Outil de DERNIER RECOURS quand aucune reparation de bootloader n'est immediatement possible : demarre malgre tout dans un Windows/Linux/BSD/macOS existant en contournant un GRUB/bootloader casse, pour recuperer des donnees ou retenter une reparation depuis l'interieur. Complementaire aux autres outils de ce profil (qui reparent le boot) plutot que redondant. Projet ancien et reconnu (supergrubdisk.org), licence GPL (heritee de GRUB), ISO legere (~24 Mo). MD5 recoupe via le flux RSS officiel SourceForge du projet (7fb288d83ce8bebad836e8ed2bfbe9f5) en plus du SHA-256 calcule localement.
boot-repair	Dism++	Interface graphique pour SFC/DISM (verification et reparation d'une image Windows hors ligne, nettoyage systeme) — plus accessible que les commandes DISM brutes pour un technicien qui n'en a pas la syntaxe memorisee. Open source (Chuyu-Team/Dism-Multi-language sur GitHub).
boot-repair	BleachBit	Nettoyage disque/registre avant ou apres une reparation (fichiers temporaires, caches, journaux) — alternative saine a CCleaner (telemetrie/adware ajoutes ces dernieres annees). Open source (GPLv3), bleachbit.org. NE fonctionne PAS depuis le menu WinPE (binaire 32 bits, WinPE amd64 n'a pas de WOW64) — reserve a un Windows deja demarre.
boot-repair	MiniTool Partition Wizard Free (Portable)	Redimensionne/deplace/fusionne une partition avec preservation des donnees, ce que diskpart (option 3) ne sait pas faire — utile avant/apres une reparation pour liberer ou reorganiser de l'espace sans tout reinstaller. Edition portable officielle 64 bits, fonctionne sous WinPE.
boot-repair	Bulk Crap Uninstaller	Desinstallation propre et detection des applications orphelines/residus laisses par une desinstallation ratee — utile avant une reparation pour eliminer un programme suspect d'etre la cause, ou apres pour nettoyer. Apache-2.0, usage commercial explicitement autorise. Necessite un Windows deja demarre (.NET 8 embarque dans le portable, mais l'app elle-meme cible un environnement Windows complet, pas WinPE).
boot-repair	ProduKey	Recupere la cle de licence Windows/Office installee (Registre, y compris la cle OA3x embarquee dans le BIOS pour Windows 8+) — a faire AVANT toute reinstallation, sinon la cle est perdue si elle n'est pas collee sur la machine. Freeware NirSoft (personnel et commercial, pas de vente/bundling — meme licence que BlueScreenView/BatteryInfoView). Certains antivirus la signalent a tort (outil de recuperation de cle generique, comportement documente sur nirsoft.net) : a signaler a l'operateur, pas un vrai positif.
hardware-diagnostic	IsMyLcdOK	Test de pixels morts/uniformite d'un ecran par mires plein ecran — seul type de diagnostic ecran qui a du sens en logiciel (le reste, retroeclairage/dalle, est materiel). Freeware, aucune restriction d'usage professionnel connue.
hardware-diagnostic	HWiNFO	Lecture des capteurs materiels en temps reel (tensions/rails d'alimentation, temperatures, vitesses ventilateurs) — complementaire aux autres outils hardware-diagnostic pour distinguer un probleme d'alimentation d'une RAM ou d'un disque defaillant. Freeware pour usage non-commercial (HWiNFO64/ARM64) ; HWiNFO32 (legacy, inclus dans la meme archive) reste freeware sans cette restriction. A signaler a l'operateur si usage commercial strict.
hardware-diagnostic	BatteryInfoView	Diagnostic batterie/alimentation sur portable (usure, tension, capacite de conception vs actuelle) — cas d'usage alimentation le plus frequent en depannage terrain. Freeware NirSoft (personnel et commercial, pas de vente ni de bundling), aucun compte requis.
hardware-diagnostic	H2testw	Teste l'authenticite et la fiabilite d'une cle USB/carte SD (ecrit puis relit des donnees de test) — detecte les fausses capacites annoncees et les supports defaillants, cas frequent en depannage terrain (client apportant une cle suspecte). Freeware, developpe par le magazine c't (heise.de), aucun compte requis, pas d'installateur (juste l'exe). F3 (Linux/Mac) est l'equivalent mais n'a pas de binaire Windows officiel pret a l'emploi — H2testw reste la reference sous Windows malgre sa derniere version datant de 2008 (toujours fonctionnel sous Windows 10/11). NE fonctionne PAS depuis le menu WinPE (binaire 32 bits, WinPE amd64 n'a pas de WOW64) — reserve a un Windows deja demarre.
hardware-diagnostic	Snappy Driver Installer Origin	Installation/mise a jour de pilotes hors-ligne (pack de pilotes embarque, pas de telechargement necessaire sur site) — pertinent specifiquement quand la machine cible n'a pas de reseau fonctionnel pour recuperer ses propres pilotes. Open source, snappy-driver-installer.org.
hardware-diagnostic	DriverStoreExplorer	Nettoyage du magasin de pilotes Windows (DriverStore) qui accumule des versions obsoletes au fil du temps — complementaire a Snappy Driver Installer Origin (l'un installe/met a jour, l'autre nettoie). Open source (lostindark/DriverStoreExplorer sur GitHub). NE fonctionne PAS depuis le menu WinPE (binaire 32 bits, WinPE amd64 n'a pas de WOW64) — reserve a un Windows deja demarre.
hardware-diagnostic	Keyboard Tester	Teste chaque touche individuellement (clavier virtuel a l'ecran qui s'allume a la frappe) — verifie un clavier apres remplacement ou degat liquide, trou dans le catalogue avant cet ajout (RAM/disque/ecran/batterie/CPU couverts, clavier non). Open source (GPLv3, 10yard/keyboardtester sur GitHub).
hardware-diagnostic	NWinfo	Visionneuse materielle legere (C pur, binaire unique, ~6 Mo) couvrant CPU/RAM/disque/reseau/GPU/SMBIOS/SMART/PCI/EDID, fonctionne meme sous Windows XP — comble le creneau "vieux systemes" que HWiNFO/CrystalDiskInfo ne visent pas specifiquement. Domaine public (licence Unlicense), a1ive/nwinfo sur GitHub, aucune restriction. Export JSON/YAML disponible en ligne de commande si besoin d'integration a un rapport.
peripherals-network	Android Platform Tools	adb (debug USB) et fastboot (mode bootloader) — diagnostic et reparation basique d'un telephone Android depuis un PC fonctionnel, cable branche (redemarrage force, effacement cache, reinstallation systeme si un firmware officiel est disponible). Ne s'utilise PAS depuis le menu de boot Ventoy : necessite un PC deja demarre normalement (Windows/Linux), le telephone est la cible, pas la cle. iOS hors de portee (ecosysteme Apple verrouille, aucun outil libre equivalent). Officiel Google (dl.google.com), licence Android SDK.
peripherals-network	androidqf	Acquisition forensique structuree de donnees Android (traces de compromission, journaux) — complementaire a Android Platform Tools : adb/fastboot reparent, androidqf collecte des preuves. Projet du Security Lab d'Amnesty International (mvt-project/androidqf sur GitHub), meme equipe que MVT (Mobile Verification Toolkit) qui analyse ensuite les donnees extraites. Licence MVT License 1.1 (derivee MPL-2.0) : clause specifique exigeant le consentement du proprietaire des donnees avant collecte — non bloquant pour un usage professionnel legitime mais a signaler a l'operateur. Binaire .exe portable non signe (SmartScreen avertira), aucun compte ni telemetrie annonces. Necessite un PC deja demarre normalement (meme categorie qu'Android Platform Tools), pas un scenario de boot sur la cle.
general-os	Alpine Linux	Distribution Linux minimaliste (musl/busybox) — utile pour un depannage reseau/systeme tres bas niveau ou un environnement le plus leger possible est prefere a SystemRescue. Open source, alpinelinux.org.
general-os	Arch Linux	Environnement Linux "rolling release" avec les outils/pilotes les plus recents — utile quand SystemRescue (base plus ancienne) ne reconnait pas un peripherique tres recent. Open source, archlinux.org.
general-os	Debian (DVD complet)	Distribution Linux stable de reference, hors ligne (DVD complet, pas besoin de reseau pour l'installation) — choix pertinent pour une reinstallation complete plutot qu'un depannage. Open source, debian.org.
general-os	Debian (netinst)	Meme distribution que ci-dessus, image d'installation reseau minimale (~700 Mo au lieu de ~3,7 Go) — pour une reinstallation quand la bande passante ou l'espace sur la cle est limite. Open source, debian.org.
general-os	Ubuntu Server	Distribution Linux orientee serveur, tres repandue en entreprise — pertinent pour reinstaller ou depanner un serveur Linux specifiquement (par opposition a un poste de travail). Open source, ubuntu.com.
general-os	Linux Mint	Distribution Linux orientee utilisateur final (bureau Cinnamon), interface familiere pour un utilisateur venant de Windows — pertinent si le choix final est de migrer un poste vers Linux plutot que de le reparer. Open source, linuxmint.com.
general-os	Fedora Workstation	Distribution Linux de bureau, cycle de developpement rapide, proche de l'amont (upstream) — alternative a Linux Mint pour un profil plus technique. Open source, fedoraproject.org.
general-os	Fedora KDE	Meme distribution que Fedora Workstation, environnement de bureau KDE Plasma au lieu de GNOME — au choix selon la preference de l'utilisateur final. Open source, fedoraproject.org.
general-os	Fedora Server	Meme distribution, edition serveur — pertinent pour reinstaller/depanner un serveur Linux avec un cycle plus recent qu'Ubuntu Server. Open source, fedoraproject.org.
general-os	Manjaro	Distribution basee sur Arch Linux mais avec une installation graphique simplifiee — compromis entre la fraicheur d'Arch et la facilite d'installation d'Ubuntu/Mint. Open source, manjaro.org.
general-os	CAINE	Distribution Linux specialisee forensique (Computer Aided INvestigative Environment) — analyse d'un disque en lecture seule par defaut, chaine de possession, pertinent pour un cas qui deborde du cadre non-destructif habituel de SONAR. Open source, caine-live.net.
general-os	Kali Linux	Distribution Linux orientee tests d'intrusion et securite offensive (centaines d'outils pentest preinstalles) — pertinent pour auditer un reseau/systeme plutot que le reparer. LIMITATION CONNUE (voir CHANGELOG.md) : c'est l'image "installer" (programme d'installation Debian), pas "live" — Kali ne distribue sa vraie image live (bureau pentest pret a l'emploi au demarrage) qu'en torrent, incompatible avec le modele --fetch de SONAR (URL HTTP fixe et verifiable). Cette image demarre bien et est verifiee SHA-256, mais installe Kali sur un disque au lieu d'offrir un environnement live immediat. Open source, kali.org.
PROFILES_EOF
)"

SONAR_PROFILE_NAMES="boot-repair data-recovery malware disk-clone password-reset hardware-diagnostic peripherals-network general-os full"

sonar_profile_names() { echo "${SONAR_PROFILE_NAMES}"; }

sonar_profile_scenario() {
    case "$1" in
        boot-repair) echo "Windows ou Linux ne demarre plus : MBR/GPT ou bootloader corrompu, table de partitions endommagee, fichiers systeme casses empechant le demarrage." ;;
        data-recovery) echo "Fichiers supprimes ou partition/systeme de fichiers endommage : recuperer des donnees avant qu'elles ne soient ecrasees ou que le disque ne lache completement." ;;
        malware) echo "Machine infectee : analyser et nettoyer depuis l'exterieur du systeme d'exploitation infecte, la ou le malware ne peut ni se cacher ni se defendre." ;;
        disk-clone) echo "Migration ou sauvegarde bloc-a-bloc d'un disque : remplacement de disque, image avant intervention risquee, ou disque physiquement defaillant a cloner avant qu'il ne lache." ;;
        password-reset) echo "Compte Windows local verrouille (mot de passe perdu, poste recupere sans compte admin) : reinitialisation hors-ligne du mot de passe." ;;
        hardware-diagnostic) echo "Plantages, ecrans bleus ou instabilite aleatoires sans cause logicielle evidente : ecarter ou confirmer une RAM defaillante avant de perdre du temps a reinstaller un systeme sain." ;;
        peripherals-network) echo "Telephone Android en panne (boot loop, systeme corrompu) diagnostique depuis un PC fonctionnel, cable branche — PAS un scenario de boot sur la cle, profil different des six precedents par nature." ;;
        general-os) echo "Pas un scenario de depannage : choix de distributions Linux generalistes (bureau, serveur, forensique) pour une reinstallation complete ou une preference operateur — chaque outil documente pourquoi CETTE distribution plutot qu'une autre, mais aucune n'est choisie pour resoudre un symptome precis comme les profils ci-dessus." ;;
        full) echo "Union de tous les profils ci-dessus — cle generaliste couvrant les huit scenarios/categories." ;;
        *) return 1 ;;
    esac
}

# sonar_profile_caveat PROFILE -> une limite connue et honnete a afficher
# avec le profil (chaine vide si aucune). Pas une erreur : juste ce que ce
# profil NE couvre PAS, pour ne pas laisser croire a une couverture totale.
sonar_profile_caveat() {
    case "$1" in
        boot-repair|full)
            echo "Reparation cote Linux (SystemRescue) couverte d'office. Cote Windows (bootrec/bcdedit/DISM), exige un WinPE que SONAR-SE ne redistribue pas mais peut vous aider a construire : tools/Build-SonarSE-WinPE.ps1 (Windows ADK officiel Microsoft, PowerShell) puis deposer l'ISO dans SOURCE_DIR/ISO/WinPE/ — voir docs/WINPE.md." ;;
        password-reset)
            echo "Couvre le mot de passe de COMPTE Windows local (chntpw), pas le mot de passe BIOS/UEFI (superviseur/allumage). Deliberement ecarte : les generateurs de code backdoor par numero de serie (Dell/HP/Lenovo...) trouves en ligne n'ont aucune distribution officielle editeur, provenance verifiable, ni licence claire — et sont detectes comme HackTool par la quasi-totalite des antivirus (confirme avec CmosPwd, pourtant GPL et du meme auteur que TestDisk/PhotoRec deja dans ce manifeste : Windows Defender le bloque a l'ecriture). Un outil qu'aucun antivirus ne laisse tourner sur la machine d'un technicien n'a pas sa place ici, licence ou pas. Voies legitimes : (1) Dell — code de deverrouillage officiel via le Service Tag et un code de defi, support.dell.com ; (2) HP — aucune procedure de reinitialisation cote support, remplacement de carte mere requis ; (3) Lenovo — aucune procedure pour un mot de passe superviseur ThinkPad oublie, passer par un centre de service agree. Retrait de la pile CMOS/cavalier : fonctionne sur carte mere de bureau (efface le CMOS, mot de passe inclus), NE fonctionne PAS de facon fiable sur portable (le mot de passe y est souvent stocke hors du CMOS classique, dans une EEPROM protegee)." ;;
        *) : ;;
    esac
}

# sonar_profile_tools PROFILE -> lines "TOOL\tWHY" (dedupliquees pour "full").
sonar_profile_tools() {
    local profile="${1:-}"
    if [[ "$profile" == "full" ]]; then
        awk -F'\t' 'NR>1 {print $2"\t"$3}' <<<"${SONAR_PROFILES_TSV}" | awk -F'\t' '!seen[$1]++'
    else
        awk -F'\t' -v p="$profile" 'NR>1 && $1==p {print $2"\t"$3}' <<<"${SONAR_PROFILES_TSV}"
    fi
}

# sonar_profile_list_all: vue d'ensemble des profils (nom + scenario en une ligne).
sonar_profile_list_all() {
    echo "Profils de depannage SONAR disponibles :"
    echo
    local p
    for p in ${SONAR_PROFILE_NAMES}; do
        printf '  %-14s %s\n' "$p" "$(sonar_profile_scenario "$p")"
    done
    echo
    echo "Detail complet (outils + justification) : --profile <nom>"
}

# sonar_profile_doc PROFILE -> scenario + outils + pourquoi, pour un profil precis.
sonar_profile_doc() {
    local profile="${1:-}" scenario tools
    scenario="$(sonar_profile_scenario "$profile")" || {
        echo "[SONAR][ERROR] Profil inconnu: '${profile}'. Profils disponibles: $(sonar_profile_names)" >&2
        return 2
    }
    tools="$(sonar_profile_tools "$profile")"
    if [[ -z "$tools" ]]; then
        echo "[SONAR][ERROR] Profil '${profile}' sans outil defini (bug interne)." >&2
        return 3
    fi
    echo "=== Profil SONAR: ${profile} ==="
    echo
    echo "Scenario: ${scenario}"
    echo
    echo "Outils et justification :"
    while IFS=$'\t' read -r tool why; do
        [[ -z "$tool" ]] && continue
        printf -- '  - %s\n      -> %s\n' "$tool" "$why"
    done <<< "$tools"
    local caveat
    caveat="$(sonar_profile_caveat "$profile")"
    if [[ -n "$caveat" ]]; then
        echo
        echo "LIMITE CONNUE: ${caveat}"
    fi
    echo
    echo "NOTE: le catalogue de 981 outils embarque (--help pour SONAR_CATALOGUE_EMBEDDED)"
    echo "      reste une base de connaissance consultable ; ce profil, pas ce catalogue,"
    echo "      decide de ce qui va reellement sur la cle."
    echo "NOTE: --fetch ${profile} telecharge et verifie (SHA-256 contre manifeste scelle)"
    echo "      les outils de ce profil — necessite --fetch-manifest-seal (role VAULT) au"
    echo "      prealable. Voir docs/DEPLOYMENT.md, Etape 0bis."
    sonar_audit "PROFILE_DOC_VIEWED" "profile=${profile}"
}

# === SONAR FETCH V1 (étape 2/6) ===
# --fetch <profil> télécharge chaque outil (unique) du profil depuis une URL
# connue et vérifie son SHA-256 contre ce manifeste — supprime le fichier et
# refuse sur non-correspondance, journalise systématiquement (audit
# hashchainé + rapport TSV dans SOURCE_DIR/.../FETCH). Le manifeste
# lui-même est protégé par un scellé HMAC (secret de build existant,
# sonar_hmac_sha256_file) : --fetch refuse de fonctionner tant que
# --fetch-manifest-seal (rôle VAULT) n'a pas été exécuté au moins une fois
# sur cette machine — "un manifeste non signé est une porte ouverte".
#
# Ce que --fetch vérifie EN DIRECT, à chaque exécution : le SHA-256 du
# fichier téléchargé. Les colonnes SIG_URL/SIG_TYPE/NOTES documentent
# COMMENT ce SHA-256 a été établi (signature GPG amont du fournisseur,
# vérifiée manuellement lors de la constitution de ce manifeste, voir
# CHANGELOG.md) — --fetch ne re-télécharge pas les clés GPG de six
# fournisseurs différents à chaque exécution, ce qui serait au-delà de ce
# qui a été demandé (un manifeste signé PAR SONAR, pas une chaîne de
# confiance GPG multi-fournisseurs re-vérifiée en continu).
SONAR_FETCH_MANIFEST_TSV="$(cat <<'FETCH_EOF'
TOOL	URL	SHA256	SIG_URL	SIG_TYPE	NOTES
SystemRescue	https://fastly-cdn.system-rescue.org/releases/13.02/systemrescue-13.02-amd64.iso	ad4d670b72859d887c7960142a9a9d36a3e50446694a035e254442f65d6e7572	https://www.system-rescue.org/releases/13.02/systemrescue-13.02-amd64.iso.asc	gpg	SHA-256 et signature GPG verifies en direct sur l'ISO complete (1,3 Go) cette session (cle Francois Dupoux, fingerprint 0FF11AF0...8320B897) : gpg: Good signature. Les deux methodes de verification concordent.
TestDisk	https://www.cgsecurity.org/testdisk-7.2.linux26-x86_64.tar.bz2	19669b6d36314d6e531efdf836c768574e8a556d1e9db3c8f3c4e93a5092cb1c		none	Couvre aussi PhotoRec (meme archive). Aucun .sha256/.sig publie par cgsecurity.org ; SHA-256 calcule localement apres telechargement HTTPS depuis le domaine officiel.
ddrescue	https://ftp.gnu.org/gnu/ddrescue/ddrescue-1.30.tar.lz	2264622d309d6c87a1cfc19148292b8859a688e9bc02d4702f5cd4f288745542	https://ftp.gnu.org/gnu/ddrescue/ddrescue-1.30.tar.lz.sig	gpg	Signature GPG verifiee cette session (cle Antonio Diaz, via gnu-keyring.gpg officiel de gnu.org).
ClamAV	https://www.clamav.net/downloads/production/clamav-1.5.4.linux.x86_64.deb	28d6efc5b4423e7830c3559339552eb53870a9eac51ac4efb37d60530d329886	https://www.clamav.net/downloads/production/clamav-1.5.4.linux.x86_64.deb.sig	gpg	Signature GPG verifiee cette session (cle Cisco Talos). Extraire avec 'ar x clamav*.deb && tar xf data.tar.*' (pas besoin de dpkg, fonctionne sur SystemRescue/Arch) : binaire reel en usr/local/bin/clamscan (pas usr/bin). Necessite ensuite export LD_LIBRARY_PATH=<extrait>/usr/local/lib (sinon 'error while loading shared libraries: libclamav.so.12'), puis 'freshclam --datadir=<dossier>' (reseau requis, paquet sans base de signatures embarquee) et 'clamscan --database=<meme dossier> -r <cible>' (sinon 0 signature chargee, scan silencieusement vide). Verifie de bout en bout sur materiel reel 2026-09-15, 3/3 fichiers EICAR detectes apres ces etapes — voir CHANGELOG.
ClamAV-Windows	https://github.com/Cisco-Talos/clamav/releases/download/clamav-1.5.4/clamav-1.5.4.win.x64.zip	0d9e0228b2674137ea1a2853566c98a0278ad52ab2582c3d6dbd75373848c395	https://github.com/Cisco-Talos/clamav/releases/download/clamav-1.5.4/clamav-1.5.4.win.x64.zip.sig	gpg	Meme version/cle que la ligne ClamAV (Linux) ci-dessus, build Windows officiel (memes releases GitHub Cisco-Talos/clamav). Signature GPG verifiee cette session (cle Cisco Talos, via src/manual/cisco-talos.gpg du depot Cisco-Talos/clamav-documentation) : gpg: Good signature, fingerprint 5BADCA2665EF59DCF8A23D8B707F0DB480836771. L'archive officielle (225 Mo) contient aussi clamd/clambc/clamsubmit, des .pdb de debogage (467 Mo) et des en-tetes/.lib de developpement (293 Mo) : sonar_fetch_wrap_clamav_win() ne garde que clamscan.exe/sigtool.exe/freshclam.exe, les DLL requises (bundlees, y compris vcruntime/msvcp — aucune dependance sur un Redistribuable VC++ installe separement), certs/ et conf_examples/ (~100 Mo). Verifie sous WinPE 26100 (VM VirtualBox) cette session : clamscan.exe se lance sans erreur de DLL manquante, charge une base de signatures personnalisee (sigtool/.hdb) et detecte correctement un fichier correspondant — memes garanties que le test EICAR du build Linux (voir CHANGELOG), sans utiliser le texte EICAR lui-meme (bloque par l'antivirus de la machine hote a chaque ecriture sur disque).
Dr.Web LiveDisk	https://cdn-download.drweb.com/pub/drweb/livedisk/drweb-livedisk-900-cd.iso	bc14a88256b3d078318222e003f8c6af235aec710e624c65e4f7206ed652457d		sha256	Antivirus de secours COMPLEMENTAIRE a ClamAV (moteur different, base de signatures Dr.Web propre) — pas un remplacement : ISO de demarrage autonome (Linux embarque), pas installable sur la cle/dans WinPE. Rescue disks concurrents verifies cette session et ECARTES : Comodo Rescue Disk (page produit et liens de telechargement officiels tous morts, seuls des miroirs tiers 2013-2019 subsistent), AVG Rescue CD (produit autonome abandonne, remplace par une fonction interne a AVG AntiVirus, seuls des agregateurs tiers proposent encore un binaire de 2016), Trend Micro Rescue Disk (discontinuation officielle annoncee au 25 avril 2025). ESET SysRescue Live et F-Secure Rescue CD ecartes sans re-verification (deja documentes morts). CORRIGE 2026-09-23 : la colonne SIG_TYPE disait a tort "md5" — le hash stocke fait 64 caracteres hexadecimaux (recalcule cette session : c'est bien un SHA-256, pas un MD5 ; erreur d'etiquetage d'une session precedente, jamais le fichier lui-meme). Toujours plus faible que les lignes GPG de ce manifeste (pas de signature amont, juste un hash publie sur le site officiel). Gratuit, aucun compte requis, lien de telechargement direct trouve dans le HTML de la page officielle (pas de page JS dynamique a executer pour l'obtenir). Windows 64 bits uniquement (le LiveDisk lui-meme est un environnement Linux, mais l'outil ne scanne/restaure que des systemes Windows 64 bits — non verifie plus avant). Boot reel teste cette session (VM) : voir CHANGELOG.
Clonezilla	https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/3.3.3-15/clonezilla-live-3.3.3-15-amd64.iso/download	482518ea32af3b82ed15d09e2e7714806775deb62aeed81491e534f6cc6bbc47		none	SHA-256 verifie via CHECKSUMS.TXT signe GPG (cle DRBL) sur clonezilla.org (hors SourceForge). L'ISO vient de SourceForge : miroirs parfois instables, --fetch reprend un telechargement interrompu (curl -C -).
chntpw	http://pogostick.net/~pnh/ntpasswd/cd140201.zip	c88d86aee55b31827ab4782d05bd44922276955909c43c69f0fb15377cc64374		none	ATTENTION assurance plus faible que les autres lignes : source officielle en HTTP seul (pas de TLS), MD5 uniquement publie par le fournisseur (pas de SHA-256/GPG amont). MD5 recoupe (f274127bf8be9a7ed48b563fd951ae9e) lors de la constitution de ce manifeste ; SHA-256 calcule localement.
Memtest86+	https://www.memtest.org/download/v8.10/mt86plus_8.10_x86_64.iso.zip	93530005d6ac6a85aa2a49c68604a43c25794ecccf796c4f8849a73a8001be9a		none	SHA-256 publie sur memtest.org (sha256sum.txt du meme domaine officiel, pas de GPG pour cette release) et recalcule localement apres telechargement HTTPS cette session : correspond exactement. Fichier est un .zip contenant l'ISO bootable (mt86plus_8.10_x86_64.iso) — extraire puis deposer l'ISO extraite dans ISO/ (pas Portable/, malgre le routage par extension de --fetch qui le place initialement dans Portable/Fetched/ a cause du .zip).
CrystalDiskInfo	https://sourceforge.net/projects/crystaldiskinfo/files/9.9.2/CrystalDiskInfo9_9_2.zip/download	01acb3176851a85824d9589c6514e3eb9771eb7f9d5ee58ed9b4e057bd21c7df		none	Licence MIT confirmee (github.com/hiyohiyo/CrystalDiskInfo). Aucune somme officielle publiee par l'editeur ; SHA-256 calcule localement apres telechargement depuis SourceForge (miroir officiel du projet, meme schema de confiance que Clonezilla dans ce manifeste). Version portable (pas l'installeur, pour eviter les variantes "Ads"/bundlees listees sur crystalmark.info) : .exe Windows autonome, a lancer depuis WinPE (voir tools/Build-SonarSE-WinPE.ps1) ou un Windows demarre normalement — ne fonctionne pas depuis SystemRescue (Linux).
Process Explorer	https://download.sysinternals.com/files/ProcessExplorer.zip	746770d3f54326dd7da16c2b2815803ab131f348cba24a91cb6a38cfd2f7073f		none	Licence Microsoft Sysinternals EULA (freeware, usage personnel et commercial, sans compte ni cle). URL officielle sur le domaine Microsoft (download.sysinternals.com). Aucune somme publiee separement ; SHA-256 calcule localement apres telechargement HTTPS direct cette session. Windows uniquement (WinPE ou Windows demarre normalement).
Autoruns	https://download.sysinternals.com/files/Autoruns.zip	7b3a8eed819f732a3e4c134aecaeaebb8d643a46490ccddb82cc8a1a745c4cf7		none	Meme licence/provenance que Process Explorer (Microsoft Sysinternals, download.sysinternals.com). SHA-256 calcule localement apres telechargement HTTPS direct cette session. Windows uniquement.
CrystalDiskMark	https://sourceforge.net/projects/crystaldiskmark/files/9.0.3/CrystalDiskMark9_0_3.zip/download	e0c1e76a8ca5df524ffb83b4553cc8f27e539feb3c2a692cc41189783c494b78		none	Meme editeur/licence MIT que CrystalDiskInfo (crystalmark.info / hiyohiyo). SHA-256 calcule localement apres telechargement depuis SourceForge. Windows uniquement.
Prime95	https://download.mersenne.ca/gimps/v30/30.19/p95v3019b20.win64.zip	d9475f2ff3f4a6a701abc49a86a66126cb48abd10bda6fa87039d98fa8756bca		none	Freeware GIMPS (mersenne.org/legal) : usage libre sans compte ni restriction pertinente pour un usage en stress-test (la seule clause notable concerne une prime EFF si le code source sert a decouvrir un nombre premier record — hors sujet ici). Mirroir officiel mersenne.ca. SHA-256 calcule localement. Windows uniquement (build win64).
BlueScreenView	https://www.nirsoft.net/utils/bluescreenview-x64.zip	df57d4c9418dd2771035f2f7b70952caeb20d2269af683a0ab0665125c821479		none	Freeware NirSoft (usage personnel et commercial libre — seule exception connue chez NirSoft concerne un autre outil, NK2Edit). Version 64 bits explicitement choisie (et non la generique 32 bits) : WinPE amd64 n'a PAS de sous-systeme WOW64 (aucun composant "WinPE-WoW64" dans l'ADK, verifie 2026-09-22 — limitation de WinPE elle-meme, pas un oubli de build) donc un .exe 32 bits ne s'y lance jamais ("rien ne se passe" au clic, aucune erreur visible). SHA-256 calcule localement apres telechargement direct depuis nirsoft.net. Windows uniquement.
Rufus	https://github.com/pbatard/rufus/releases/download/v4.15/rufus-4.15.exe	84c8a437f8af89257524478489e5c85f1edf25f761d299e2bcde46ac0afbe106		none	Open source GPLv3 (github.com/pbatard/rufus). L'auteur ne publie pas de SHA-256 statique par choix deliberateur (FAQ officielle) : le binaire est signe Authenticode (editeur verifie "Akeo Consulting"), verifie automatiquement par Windows au lancement — assurance au moins equivalente a un hash publie. SHA-256 calcule localement quand meme, comme reference. Windows uniquement.
Dism++	https://github.com/Chuyu-Team/Dism-Multi-language/releases/download/v10.1.1002.2/Dism%2B%2B10.1.1002.1B.zip	5bbab96d60704854efd8246a7d9371688b9102261544827fc8884126d70bcb3b		none	Open source (Chuyu-Team/Dism-Multi-language sur GitHub). Aucune somme publiee separement par le projet ; SHA-256 calcule localement apres telechargement direct GitHub cette session. Windows uniquement.
BleachBit	https://download.bleachbit.org/get/BleachBit-6.0.4-portable.zip	3425195570e4d191695c45537065dc007a51efd4fd675a47f7b6da6d686a4660		none	Open source (GPLv3, bleachbit.org). Aucune somme publiee separement sur le site officiel ; SHA-256 calcule localement apres telechargement HTTPS direct depuis download.bleachbit.org cette session. Multiplateforme, version portable Windows utilisee ici. ATTENTION : ce portable officiel est 32 bits (verifie, pas d'alternative 64 bits proposee par l'editeur) — NE se lance PAS depuis le menu WinPE amd64 (pas de WOW64, voir note BlueScreenView) : "rien ne se passe" au clic, sans erreur visible. Reste utilisable depuis un Windows deja demarre normalement (32 et 64 bits y ont tous deux WOW64).
ProduKey	https://www.nirsoft.net/utils/produkey-x64.zip	e4604e0ee680370448c6a832856dff4a0255ca763672825a7a67a2a4662b9909		none	Freeware NirSoft (personnel et commercial, pas de vente/bundling — meme licence que BlueScreenView/BatteryInfoView). Certains antivirus le signalent a tort (outil de recuperation de cle generique — voir la page NirSoft "Known Problems", faux positif documente par l'editeur). SHA-256 calcule localement apres telechargement direct depuis nirsoft.net cette session. Windows uniquement.
IsMyLcdOK	https://www.softwareok.com/Download/IsMyLcdOK_x64.zip	5b67541c0db43124539509071aa56a4c59621b6249abb043f8c1c5c31750553b		none	Freeware, aucun compte requis. Aucune somme publiee separement par l'editeur ; SHA-256 calcule localement apres telechargement HTTPS direct depuis softwareok.com cette session. Windows uniquement (64 bits).
HWiNFO	https://www.hwinfo.com/files/hwi_852.zip	640c707de4c40c6903ed2ae916e62e6b7d5d6357c20fbf12d6b9753f7ae99c17		none	Version portable (32+64+ARM64 dans une seule archive). Freeware pour HWiNFO32 (legacy) ; HWiNFO64/ARM64 sont freeware pour usage NON-COMMERCIAL uniquement — a signaler a l'operateur si usage commercial strict (voir hwinfo.com/license). Aucune somme publiee separement ; SHA-256 calcule localement apres telechargement HTTPS direct depuis hwinfo.com cette session. Windows uniquement.
BatteryInfoView	https://www.nirsoft.net/utils/batteryinfoview-x64.zip	a01a2dfae2b136ade4efe88b36993256b6121db0f797a827c2b8eea16105246f		none	Freeware NirSoft (personnel et commercial, pas de vente/bundling — meme licence que BlueScreenView). SHA-256 calcule localement apres telechargement direct depuis nirsoft.net cette session. Windows uniquement.
H2testw	ftp://ftp.heise.de/pub/ct/ctsi/h2testw_1.4.zip	0d54b8beca3bc2ebfab543dbe793d52658d278538f9062b816fb77abe2dac187		none	Freeware, magazine c't (heise.de), aucun compte requis. URL FTP directe d'origine (la page produit heise.de moderne oblige a executer du JS et pousse un telechargement tiers "recommande" a cote — evite ici). Archive propre (juste h2testw.exe + readme), pas d'installateur groupe. Aucune somme publiee separement par l'editeur ; SHA-256 calcule localement apres telechargement cette session. Windows uniquement, derniere version 2008 mais fonctionnelle sous Windows 10/11 (confirme par plusieurs sources tierces indépendantes, dont portablefreeware.com). ATTENTION : h2testw.exe est compile 32 bits, aucune version 64 bits n'existe chez l'editeur (verifie 2026-09-22) — NE se lance PAS depuis le menu WinPE amd64 (pas de WOW64, voir note BlueScreenView) : "rien ne se passe" au clic, sans erreur visible. Reste utilisable depuis un Windows deja demarre normalement.
Snappy Driver Installer Origin	https://www.glenn.delahoy.com/downloads/sdio/SDIO_2.0.4.887.zip	9d92cdd3bebf04d48e495b30277ae61ef2a61a67e1d164a6a241c1bc3a8a3d0b		none	Open source (snappy-driver-installer.org). Aucune somme publiee separement par l'editeur ; SHA-256 calcule localement apres telechargement HTTPS direct cette session. Contient un pack de pilotes embarque (installation hors-ligne). Windows uniquement.
DriverStoreExplorer	https://github.com/lostindark/DriverStoreExplorer/releases/download/v1.0.26/DriverStoreExplorer-v1.0.26.zip	89a5ed17bf7c08c869294af2202f5f9b34050f81c2feeaa6cd694970da8e931f		none	Open source (MIT, lostindark/DriverStoreExplorer sur GitHub). Aucune somme publiee separement ; SHA-256 calcule localement apres telechargement direct GitHub cette session. Windows uniquement. ATTENTION : Rapr.exe (le binaire) est compile 32 bits, un seul asset publie par release (pas de variante 64 bits distincte trouvee) — NE se lance PAS depuis le menu WinPE amd64 (pas de WOW64, voir note BlueScreenView) : "rien ne se passe" au clic, sans erreur visible. Reste utilisable depuis un Windows deja demarre normalement.
Keyboard Tester	https://github.com/10yard/keyboardtester/releases/download/v0.2/keyboard_tester_v0_2_win64.zip	bf81398c90b9d6a1181bdb15d43d786e4c2c6ec9ac75198f9d9566b94dbc7b54		none	Open source (GPLv3, 10yard/keyboardtester sur GitHub). Aucune somme publiee separement ; SHA-256 calcule localement apres telechargement direct GitHub cette session. Windows uniquement (build x64 ; build x86 aussi disponible sur la meme release si besoin).
Android Platform Tools	https://dl.google.com/android/repository/platform-tools-latest-windows.zip	45f4d63113e895ebde0c90f194099a4676b6ac653bd28d54314a9e022bbc1a99		none	URL officielle Google (dl.google.com, meme domaine que les releases Android Studio). Licence Android SDK (contrat Google, pas open-source au sens strict, mais usage libre sans compte). "latest" dans l'URL : Google ne publie pas d'URL versionnee stable ni de somme officielle pour ce point d'entree — SHA-256 calcule localement au moment du telechargement, revalide a chaque --fetch (pas de garantie de stabilite dans le temps contrairement aux autres entrees de ce manifeste, a re-verifier si le contenu change).
Alpine Linux	https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-standard-3.24.1-x86_64.iso	f4dd613206676c62949144c8ad75fc64582099f444dd1485bae104a60f51dd26		none	SHA-256 publie sur le domaine officiel (fichier .sha256 a cote de l'ISO, dl-cdn.alpinelinux.org) et recoupe localement apres telechargement.
Arch Linux	https://geo.mirror.pkgbuild.com/iso/latest/archlinux-2026.09.01-x86_64.iso	be8458032f8105e60ee2a3067f950b6e3c007ee51b38dac50e8b48e765561c91		none	SHA-256 publie sur le miroir officiel geo.mirror.pkgbuild.com (redirection vers un miroir proche gere par le projet Arch, sha256sums.txt) et recoupe localement.
Debian (DVD complet)	https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd/debian-13.7.0-amd64-DVD-1.iso	347b6c67a3cc0b7ddb60b178f683470c4e2b7ac426c996d9337a2ff36c1a32d2		none	SHA-256 publie sur le domaine officiel (cdimage.debian.org, SHA256SUMS) et recoupe localement.
Debian (netinst)	https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.7.0-amd64-netinst.iso	a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355		none	Meme source/verification que Debian DVD complet.
Ubuntu Server	https://releases.ubuntu.com/26.04.1/ubuntu-26.04.1-live-server-amd64.iso	cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927		none	SHA-256 publie sur le domaine officiel (releases.ubuntu.com, SHA256SUMS) et recoupe localement.
Linux Mint	https://mirrors.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso	a081ab202cfda17f6924128dbd2de8b63518ac0531bcfe3f1a1b88097c459bd4		none	ISO et sha256sum.txt recuperes sur mirrors.kernel.org (miroir officiel liste sur linuxmint.com/edition.php, kernel.org est une infrastructure de confiance etablie) et recoupe localement. Linux Mint lui-meme ne publie pas de checksum sur son propre domaine, seulement sur ses miroirs officiels.
Fedora Workstation	https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/Fedora-Workstation-Live-44-1.7.x86_64.iso	1620295f6a00c27c3208f0c00b8ece4eab1ec69b9002152d97488bf26a426ddf		none	SHA-256 publie sur le domaine officiel (download.fedoraproject.org, fichier CHECKSUM signe PGP) et recoupe localement.
Fedora KDE	https://download.fedoraproject.org/pub/fedora/linux/releases/44/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-44-1.7.x86_64.iso	c8295961d4c41adbf785a31a17c21a971d3b7415fda72dcad0c11c49577bf03a		none	Meme source/verification que Fedora Workstation.
Fedora Server	https://download.fedoraproject.org/pub/fedora/linux/releases/44/Server/x86_64/iso/Fedora-Server-dvd-x86_64-44-1.7.iso	85837793bfa36db6bc709b4cecd2ec116951b87d9c53c3d95eb2fac8dcf7cf1f		none	Meme source/verification que Fedora Workstation.
Manjaro	https://download.manjaro.org/gnome/26.1.0/manjaro-gnome-26.1.0-minimal-260812-linux618.iso	c95ab4fcce563edf5bd780dfad7a60d6e62f260473d772eee75a690f0c6f1861		none	SHA-256 publie sur le domaine officiel (download.manjaro.org, fichier .sha256 a cote de l'ISO) et recoupe localement.
CAINE	https://www.caine-live.net/Downloads/caine14.0.iso	2702226cf9ee131ee54e9649d6d90008f3fe851ba35939f43ae8cb614a00d564		none	SHA-256 publie sur le domaine officiel (caine-live.net) et recoupe localement.
Kali Linux	https://cdimage.kali.org/kali-2026.2/kali-linux-2026.2-installer-amd64.iso	6dbefacc95e3b556c19c48e8bae39b8b505e2d3a1aba0bfb7ab62b036c3d2ba3		none	SHA-256 publie sur le domaine officiel (kali.download/base-images/kali-2026.2/SHA256SUMS, meme infrastructure que cdimage.kali.org qui y redirige) et recoupe via deux methodes independantes cette session. cdimage.kali.org redirige (302) vers un miroir geographique proche, comme l'entree Arch Linux ci-dessus — couvert par le -fL (follow redirect) de sonar_fetch_one_tool. LIMITATION CONNUE : seule l'image "installer" est disponible en HTTP direct ; l'image "live" (bureau pret a l'emploi) n'existe qu'en torrent sur le site officiel (verifie sur cdimage.kali.org et kali.org/get-kali) — incompatible avec --fetch. Voir CHANGELOG.md.
MiniTool Partition Wizard Free (Portable)	https://cdn2.minitool.com/?p=pw&e=pwfree-64bit-portable	11db3ca0e52b04105181a2bc50336bb611aff46ec97d0bd0c01054e9e1c2386e		none	Redimensionne/deplace/fusionne une partition AVEC preservation des donnees — diskpart (deja natif WinPE) ne sait faire que creer/supprimer/etendre-sur-espace-libre, pas ca. Edition Free authentique (pas une demo bridee) empaquetee en .zip portable par l'editeur, sans installation (partitionwizard.exe, verifie session : "Personal use" absent de l'EULA affiche par l'appli elle-meme contrairement a d'autres outils du meme type evalues et ecartes cette session — Geek Uninstaller/NetAdapter Repair). Editeur ne publie pas de SHA-256/GPG separe : authenticite verifiee a la place par signature Authenticode valide (CN=MiniTool Software Limited) sur partitionwizard.exe apres extraction ; SHA-256 de l'archive calcule localement sur ce telechargement. Fonctions payantes (migration OS, recuperation de partition) grisees mais absentes de completement bloquer l'usage gratuit des fonctions de base.
Bulk Crap Uninstaller	https://github.com/BCUninstaller/Bulk-Crap-Uninstaller/releases/download/v6.3/BCUninstaller_6.3.0_portable.7z	1ab75c8fdb88cfc8c05012ef21136f35e7c477bb58b7f69d7d3b4495179c5dc3		none	Remplace Geek Uninstaller (ecarte cette session : licence "usage personnel uniquement", verifie dans son EULA d'origine). Apache-2.0, README du depot officiel explicite : "can be used in both private and commercial settings for free and with no obligations". 21,5k etoiles GitHub, activement maintenu (derniere release recente), variante portable auto-suffisante (runtime .NET 8 inclus, aucune installation). Asset telecharge directement depuis les releases GitHub du depot officiel BCUninstaller/Bulk-Crap-Uninstaller (pas un miroir tiers). Executables NON signes numeriquement depuis la v5.9 — choix assume et explique par le projet lui-meme dans ses notes de version (la signature declenchait plus de faux positifs antivirus qu'elle n'apportait de garantie) : verification par SHA-256 calcule localement sur ce telechargement a la place, comme plusieurs autres lignes de ce manifeste sans GPG amont (TestDisk, Manjaro, CAINE). Testee sans alerte Windows Defender apres extraction cette session. Detecte aussi les applications orphelines/laissees par une desinstallation incomplete, utile pour nettoyer avant reinstallation.
NWinfo	https://github.com/a1ive/nwinfo/releases/download/v1.6.6/NWinfo.zip	52006a9280b53449375fd8d7211a2a8def7e287f93028bb469660ce877bd4a2e		none	Domaine public (licence Unlicense, a1ive/nwinfo sur GitHub). Aucune somme publiee separement par l'editeur pour cette release ; SHA-256 calcule localement apres telechargement direct GitHub cette session (correspond a celui affiche sur la page de release GitHub). Binaire C pur, aucune dependance lourde. Windows uniquement (build .zip utilise ici).
Super Grub2 Disk	https://sourceforge.net/projects/supergrub2/files/2.06s4/super_grub2_disk_2.06s4/supergrub2-classic-2.06s4-multiarch-CD.iso/download	d26ee9cda990051fbe4c2b367659df5156a130a7ada29f0b4fb0e65928d8ebab		none	SHA-256 calcule localement apres telechargement depuis SourceForge (miroir officiel du projet, meme schema de confiance que Clonezilla/CrystalDiskInfo dans ce manifeste) ; recoupe avec le MD5 publie par SourceForge dans le flux RSS officiel du projet (7fb288d83ce8bebad836e8ed2bfbe9f5) — deux sources independantes concordent. Variante "classic multiarch" choisie (ISO hybride BIOS+UEFI la plus generaliste). GPL (herite de GRUB).
androidqf	https://github.com/mvt-project/androidqf/releases/download/v1.8.3/androidqf_windows_amd64_1.8.3_unsigned.exe	2a5aa89b8aa2145d1246372ef3310ffd1e6d8a457c59b0a232c3de79892d4650	https://github.com/mvt-project/androidqf/releases/download/v1.8.3/checksums.txt	sha256	Projet du Security Lab d'Amnesty International (mvt-project/androidqf sur GitHub). SHA-256 calcule localement et recoupe avec checksums.txt publie par l'editeur sur la meme release GitHub : concorde exactement. Licence MVT License 1.1 (derivee MPL-2.0) avec clause de consentement du proprietaire des donnees avant collecte — a signaler a l'operateur, non bloquant pour un usage forensique professionnel legitime. Executable non signe (SmartScreen avertira), aucun compte ni telemetrie annonces. Windows uniquement (build utilise ici) ; ne s'utilise pas depuis le menu de boot Ventoy (meme categorie qu'Android Platform Tools : PC deja demarre, telephone cible).
Rescuezilla	https://github.com/rescuezilla/rescuezilla/releases/download/2.6.2/rescuezilla-2.6.2-64bit.noble.iso	285db0af83213e2297490ca1cfd74ecd607c3b0a2f1d14e11a8412c0b71eea50		none	GPL-3.0 (rescuezilla/rescuezilla sur GitHub), fork de Clonezilla avec interface graphique. Base Ubuntu 24.04 LTS (variante "noble") choisie parmi les 4 variantes de codename proposees par la release pour son support materiel long terme, plutot que les codenames plus recents et moins eprouves. SHA-256 calcule localement apres telechargement direct GitHub cette session (aucune somme publiee separement par le projet pour cette release). ISO volumineuse (~1,5 Go) : evaluer l'espace disponible sur la cle avant --fetch disk-clone si Dr.Web LiveDisk (malware) est deja present.
IPED	https://github.com/sepinf-inc/IPED/releases/download/4.3.1/IPED-4.3.1_and_java_plugins.zip	e8ee71e7e2e41a770b521bfbaabf0cf0b88add5febff27c5a5ad375248cfef8e		none	Plateforme forensique open source de la Police Federale Bresilienne (sepinf-inc/IPED sur GitHub, GPLv3 avec permission additionnelle GPLv3 §7 pour lier The Sleuthkit — GitHub l'affiche a tort "Other/NOASSERTION" a cause de cette clause additionnelle, le texte de base reste GPLv3). Traite RAW/DD/E01/EX01/VHD/VHDX/VMDK/AFF/ISO/AD1/UFDR, indexe/recherche/carve/OCR/detection chiffrement. Projet tres actif (dernier commit a 2 jours de la verification). Archive volumineuse (~750 Mo, inclut un JRE embarque — confirme cette session, pas de dependance Java separee a installer). SHA-256 calcule localement apres telechargement direct GitHub cette session (aucune somme publiee separement par le projet).
Antivirus Live CD	https://sourceforge.net/projects/antiviruslivecd/files/AntivirusLiveCD-52.0-1.5.2.iso/download	4dec4b4e53472fc0f6d0fa3e9b6be3588e8ec9d36a3bb284eb6a2f64080ef1bc		none	Distribution Linux legere (fork 4MLinux, GPL-3.0) qui embarque ClamAV et monte automatiquement les partitions detectees pour un scan a la volee — alternative "boot -> scan" plus rapide que SystemRescue pour un technicien qui veut juste lancer un antivirus hors-ligne sans naviguer un shell. SHA-256 calcule localement apres telechargement depuis SourceForge (miroir officiel du projet).
Ophcrack	https://sourceforge.net/projects/ophcrack/files/ophcrack/3.8.0/ophcrack-3.8.0-bin.zip/download	36a35b2f84fe4ebc4652776abb55256f371998d8044253d062858e7ed77545db		none	Cassage de mots de passe Windows par tables arc-en-ciel (GPL-2.0, ophcrack.sourceforge.io) — approche differente de chntpw (edition directe de la ruche SAM) : verification croisee utile quand l'un des deux echoue. Binaires x86/x64 portables verifies dans l'archive (ophcrack.exe, dates 2018 — derniere version stable connue, projet plus maintenu depuis mais toujours fonctionnel et reference dans ce domaine). SHA-256 calcule localement apres telechargement depuis SourceForge. Meme reserve legale que documentee dans sonar_profile_caveat pour le profil password-reset. Windows uniquement.
WereSync	https://github.com/DonyorM/weresync/releases/download/v1.1.5/weresync_1.1.5-1_all.deb	ede0803904134b07723d416d5c14fb7547e80b7418cd7c959d1f7a640feb6653		none	Clone incrementiel de disques Linux (Apache-2.0), produit un clone bootable avec mise a jour automatique de fstab/bootloader — complementaire a Clonezilla (plus generaliste) pour une migration de systeme Linux specifiquement. Paquet .deb publie sur la release officielle GitHub (meme schema d'extraction que ClamAV .deb de ce manifeste : 'ar x weresync*.deb && tar xf data.tar.*'). CORRIGE 2026-09-23 : une premiere version de cette ligne affirmait a tort une signature GPG (.asc) sur ce .deb — verifie en re-listant les assets de la release : seuls WereSync-1.1.5.tar.gz/.whl/.egg (le tarball source et les paquets Python, PAS le .deb) ont un .asc associe. SHA-256 calcule localement sur le .deb, sans signature amont, comme plusieurs autres lignes de ce manifeste (TestDisk, Manjaro, CAINE). Outil Python (necessite python3 sur l'environnement cible, non garanti provisionne par defaut sur SystemRescue — a verifier avant deploiement). Derniere activite du depot 2022-12 : projet ralenti mais pas signale abandonne par son auteur.
Rizin	https://github.com/rizinorg/rizin/releases/download/v0.9.1/rizin-windows-static-v0.9.1.zip	2d14e0a6ecba1196dcd742d63de83bbaffed2a7a78ef5a0a9b4e92a0f73d1d28		none	Analyse/desassemblage/edition hexadecimale scriptable (LGPL-3.0, fork de radare2 oriente utilisabilite, rizinorg/rizin sur GitHub). Build Windows "static" choisi plutot que "shared" : aucune DLL externe a fournir a cote, coherent avec l'usage portable WinPE de ce manifeste. SHA-256 calcule localement apres telechargement direct GitHub cette session (aucune somme publiee separement). Public restreint : techniciens formes au reverse engineering/analyse binaire, pas un outil de depannage courant — non rattache a un profil de depannage SONAR (comme IPED ci-dessus), documente ici pour reference/fetch a la demande.
FETCH_EOF
)"

# sonar_fetch_manifest_lookup TOOL -> la ligne TSV complète, ou échec (rc 1)
# si l'outil n'a pas d'entrée (cas normal pour un outil fourni par un autre,
# ex. GParted est inclus dans l'ISO SystemRescue, pas téléchargé seul).
sonar_fetch_manifest_lookup() {
    local tool="$1"
    awk -F'\t' -v t="$tool" 'NR>1 && $1==t {print; found=1} END{exit !found}' <<<"${SONAR_FETCH_MANIFEST_TSV}"
}

SONAR_FETCH_MANIFEST_SEAL_FILE="${SONAR_FETCH_MANIFEST_SEAL_FILE:-${SONAR_SECURITY_DIR}/Vault/fetch_manifest.hmac}"

sonar_fetch_manifest_hmac() {
    sonar_build_secret_exists || return 1
    sonar_hmac_sha256_file "${SONAR_BUILD_SECRET_FILE}" "${SONAR_FETCH_MANIFEST_TSV}"
}

sonar_fetch_manifest_seal() {
    sonar_require_role VAULT || return 1
    sonar_ensure_build_secret || { echo "[SONAR][ERROR] Impossible de générer/lire le secret de build." >&2; return 1; }
    mkdir -p "$(dirname "${SONAR_FETCH_MANIFEST_SEAL_FILE}")"
    local hmac
    hmac="$(sonar_fetch_manifest_hmac)" || { echo "[SONAR] Échec du calcul HMAC." >&2; return 1; }
    printf '%s\t%s\t%s\n' "$(sonar_iso_now)" "${SONAR_ROLE}" "${hmac}" > "${SONAR_FETCH_MANIFEST_SEAL_FILE}"
    chmod 600 "${SONAR_FETCH_MANIFEST_SEAL_FILE}" 2>/dev/null || true
    sonar_audit "FETCH_MANIFEST_SEALED" "hmac=${hmac}"
    echo "[SONAR] Manifeste de téléchargement scellé: ${SONAR_FETCH_MANIFEST_SEAL_FILE}"
}

# sonar_fetch_manifest_seal_ok -> 0 scellé et conforme, 1 modifié depuis le
# scellement, 2 jamais scellé sur cette machine. Pas de garde de rôle : la
# LECTURE d'un scellé existant est une vérification, pas une escalade — seule
# sa CRÉATION (sonar_fetch_manifest_seal ci-dessus) exige le rôle VAULT.
sonar_fetch_manifest_seal_ok() {
    [[ -s "${SONAR_FETCH_MANIFEST_SEAL_FILE}" ]] || return 2
    sonar_build_secret_exists || return 2
    local sealed_hmac current_hmac
    sealed_hmac="$(awk -F'\t' '{print $NF}' "${SONAR_FETCH_MANIFEST_SEAL_FILE}")"
    current_hmac="$(sonar_fetch_manifest_hmac)" || return 2
    [[ "${sealed_hmac}" == "${current_hmac}" ]]
}

sonar_fetch_manifest_verify_seal() {
    local rc=0
    sonar_fetch_manifest_seal_ok || rc=$?
    case "$rc" in
        0) echo "[SONAR] Manifeste de téléchargement conforme au scellé."; sonar_audit "FETCH_MANIFEST_SEAL_VERIFIED" "status=MATCH" ;;
        1) echo "[SONAR][ALERTE] Le manifeste de téléchargement a changé depuis son scellement." >&2; sonar_audit "FETCH_MANIFEST_SEAL_VERIFIED" "status=MISMATCH" ;;
        *) echo "[SONAR] Aucun scellé trouvé ; exécutez --fetch-manifest-seal (rôle VAULT) d'abord." >&2 ;;
    esac
    return "$rc"
}

# sonar_fetch_sha256_matches FILE EXPECTED -> vrai si le SHA-256 de FILE
# correspond (comparaison insensible à la casse). Pas de réseau — testable
# hors-ligne par --self-test.
sonar_fetch_sha256_matches() {
    local file="$1" expected="$2" actual
    [[ -f "$file" ]] || return 2
    actual="$(sha256_final "$file" 2>/dev/null)" || return 2
    [[ "${actual,,}" == "${expected,,}" ]]
}

SONAR_FETCH_REPORT_DIR="${SONAR_FETCH_REPORT_DIR:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/FETCH}"
SONAR_FETCH_REPORT="${SONAR_FETCH_REPORT:-${SONAR_FETCH_REPORT_DIR}/MANIFEST_FETCH.tsv}"

# ---------------------------------------------------------------------------
# Post-traitement de --fetch : rendre l'outil UTILISABLE, pas seulement telecharge.
#
# --fetch verifie le SHA-256 d'une ARCHIVE ; encore faut-il que le technicien n'ait
# pas a la decompresser a la main. sonar_fetch_postprocess est appele UNIQUEMENT sur
# une archive deja verifiee (SHA-256 conforme), et ne modifie jamais l'archive. Il
# renseigne SONAR_FETCH_STATE, ecrit dans le rapport --fetch :
#   READY            fichier directement utilisable (.iso, .exe...)
#   EXTRACTED        archive decompressee dans Portable/<Outil>/
#   ISO_EXTRACTED    l'ISO contenue dans l'archive est dans ISO/Fetched/ (Memtest86+, chntpw)
#   WRAPPED          extrait + lanceurs poses (ClamAV : LD_LIBRARY_PATH, base de signatures)
#   SOURCE_ONLY      archive de CODE SOURCE : rien d'executable sans compilation -> dit clairement
#   MANUAL           extraction impossible ici (outil manquant) : la raison est affichee
# Extraction sure : les noms d'entrees sont controles AVANT (pas de chemin absolu ni de
# composant ".."), aucun lien symbolique ne peut sortir du dossier, jamais de proprietaire
# ni de droits d'origine (--no-same-owner).
# ---------------------------------------------------------------------------
SONAR_FETCH_STATE=""
SONAR_FETCH_ATTENTION=()

# nom de dossier sur : lettres, chiffres, point, tiret, souligne
sonar_fetch_safe_name() {
    local n
    n="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | sed 's/^[._]*//; s/_*$//')"
    printf '%s' "${n:-outil}"
}

# refuse une liste de noms d'entrees (stdin) contenant un chemin absolu ou "..".
sonar_fetch_names_safe() {
    ! awk '/^\// || /(^|\/)\.\.(\/|$)/ || /\\/ {bad=1} END {exit !bad}'
}

# sonar_fetch_extract ARCHIVE DEST -> 0 ok ; 1 refuse/echec ; 2 outil manquant
sonar_fetch_extract() {
    local f="$1" d="$2" names lnk
    mkdir -p "$d" || return 1
    case "$f" in
        *.zip)
            command -v unzip >/dev/null 2>&1 || { echo "[SONAR] unzip absent : impossible de decompresser $(basename "$f")." >&2; return 2; }
            names="$(unzip -Z1 "$f" 2>/dev/null)" || return 1
            sonar_fetch_names_safe <<<"$names" || { echo "[SONAR][ERROR] $(basename "$f") : nom d'entree dangereux (chemin absolu ou '..') — extraction REFUSEE." >&2; return 1; }
            unzip -q -o "$f" -d "$d" >/dev/null || return 1 ;;
        *.tar.bz2|*.tar.gz|*.tgz|*.tar.xz|*.tar.lz|*.tar)
            command -v tar >/dev/null 2>&1 || return 2
            # Le decompresseur est choisi explicitement : GNU tar appelle lbzip2 pour .bz2 sur certaines
            # distributions, absent d'un systeme minimal (constate sur l'archive TestDisk reelle : echec
            # generique « extraction refusee »). Sans decompresseur dedie, repli sur 7z si present.
            local dec="" c viaz=false
            case "$f" in
                *.tar.bz2) for c in bzip2 lbzip2 pbzip2; do command -v "$c" >/dev/null 2>&1 && { dec="$c"; break; }; done; [[ -n "$dec" ]] || dec="bzip2" ;;
                *.tar.gz|*.tgz) dec="gzip" ;;
                *.tar.xz) dec="xz" ;;
                *.tar.lz) dec="lzip" ;;
            esac
            if [[ -n "$dec" ]] && ! command -v "$dec" >/dev/null 2>&1; then
                if command -v 7z >/dev/null 2>&1; then viaz=true
                else echo "[SONAR] ${dec} absent (et 7z aussi) : impossible de decompresser $(basename "$f") — installez ${dec}." >&2; return 2; fi
            fi
            if $viaz; then
                names="$(7z x -so "$f" 2>/dev/null | tar -t 2>/dev/null)" || return 1
            else
                names="$(tar ${dec:+-I "$dec"} -tf "$f" 2>/dev/null)" || return 1
            fi
            sonar_fetch_names_safe <<<"$names" || { echo "[SONAR][ERROR] $(basename "$f") : nom d'entree dangereux — extraction REFUSEE." >&2; return 1; }
            if $viaz; then 7z x -so "$f" 2>/dev/null | tar -x -C "$d" --no-same-owner --no-same-permissions || return 1
            else tar ${dec:+-I "$dec"} -xf "$f" -C "$d" --no-same-owner --no-same-permissions || return 1; fi ;;
        *.deb)
            if command -v dpkg-deb >/dev/null 2>&1; then
                names="$(dpkg-deb -c "$f" 2>/dev/null | awk '{print $6}' | sed 's|^\./||')" || return 1
                sonar_fetch_names_safe <<<"$names" || { echo "[SONAR][ERROR] $(basename "$f") : nom d'entree dangereux — extraction REFUSEE." >&2; return 1; }
                dpkg-deb -x "$f" "$d" || return 1
            elif command -v ar >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
                ( cd "$d" && ar p "$f" data.tar.gz 2>/dev/null | tar -xz --no-same-owner ) || return 1
            else
                echo "[SONAR] dpkg-deb/ar absents : impossible d'extraire $(basename "$f")." >&2; return 2
            fi ;;
        *) return 1 ;;
    esac
    # aucun lien symbolique ne doit pointer hors du dossier d'extraction
    while IFS= read -r lnk; do
        [[ -n "$lnk" ]] || continue
        case "$(readlink -m "$lnk" 2>/dev/null)" in
            "$(cd "$d" && pwd -P)"/*) ;;
            *) rm -f "$lnk"; echo "[SONAR] lien symbolique sortant supprime : ${lnk#"$d"/}" >&2 ;;
        esac
    done < <(find "$d" -type l 2>/dev/null)
    return 0
}

# ClamAV (.deb officiel, prefixe /usr/local) : on garde bin/, lib/*.so*, etc/certs, on retire
# en-tetes, bibliotheques statiques et pages de man (459 Mo -> quelques dizaines), puis on pose
# des lanceurs qui fixent LD_LIBRARY_PATH et le dossier de signatures.
sonar_fetch_wrap_clamav() {
    local d="$1" root="$1/usr/local" bin
    [[ -x "$root/bin/clamscan" && -x "$root/bin/freshclam" ]] || { echo "[SONAR][ERROR] ClamAV : clamscan/freshclam absents de l'extraction." >&2; return 1; }
    rm -rf "$root/include" "$root/lib/pkgconfig" "$root/share/man" "$root/share/doc" "$root"/lib/*.a
    mkdir -p "$d/db"
    cat > "$d/sonar-clamscan.sh" <<'CLAM_EOF'
#!/bin/sh
# Lance clamscan depuis cette copie portable : bibliotheques et signatures locales.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/usr/local"
have=0
for f in "$HERE"/db/*.cvd "$HERE"/db/*.cld; do [ -e "$f" ] && have=1; done
if [ "$have" -ne 1 ]; then
    echo "Aucune base de signatures dans $HERE/db : lancez d'abord sonar-freshclam.sh (Internet requis)." >&2
    exit 2
fi
LD_LIBRARY_PATH="$ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "$ROOT/bin/clamscan" -d "$HERE/db" "$@"
CLAM_EOF
    cat > "$d/sonar-freshclam.sh" <<'CLAM_EOF'
#!/bin/sh
# Met a jour les signatures ClamAV dans ./db (Internet requis ; ~300 Mo la premiere fois).
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/usr/local"
CONF="$(mktemp)"
trap 'rm -f "$CONF"' EXIT
printf 'DatabaseDirectory %s\nDatabaseMirror database.clamav.net\nCompressLocalDatabase no\n' "$HERE/db" > "$CONF"
LD_LIBRARY_PATH="$ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "$ROOT/bin/freshclam" --config-file="$CONF" "$@"
CLAM_EOF
    chmod +x "$d/sonar-clamscan.sh" "$d/sonar-freshclam.sh" 2>/dev/null || true
    if [[ "${SONAR_FETCH_CLAMAV_DB:-0}" == "1" ]]; then
        echo "[SONAR] ClamAV : telechargement des signatures (SONAR_FETCH_CLAMAV_DB=1)..."
        sh "$d/sonar-freshclam.sh" >/dev/null 2>&1 && echo "[SONAR] ClamAV : signatures installees dans ${d}/db." \
            || echo "[SONAR] ClamAV : freshclam a echoue (reseau ?) — relancez sonar-freshclam.sh avant usage." >&2
    fi
    return 0
}

# ClamAV pour Windows/WinPE (.zip officiel Cisco-Talos, meme version/cle que sonar_fetch_wrap_clamav) :
# l'archive complete (225 Mo) contient aussi clamd/clambc/clamsubmit (non utilises ici), des .pdb de
# debogage (467 Mo) et des en-tetes/.lib de developpement (293 Mo). On aplatit le sous-dossier versionne
# (ex. clamav-1.5.4.win.x64/) vers la racine — chemin de lanceur stable d'une version a l'autre — puis on
# elague pour ne garder que ce qui sert a un scan hors ligne : clamscan.exe/sigtool.exe/freshclam.exe, les
# DLL requises (deja bundlees avec le zip, y compris vcruntime/msvcp — aucun Redistribuable VC++ a
# installer separement), certs/ (TLS pour freshclam) et conf_examples/. Verifie sous WinPE 26100 (VM) :
# clamscan.exe se lance sans erreur de DLL manquante, charge une base de signatures et detecte
# correctement (voir CHANGELOG).
sonar_fetch_wrap_clamav_win() {
    local d="$1" sub
    sub="$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
    if [[ -n "$sub" && -f "$sub/clamscan.exe" ]]; then
        ( shopt -s dotglob 2>/dev/null; mv -f "$sub"/* "$d"/ ) 2>/dev/null
        rmdir "$sub" 2>/dev/null
    fi
    [[ -f "$d/clamscan.exe" ]] || { echo "[SONAR][ERROR] ClamAV (Windows) : clamscan.exe absent de l'extraction." >&2; return 1; }
    rm -f "$d"/*.pdb "$d"/clamd.exe "$d"/clamdscan.exe "$d"/clamdtop.exe "$d"/clambc.exe "$d"/clamsubmit.exe "$d"/clamconf.exe "$d"/*.lib
    rm -rf "$d/include"
    mkdir -p "$d/db"
    cat > "$d/sonar-clamscan.cmd" <<'CLAMWIN_EOF'
@echo off
rem Lance clamscan.exe depuis cette copie portable (DLL et base de signatures locales, %~dp0). Refuse de
rem tourner sans base de signatures : un scan "0 signature" serait silencieusement vide, plus dangereux
rem qu'un refus clair (meme logique que sonar-clamscan.sh sous Linux).
setlocal enabledelayedexpansion
set "HERE=%~dp0"
set HAVE=0
if exist "%HERE%db\*.cvd" set HAVE=1
if exist "%HERE%db\*.cld" set HAVE=1
if "%HAVE%"=="0" (
    echo Aucune base de signatures dans %HERE%db : lancez d'abord sonar-freshclam.cmd ^(Internet requis^).
    exit /b 2
)
"%HERE%clamscan.exe" -d "%HERE%db" %*
exit /b %errorlevel%
CLAMWIN_EOF
    cat > "$d/sonar-freshclam.cmd" <<'CLAMWIN_EOF'
@echo off
rem Met a jour les signatures ClamAV dans %~dp0db (Internet requis ; ~300 Mo la premiere fois).
setlocal enabledelayedexpansion
set "HERE=%~dp0"
set "CONF=%TEMP%\sonar_freshclam_%RANDOM%.conf"
> "%CONF%" echo DatabaseDirectory %HERE%db
>> "%CONF%" echo DatabaseMirror database.clamav.net
>> "%CONF%" echo CompressLocalDatabase no
"%HERE%freshclam.exe" --config-file="%CONF%" %*
set "RC=%errorlevel%"
del "%CONF%" >nul 2>&1
exit /b %RC%
CLAMWIN_EOF
    if [[ "${SONAR_FETCH_CLAMAV_DB:-0}" == "1" ]]; then
        # freshclam.exe est un binaire Windows : ne peut pas etre execute depuis cet hote de build
        # (Linux/WSL). Signatures a recuperer plus tard, depuis Windows ou WinPE, via sonar-freshclam.cmd.
        echo "[SONAR] ClamAV (Windows) : freshclam.exe ne peut pas etre lance depuis cet hote (binaire Windows) — executez sonar-freshclam.cmd depuis Windows ou WinPE pour installer les signatures." >&2
    fi
    return 0
}

# sonar_fetch_postprocess TOOL ARCHIVE SHA256  -> jamais fatal ; renseigne SONAR_FETCH_STATE
sonar_fetch_postprocess() {
    local tool="$1" f="$2" sha="$3" base safe dest tmp names isos others rc
    base="$(basename "$f")"; safe="$(sonar_fetch_safe_name "$tool")"
    SONAR_FETCH_STATE="READY"
    case "$base" in
        *.iso|*.exe|*.msi|*.img) return 0 ;;
        *.tar.lz|*.tar.lzma)
            # archive de code source (ddrescue) : meme decompressee, rien d'executable sans compilation
            SONAR_FETCH_STATE="SOURCE_ONLY"
            echo "[SONAR] ${tool} : archive de CODE SOURCE (${base}), pas un binaire — rien d'executable sans compilation (make + g++). Utilisez l'outil deja present dans l'ISO du profil (ex. SystemRescue : ddrescue) ou compilez." >&2
            return 0 ;;
        *.zip|*.tar.bz2|*.tar.gz|*.tgz|*.tar.xz|*.deb)
            :
            ;;
        *) return 0 ;;
    esac
    # ZIP contenant une ISO (Memtest86+, chntpw) : c'est l'ISO qui va dans ISO/
    if [[ "$base" == *.zip ]] && command -v unzip >/dev/null 2>&1; then
        names="$(unzip -Z1 "$f" 2>/dev/null || true)"
        isos="$(grep -Ei '\.iso$' <<<"$names" || true)"
        others="$(grep -Evi '\.iso$|(^|/)$|\.(txt|md|sig|asc|sha256|sha1|md5|nfo)$' <<<"$names" || true)"
        if [[ -n "$isos" && -z "$others" ]]; then
            tmp="$(mktemp -d)"
            if sonar_fetch_extract "$f" "$tmp"; then
                mkdir -p "${ISO_SOURCE_DIR}/Fetched"
                while IFS= read -r iso; do
                    [[ -n "$iso" ]] || continue
                    mv -f "$tmp/$iso" "${ISO_SOURCE_DIR}/Fetched/$(basename "$iso")"
                    echo "[SONAR] ${tool} : ISO extraite -> ${ISO_SOURCE_DIR}/Fetched/$(basename "$iso")"
                done <<<"$isos"
                SONAR_FETCH_STATE="ISO_EXTRACTED"
            else
                SONAR_FETCH_STATE="MANUAL"
            fi
            rm -rf "$tmp"; return 0
        fi
    fi
    dest="${PORTABLE_SOURCE_DIR}/${safe}"
    if [[ -f "$dest/.sonar_fetch_sha256" && "$(cat "$dest/.sonar_fetch_sha256" 2>/dev/null)" == "$sha" ]]; then
        SONAR_FETCH_STATE="EXTRACTED"; [[ -f "$dest/sonar-clamscan.sh" || -f "$dest/sonar-clamscan.cmd" ]] && SONAR_FETCH_STATE="WRAPPED"
        echo "[SONAR] ${tool} : deja extrait -> ${dest}"; return 0
    fi
    rm -rf "$dest"
    rc=0; sonar_fetch_extract "$f" "$dest" || rc=$?
    if [[ $rc -ne 0 ]]; then
        rm -rf "$dest"; SONAR_FETCH_STATE="MANUAL"
        [[ $rc -eq 1 ]] && echo "[SONAR][ERROR] ${tool} : extraction refusee ou echouee (${base})." >&2
        return 0
    fi
    if [[ "$base" == *.deb && "$tool" == "ClamAV" ]]; then
        if sonar_fetch_wrap_clamav "$dest"; then SONAR_FETCH_STATE="WRAPPED"; else rm -rf "$dest"; SONAR_FETCH_STATE="MANUAL"; return 0; fi
    elif [[ "$base" == *.zip && "$tool" == "ClamAV-Windows" ]]; then
        if sonar_fetch_wrap_clamav_win "$dest"; then SONAR_FETCH_STATE="WRAPPED"; else rm -rf "$dest"; SONAR_FETCH_STATE="MANUAL"; return 0; fi
    else
        SONAR_FETCH_STATE="EXTRACTED"
    fi
    printf '%s' "$sha" > "$dest/.sonar_fetch_sha256"
    echo "[SONAR] ${tool} : pret -> ${dest} (${SONAR_FETCH_STATE})"
    return 0
}

# sonar_fetch_one_tool TOOL -> 0 téléchargé+vérifié, 1 échec (téléchargement
# ou SHA-256), 3 pas d'entrée manifeste pour cet outil (fourni autrement,
# ex. bundlé dans une autre ISO du même profil — pas une erreur).
sonar_fetch_one_tool() {
    local tool="$1" row url expected_sha256 url_clean base ext dest_dir dest_file actual_sha256
    row="$(sonar_fetch_manifest_lookup "$tool")" || {
        echo "[SONAR] '${tool}' : pas d'entrée de téléchargement séparée (fourni par un autre outil du profil, ex. inclus dans une ISO déjà récupérée)."
        return 3
    }
    IFS=$'\t' read -r _ url expected_sha256 _ _ _ <<< "$row"
    [[ -n "$url" && -n "$expected_sha256" ]] || { echo "[SONAR][ERROR] Entrée de manifeste incomplète pour '${tool}'." >&2; return 1; }
    url_clean="${url%/download}"
    base="${url_clean##*/}"
    ext="${base##*.}"
    case "$ext" in
        iso) dest_dir="${ISO_SOURCE_DIR}/Fetched" ;;
        *) dest_dir="${PORTABLE_SOURCE_DIR}/Fetched" ;;
    esac
    mkdir -p "$dest_dir"
    dest_file="${dest_dir}/${base}"
    # Idempotent : si le fichier est deja present ET que son SHA-256 est
    # deja correct, on ne re-telecharge rien. Observe en pratique : sans
    # ce garde-fou, --fetch sur un profil incluant un gros outil deja
    # present (SystemRescue, 1.3 Go) le retelechargeait integralement a
    # chaque execution, meme deja valide.
    if [[ -f "$dest_file" ]] && sonar_fetch_sha256_matches "${dest_file}" "${expected_sha256}"; then
        echo "[SONAR] OK: ${tool} deja present et verifie (SHA-256 conforme) -> ${dest_file}"
        sonar_fetch_postprocess "$tool" "$dest_file" "$expected_sha256"
        case "$SONAR_FETCH_STATE" in MANUAL|SOURCE_ONLY) SONAR_FETCH_ATTENTION+=("${tool}:${SONAR_FETCH_STATE}") ;; esac
        return 0
    fi
    echo "[SONAR] Téléchargement: ${tool} <- ${url}"
    # --connect-timeout/--max-time : sans eux, un serveur qui accepte la
    # connexion puis ne repond plus (pending indefiniment) bloque --fetch
    # sans aucun message, sur un reseau instable — deja observe en
    # pratique cette session (voir CHANGELOG.md). 3600s (1h) laisse le
    # temps aux plus gros outils du manifeste (SystemRescue, ~1,3 Go) sur
    # une connexion lente, sans bloquer indefiniment sur un serveur mort.
    if ! curl -fL --connect-timeout 20 --max-time 3600 --retry 3 --retry-delay 5 -C - -o "${dest_file}.part" "$url"; then
        rm -f "${dest_file}.part"
        echo "[SONAR][ERROR] Échec du téléchargement: ${tool}" >&2
        sonar_audit "FETCH_DOWNLOAD_FAILED" "tool=${tool};url=${url}"
        return 1
    fi
    mv -f "${dest_file}.part" "${dest_file}"
    if ! sonar_fetch_sha256_matches "${dest_file}" "${expected_sha256}"; then
        actual_sha256="$(sha256_final "${dest_file}" 2>/dev/null || echo indisponible)"
        rm -f "${dest_file}"
        echo "[SONAR][ERROR] SHA-256 NE CORRESPOND PAS pour ${tool} — fichier supprimé. Attendu=${expected_sha256} Obtenu=${actual_sha256}" >&2
        sonar_audit "FETCH_HASH_MISMATCH" "tool=${tool};expected=${expected_sha256};actual=${actual_sha256}"
        return 1
    fi
    echo "[SONAR] OK: ${tool} vérifié (SHA-256 conforme) -> ${dest_file}"
    # archive verifiee => on peut la rendre utilisable (jamais fatal)
    sonar_fetch_postprocess "$tool" "$dest_file" "$expected_sha256"
    case "$SONAR_FETCH_STATE" in MANUAL|SOURCE_ONLY) SONAR_FETCH_ATTENTION+=("${tool}:${SONAR_FETCH_STATE}") ;; esac
    mkdir -p "${SONAR_FETCH_REPORT_DIR}"
    [[ -s "${SONAR_FETCH_REPORT}" ]] || printf 'TOOL\tURL\tSHA256\tFETCHED_AT\tDEST\tSTATE\n' > "${SONAR_FETCH_REPORT}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$tool" "$url" "$expected_sha256" "$(sonar_iso_now)" "$dest_file" "$SONAR_FETCH_STATE" >> "${SONAR_FETCH_REPORT}"
    sonar_audit "FETCH_VERIFIED" "tool=${tool};sha256=${expected_sha256};dest=${dest_file};state=${SONAR_FETCH_STATE}"
    return 0
}

sonar_fetch_profile() {
    local profile="${1:-}" seal_rc=0
    sonar_profile_scenario "$profile" >/dev/null || {
        echo "[SONAR][ERROR] Profil inconnu: '${profile}'. Profils disponibles: $(sonar_profile_names)" >&2
        return 2
    }
    sonar_fetch_manifest_seal_ok || seal_rc=$?
    if [[ "$seal_rc" -ne 0 ]]; then
        echo "[SONAR][ERROR] --fetch refuse : manifeste de téléchargement non scellé ou modifié (code ${seal_rc})." >&2
        echo "[SONAR] Exécutez --fetch-manifest-seal (rôle VAULT) pour valider ce manifeste avant toute utilisation de --fetch." >&2
        sonar_audit "FETCH_REFUSED" "profile=${profile};reason=unsealed_manifest;seal_rc=${seal_rc}"
        return 1
    fi
    command -v curl >/dev/null 2>&1 || { echo "[SONAR][ERROR] curl requis pour --fetch." >&2; return 127; }
    local tools tool rc ok=0 fail=0 skip=0
    tools="$(sonar_profile_tools "$profile" | awk -F'\t' '{print $1}')"
    while IFS= read -r tool; do
        [[ -z "$tool" ]] && continue
        rc=0
        sonar_fetch_one_tool "$tool" || rc=$?
        case "$rc" in
            0) ok=$((ok+1)) ;;
            3) skip=$((skip+1)) ;;
            *) fail=$((fail+1)) ;;
        esac
    done <<< "$tools"
    echo "[SONAR] Profil '${profile}' : ${ok} outil(s) vérifié(s), ${fail} échec(s), ${skip} fourni(s) autrement."
    if [[ ${#SONAR_FETCH_ATTENTION[@]} -gt 0 ]]; then
        echo "[SONAR] ATTENTION — non directement utilisable(s) : ${SONAR_FETCH_ATTENTION[*]} (MANUAL = extraction impossible ici, SOURCE_ONLY = code source à compiler)."
    fi
    sonar_audit "FETCH_PROFILE_DONE" "profile=${profile};ok=${ok};fail=${fail};skip=${skip}"
    [[ "$fail" -eq 0 ]]
}

# sonar_field_pin_set NIVEAU PIN [PROFILS]: définit (rôle VAULT) un PIN
# de terrain associé à un NIVEAU d'accréditation et à la liste de PROFILS
# qu'il déverrouille dans SONAR Field — "ALL" (défaut) ou une liste
# séparée par des virgules parmi boot-repair/data-recovery/malware/
# disk-clone/password-reset/full. Rejouer avec le même NIVEAU met à jour
# sa ligne (PIN et/ou profils) sans toucher aux autres niveaux déjà
# définis — copié en bloc dans MANIFEST/FIELD_PINS.tsv par
# copy_payload_final si ce fichier existe.
sonar_field_pin_set() {
    local niveau profils
    niveau="$(sonar_sanitize_value "${1:-}")"
    local pin="${2:-}"
    profils="${3:-ALL}"
    sonar_require_role VAULT || return 1
    [[ -n "$niveau" ]] || { echo "[SONAR][ERROR] Niveau vide refusé." >&2; return 2; }
    [[ -n "$pin" ]] || { echo "[SONAR][ERROR] PIN vide refusé." >&2; return 2; }
    if [[ "${#pin}" -lt 4 ]]; then
        echo "[SONAR][ERROR] PIN trop court (minimum 4 caractères)." >&2
        return 2
    fi
    if [[ "$profils" != "ALL" ]]; then
        local prof bad=""
        local -a prof_arr=()
        IFS=',' read -ra prof_arr <<< "$profils"
        for prof in "${prof_arr[@]}"; do
            sonar_profile_scenario "$prof" >/dev/null || bad="$prof"
        done
        if [[ -n "$bad" ]]; then
            echo "[SONAR][ERROR] Profil inconnu dans la liste: '${bad}'. Profils disponibles: $(sonar_profile_names), ou 'ALL'." >&2
            return 2
        fi
    fi
    mkdir -p "$(dirname "${SONAR_FIELD_PINS_FILE}")"
    local hash tmp
    hash="$(sonar_hash_str "$pin")"
    tmp="$(mktemp)"
    if [[ -s "${SONAR_FIELD_PINS_FILE}" ]]; then
        awk -F'\t' -v n="$niveau" 'BEGIN{OFS="\t"} $1!=n' "${SONAR_FIELD_PINS_FILE}" > "$tmp"
    fi
    printf '%s\t%s\t%s\n' "$niveau" "$hash" "$profils" >> "$tmp"
    mv "$tmp" "${SONAR_FIELD_PINS_FILE}"
    chmod 600 "${SONAR_FIELD_PINS_FILE}" 2>/dev/null || true
    sonar_audit "FIELD_PIN_SET" "niveau=${niveau};profils=${profils}"
    echo "[SONAR] PIN de terrain défini pour le niveau '${niveau}' (profils: ${profils}) — sera copié sur la clé au prochain --disk (MANIFEST/FIELD_PINS.tsv)."
}

# === SONAR AI DRY-RUN REPORT ENGINE V1 ===
SONAR_AI_REPORT_DIR="${SONAR_AI_REPORT_DIR:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/AI_REPORT}"
SONAR_AI_REPORT="${SONAR_AI_REPORT:-${SONAR_AI_REPORT_DIR}/ai_dry_run_report.tsv}"
SONAR_AI_SUMMARY="${SONAR_AI_SUMMARY:-${SONAR_AI_REPORT_DIR}/ai_dry_run_summary.txt}"

sonar_ai_dry_run_report() {
    local queue="${SONAR_QUEUE:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/MANIFEST_AI_QUEUE.tsv}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --queue) [[ $# -ge 2 ]] || { echo "[SONAR] --queue nécessite une valeur." >&2; return 1; }; queue="$2"; shift 2 ;;
            --source) [[ $# -ge 2 ]] || { echo "[SONAR] --source nécessite une valeur." >&2; return 1; }; SONAR_ROOT="$2"; SONAR_AI_REPORT_DIR="${SONAR_ROOT}/SONAR_SOURCE/AI_REPORT"; SONAR_AI_REPORT="${SONAR_AI_REPORT_DIR}/ai_dry_run_report.tsv"; SONAR_AI_SUMMARY="${SONAR_AI_REPORT_DIR}/ai_dry_run_summary.txt"; shift 2 ;;
            *) shift ;;
        esac
    done
    mkdir -p "$SONAR_AI_REPORT_DIR"
    if [[ ! -f "$queue" ]]; then
        sonar_build_ai_queue_from_catalogue || return $?
    fi

    printf 'ID\tNAME\tOS\tARCH\tVERSION\tOFFICIAL_DOMAIN\tSTATUS\tREASON\n' > "$SONAR_AI_REPORT"
    local total=0 auto_os=0 auto_arch=0 auto_domain=0
    local id name os arch version official

    while IFS=$'\t' read -r id name os arch version official; do
        [[ -z "$id" || "$id" == "ID" || "$id" == \#* ]] && continue
        total=$((total+1))
        [[ "$os" == "AUTO" ]] && auto_os=$((auto_os+1))
        [[ "$arch" == "AUTO" ]] && auto_arch=$((auto_arch+1))
        [[ "$official" == "AUTO" ]] && auto_domain=$((auto_domain+1))

        local reason="catalogue_fields_present"
        [[ "$os" == "AUTO" ]] && reason="${reason};os_needs_ai"
        [[ "$arch" == "AUTO" ]] && reason="${reason};arch_needs_ai"
        [[ "$official" == "AUTO" ]] && reason="${reason};official_domain_needs_ai"

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$id" "$name" "$os" "$arch" "$version" "$official" \
          "READY_FOR_AI" "$reason" >> "$SONAR_AI_REPORT"
    done < "$queue"

    {
        echo "SONAR AI DRY-RUN SUMMARY"
        echo "========================="
        echo "Date: $(sonar_iso_now)"
        echo "Catalogue entries: $total"
        echo "OS requiring AI resolution: $auto_os"
        echo "Architecture requiring AI resolution: $auto_arch"
        echo "Official domain requiring AI resolution: $auto_domain"
        echo
        echo "PRE-DOWNLOAD: aucun fichier distant n'a été téléchargé."
        echo "Aucun périphérique bloc n'a été modifié."
        echo "Les résultats IA devront passer la validation Sonar."
    } > "$SONAR_AI_SUMMARY"

    echo "[SONAR] Rapport: $SONAR_AI_REPORT"
    echo "[SONAR] Résumé: $SONAR_AI_SUMMARY"
}

# === SONAR OLLAMA CATALOGUE AUDIT V1 ===
SONAR_OLLAMA_AUDIT_DIR="${SONAR_OLLAMA_AUDIT_DIR:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/OLLAMA_AUDIT}"
SONAR_OLLAMA_AUDIT_REPORT="${SONAR_OLLAMA_AUDIT_REPORT:-${SONAR_OLLAMA_AUDIT_DIR}/ollama_catalogue_audit.tsv}"
SONAR_OLLAMA_AUDIT_SUMMARY="${SONAR_OLLAMA_AUDIT_SUMMARY:-${SONAR_OLLAMA_AUDIT_DIR}/ollama_catalogue_audit_summary.txt}"
SONAR_OLLAMA_MAX_ITEMS="${SONAR_OLLAMA_MAX_ITEMS:-0}"

sonar_ollama_catalogue_audit() {
    local queue="${SONAR_QUEUE:-${SONAR_ROOT:-$(pwd)}/SONAR_SOURCE/MANIFEST_AI_QUEUE.tsv}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --queue) [[ $# -ge 2 ]] || { echo "[SONAR] --queue nécessite une valeur." >&2; return 1; }; queue="$2"; shift 2 ;;
            --source) [[ $# -ge 2 ]] || { echo "[SONAR] --source nécessite une valeur." >&2; return 1; }; SONAR_ROOT="$2"; SONAR_OLLAMA_AUDIT_DIR="${SONAR_ROOT}/SONAR_SOURCE/OLLAMA_AUDIT"; SONAR_OLLAMA_AUDIT_REPORT="${SONAR_OLLAMA_AUDIT_DIR}/ollama_catalogue_audit.tsv"; SONAR_OLLAMA_AUDIT_SUMMARY="${SONAR_OLLAMA_AUDIT_DIR}/ollama_catalogue_audit_summary.txt"; shift 2 ;;
            --model) [[ $# -ge 2 ]] || { echo "[SONAR] --model nécessite une valeur." >&2; return 1; }; SONAR_AI_MODEL="$2"; shift 2 ;;
            --max-items) [[ $# -ge 2 ]] || { echo "[SONAR] --max-items nécessite une valeur." >&2; return 1; }; SONAR_OLLAMA_MAX_ITEMS="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    mkdir -p "$SONAR_OLLAMA_AUDIT_DIR"
    if [[ ! -f "$queue" ]]; then
        sonar_build_ai_queue_from_catalogue || return $?
    fi

    if ! ollama_available; then
        echo "[SONAR] Ollama indisponible sur ${SONAR_AI_URL%%/api/generate}." >&2
        echo "[SONAR] Aucun téléchargement ne sera effectué." >&2
        return 2
    fi

    printf 'ID\tNAME\tOS\tARCH\tVERSION\tOFFICIAL_DOMAIN\tSTATUS\tURL\tSHA256\tCONFIDENCE\tREASON\n' > "$SONAR_OLLAMA_AUDIT_REPORT"
    local total=0 resolved=0 unresolved=0 rejected=0
    local id name os arch version official response json url sha conf source reason

    while IFS=$'\t' read -r id name os arch version official; do
        [[ -z "$id" || "$id" == "ID" || "$id" == \#* ]] && continue
        if (( SONAR_OLLAMA_MAX_ITEMS > 0 && total >= SONAR_OLLAMA_MAX_ITEMS )); then
            break
        fi
        total=$((total+1))

        response="$(ollama_query "Tu es le module de résolution documentaire de Sonar. Pour le logiciel suivant, identifie uniquement des informations vérifiables. N'invente aucune URL ni aucun SHA-256. Ne télécharge rien. Si tu ne peux pas vérifier une donnée, laisse-la vide.
Nom: $name
OS: $os
Architecture: $arch
Version: $version
Domaine officiel attendu: $official
Retourne UNIQUEMENT JSON avec:
{\"name\":\"\",\"version\":\"\",\"os\":\"\",\"arch\":\"\",\"official_domain\":\"\",\"download_url\":\"\",\"sha256\":\"\",\"sha256_source_url\":\"\",\"source_type\":\"official|vendor|unknown\",\"confidence\":\"high|medium|low\"}" )" || {
            printf '%s\t%s\t%s\t%s\t%s\t%s\tOLLAMA_ERROR\t\t\tlow\tollama_query_failed\n' "$id" "$name" "$os" "$arch" "$version" "$official" >> "$SONAR_OLLAMA_AUDIT_REPORT"
            rejected=$((rejected+1)); continue
        }

        json="$(printf '%s' "$response" | extract_json)" || {
            printf '%s\t%s\t%s\t%s\t%s\t%s\tINVALID_JSON\t\t\tlow\tmodel_return_not_json\n' "$id" "$name" "$os" "$arch" "$version" "$official" >> "$SONAR_OLLAMA_AUDIT_REPORT"
            rejected=$((rejected+1)); continue
        }

        url="$(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("download_url",""))' <<<"$json")"
        sha="$(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("sha256",""))' <<<"$json")"
        conf="$(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("confidence","low"))' <<<"$json")"
        source="$(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("source_type","unknown"))' <<<"$json")"
        local ro osx arx dom
        ro="$(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("os",""))' <<<"$json")"
        osx="$(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("arch",""))' <<<"$json")"
        arx="$(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("official_domain",""))' <<<"$json")"

        reason=""
        status="NEEDS_REVIEW"
        if [[ -z "$url" || ! "$url" =~ ^https:// ]]; then reason="missing_or_non_https_url"
        elif [[ -z "$sha" || ! "$sha" =~ ^[A-Fa-f0-9]{64}$ ]]; then reason="missing_or_invalid_sha256"
        elif [[ "$conf" != "high" ]]; then reason="confidence_not_high"
        elif [[ "$source" != "official" && "$source" != "vendor" ]]; then reason="source_not_official_or_vendor"
        else status="AI_RESOLVED"; reason="metadata_and_hash_shape_valid"
        fi

        if [[ "$status" == "AI_RESOLVED" ]]; then resolved=$((resolved+1)); else unresolved=$((unresolved+1)); fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$id" "$name" "$ro" "$osx" "$version" "$arx" "$status" "$url" "$sha" "$conf" "$reason" >> "$SONAR_OLLAMA_AUDIT_REPORT"
    done < "$queue"

    {
        echo "SONAR OLLAMA CATALOGUE AUDIT"
        echo "============================"
        echo "Date: $(sonar_iso_now)"
        echo "Model: $SONAR_AI_MODEL"
        echo "Items processed: $total"
        echo "AI-resolved candidates: $resolved"
        echo "Needs review / rejected: $unresolved"
        echo
        echo "IMPORTANT: this stage is discovery/audit only."
        echo "No download URL was fetched."
        echo "No file was installed."
        echo "No block device was modified."
        echo "AI_RESOLVED means the response passed structural/policy checks only;"
        echo "the SHA-256 still must be verified against the actual downloaded file."
    } > "$SONAR_OLLAMA_AUDIT_SUMMARY"

    echo "[SONAR] Audit Ollama: $SONAR_OLLAMA_AUDIT_REPORT"
    echo "[SONAR] Résumé: $SONAR_OLLAMA_AUDIT_SUMMARY"
}

# === SONAR STRUCTURAL SELF-AUDIT V1 ===
sonar_structural_self_audit() {
    local self="${BASH_SOURCE[0]}" errors=0
    echo "SONAR STRUCTURAL SELF-AUDIT"
    echo "==========================="
    echo "File: $self"
    echo "SHA256: $(sonar_hash "$self" 2>/dev/null || echo indisponible)"
    local d m mf
    d=$(grep -c '^# === SONAR FINAL COMMAND DISPATCH ===$' "$self" || true)
    m=$(grep -c '^main_final() {' "$self" || true)
    mf=$(grep -c '^main_final "\$@"$' "$self" || true)
    [[ "$d" == 1 ]] && echo 'PASS: one final dispatch' || { echo "FAIL: dispatch count=$d"; errors=$((errors+1)); }
    [[ "$m" == 1 ]] && echo 'PASS: one main_final definition' || { echo "FAIL: main_final definitions=$m"; errors=$((errors+1)); }
    [[ "$mf" == 1 ]] && echo 'PASS: one main_final invocation' || { echo "FAIL: main_final invocations=$mf"; errors=$((errors+1)); }
    grep -q '^DISK="/dev/sdb"' "$self" && { echo 'FAIL: hard-coded /dev/sdb default'; errors=$((errors+1)); } || echo 'PASS: no /dev/sdb default'
    grep -q '"$official" != "AUTO"' "$self" && echo 'PASS: AUTO official-domain guard' || echo 'WARN: AUTO domain guard not found'
    bash -n "$self" && echo 'PASS: bash -n' || { echo 'FAIL: bash -n'; errors=$((errors+1)); }
    if grep -q $'\r' "$self"; then echo 'FAIL: CRLF characters detected'; errors=$((errors+1)); else echo 'PASS: LF-only source'; fi
    if grep -qE '\|\| return$' "$self"; then
        echo 'FAIL: unsafe bare "|| return" guard present'; errors=$((errors+1))
    else
        echo 'PASS: no unsafe bare "|| return" guard'
    fi
    grep -q '^sonar_role_enforce_lock() {' "$self" && echo 'PASS: role lock present' || { echo 'FAIL: role lock missing'; errors=$((errors+1)); }
    grep -q '^sonar_role_revoke_token() {' "$self" && echo 'PASS: role token revocation present' || { echo 'FAIL: role token revocation missing'; errors=$((errors+1)); }
    grep -q '^sonar_require_hardware_risk_ack() {' "$self" && echo 'PASS: hardware risk gate present' || { echo 'FAIL: hardware risk gate missing'; errors=$((errors+1)); }
    grep -q '^sonar_forensic_chain_of_custody() {' "$self" && echo 'PASS: chain-of-custody present' || { echo 'FAIL: chain-of-custody missing'; errors=$((errors+1)); }
    grep -q '^sonar_generate_vault_helper() {' "$self" && echo 'PASS: vault helper generator present' || { echo 'FAIL: vault helper generator missing'; errors=$((errors+1)); }
    grep -q '^sonar_generate_build_watermark() {' "$self" && echo 'PASS: build watermark present' || { echo 'FAIL: build watermark missing'; errors=$((errors+1)); }
    grep -q '^sonar_protect_catalog_final() {' "$self" && echo 'PASS: catalog protection present' || { echo 'FAIL: catalog protection missing'; errors=$((errors+1)); }
    grep -q '^sonar_policy_check_stale() {' "$self" && echo 'PASS: stale policy.tsv migration check present' || { echo 'FAIL: stale policy.tsv migration check missing'; errors=$((errors+1)); }
    local _dg_dir; _dg_dir="$(cd "$(dirname "$self")" && pwd)/tools"
    if [[ -f "${_dg_dir}/sonar_diag.sh" && -f "${_dg_dir}/diag_rules.txt" && -f "${_dg_dir}/diag_engine.awk" ]] && bash -n "${_dg_dir}/sonar_diag.sh" 2>/dev/null; then
        echo 'PASS: diagnostic intelligent present (sonar_diag.sh + diag_engine.awk + diag_rules.txt, bash -n)'
    else
        echo 'FAIL: diagnostic intelligent missing or has a syntax error (tools/sonar_diag.sh, tools/diag_rules.txt)'; errors=$((errors+1))
    fi
    if [[ -f "${_dg_dir}/client_templates.txt" && -f "${_dg_dir}/client_report.awk" && -f "${_dg_dir}/text2pdf.awk" ]] \
       && bash -n "${_dg_dir}/sonar_diag.sh" 2>/dev/null && grep -q -- '--client-report' "${_dg_dir}/sonar_diag.sh"; then
        echo 'PASS: rapport client present (client_templates.txt + client_report.awk + text2pdf.awk, option --client-report)'
    else
        echo 'FAIL: rapport client incomplet (tools/client_templates.txt, client_report.awk, text2pdf.awk ou --client-report)'; errors=$((errors+1))
    fi
    if [[ -f "${_dg_dir}/sonar_bitlocker.sh" ]] && bash -n "${_dg_dir}/sonar_bitlocker.sh" 2>/dev/null \
       && grep -q 'bitlkOpen --readonly' "${_dg_dir}/sonar_bitlocker.sh" && [[ -f "${SONAR_SCRIPT_DIR}/tests/bitlocker/run_tests.sh" ]]; then
        echo 'PASS: deverrouillage BitLocker present (sonar_bitlocker.sh, lecture seule, bash -n, tests)'
    else
        echo 'FAIL: deverrouillage BitLocker incomplet (tools/sonar_bitlocker.sh, lecture seule, tests/bitlocker/run_tests.sh)'; errors=$((errors+1))
    fi
    if [[ -f "${_dg_dir}/sonar_recover.sh" ]] && bash -n "${_dg_dir}/sonar_recover.sh" 2>/dev/null \
       && grep -q 'mount -o ro' "${_dg_dir}/sonar_recover.sh" && [[ -f "${SONAR_SCRIPT_DIR}/tests/recover/run_tests.sh" ]]; then
        echo 'PASS: recuperation de donnees presente (sonar_recover.sh, montage lecture seule, bash -n, tests)'
    else
        echo 'FAIL: recuperation de donnees incomplete (tools/sonar_recover.sh, lecture seule, tests/recover/run_tests.sh)'; errors=$((errors+1))
    fi
    if [[ -f "${_dg_dir}/sonar_pe_audit.sh" && -s "${_dg_dir}/pe_audit_indicators.txt" ]] && bash -n "${_dg_dir}/sonar_pe_audit.sh" 2>/dev/null \
       && [[ -f "${SONAR_SCRIPT_DIR}/tests/pe_audit/run_tests.sh" ]]; then
        echo 'PASS: audit de WinPE tiers present (sonar_pe_audit.sh + indicateurs, bash -n, tests)'
    else
        echo 'FAIL: audit de WinPE tiers incomplet (tools/sonar_pe_audit.sh, pe_audit_indicators.txt, tests/pe_audit/run_tests.sh)'; errors=$((errors+1))
    fi
    if [[ -f "${_dg_dir}/winpe/sonar_check_awk.sh" ]] && sh -n "${_dg_dir}/winpe/sonar_check_awk.sh" 2>/dev/null \
       && grep -q ':diagsources' "${_dg_dir}/Build-SonarSE-WinPE.ps1" && sh -n "${_dg_dir}/winpe/sonar_assistant.sh" 2>/dev/null && [[ -f "${_dg_dir}/winpe/sonar_banner.txt" ]] && [[ -f "${SONAR_SCRIPT_DIR}/tests/winpe/run_tests.sh" ]]; then
        echo 'PASS: WinPE : regles/moteur lus sur la cle (garde-fou awk, repli integre) + assistant guide (tests)'
    else
        echo 'FAIL: diagnostic WinPE depuis la cle incomplet (tools/winpe/sonar_check_awk.sh, :diagsources dans Build-SonarSE-WinPE.ps1, tests/winpe)'; errors=$((errors+1))
    fi
    # Boite a outils WinPE : collecteur + build (busybox sh -n n'existe pas ici : sh -n suffit, syntaxe POSIX).
    if [[ -f "${_dg_dir}/winpe/sonar_diag_winpe.sh" ]] && sh -n "${_dg_dir}/winpe/sonar_diag_winpe.sh" 2>/dev/null \
       && grep -q 'IncludeToolbox' "${_dg_dir}/Build-SonarSE-WinPE.ps1" 2>/dev/null \
       && grep -q 'IncludeAdkComponents' "${_dg_dir}/Build-SonarSE-WinPE.ps1" 2>/dev/null \
       && grep -Eq '\$bbSha256 = "[0-9a-f]{64}"' "${_dg_dir}/Build-SonarSE-WinPE.ps1" 2>/dev/null; then
        echo 'PASS: boite a outils WinPE presente (collecteur sh -n, -IncludeToolbox, SHA-256 BusyBox epingle)'
    else
        echo 'FAIL: boite a outils WinPE incomplete (tools/winpe/sonar_diag_winpe.sh, -IncludeToolbox ou SHA-256 BusyBox epingle)'; errors=$((errors+1))
    fi
    # Garde-fou TSV (item [12], audit externe) : chaque TSV embarque en
    # heredoc doit avoir au moins une tabulation par ligne de donnees. Un
    # editeur qui convertit les tabulations en espaces casse "awk -F'\t'"
    # (et donc chaque outil de ce manifeste) SANS message d'erreur visible
    # — "outil non trouve, donc saute" plutot qu'un echec bruyant. grep -P
    # '\t' seul serait insuffisant (une seule tabulation n'importe ou dans
    # la ligne suffirait a le satisfaire, meme une ligne qui n'en a besoin
    # que d'une alors que le format en attend plusieurs) ; awk -F'\t'
    # 'NF<2' exige au moins une tabulation REELLE separant deux colonnes.
    local _tsv_marker _tsv_start _tsv_end _tsv_bad
    for _tsv_marker in SONAR_CATALOGUE_EOF PROFILES_EOF FETCH_EOF SONAR_CATALOG_EOF; do
        _tsv_start=$(grep -n "<<'${_tsv_marker}'" "$self" | head -1 | cut -d: -f1)
        _tsv_end=$(grep -n "^${_tsv_marker}\$" "$self" | head -1 | cut -d: -f1)
        if [[ -z "$_tsv_start" || -z "$_tsv_end" ]]; then
            echo "FAIL: TSV heredoc '${_tsv_marker}' introuvable pour verification"; errors=$((errors+1)); continue
        fi
        _tsv_bad=$(sed -n "$((_tsv_start+1)),$((_tsv_end-1))p" "$self" | awk -F'\t' 'NF<2 && length($0)>0 {print NR; exit}')
        if [[ -n "$_tsv_bad" ]]; then
            echo "FAIL: TSV '${_tsv_marker}' ligne ${_tsv_bad} (relative) sans tabulation"; errors=$((errors+1))
        else
            echo "PASS: TSV '${_tsv_marker}' — chaque ligne de donnees a au moins une tabulation"
        fi
    done
    return "$errors"
}

# ============================================================================
# SONAR OPERATIONAL EXTENSIONS V2
# Non-destructive operational layer: Launcher, Diagnostic, Recovery plans,
# Backup/Clone safety checks, Forensic workspace, Network diagnostics,
# Builder, Self-Test and Release report.
# Destructive disk actions remain exclusively in the existing deploy workflow.
# ============================================================================

SONAR_VERSION="1.0.0"
SONAR_REPORT_DIR="${SONAR_REPORT_DIR:-${SONAR_ROOT}/SONAR_REPORTS}"
SONAR_BUILD_DIR="${SONAR_BUILD_DIR:-${SONAR_ROOT}/SONAR_BUILD}"
SONAR_PROFILE="${SONAR_PROFILE:-FULL}"

sonar_report_init() {
    mkdir -p "$SONAR_REPORT_DIR" "$SONAR_REPORT_DIR/runs" "$SONAR_REPORT_DIR/diagnostic" \
             "$SONAR_REPORT_DIR/recovery" "$SONAR_REPORT_DIR/forensic" "$SONAR_REPORT_DIR/network" \
             "$SONAR_REPORT_DIR/release"
}

sonar_timestamp() { date -u '+%Y%m%d-%H%M%S'; }

sonar_safe_name() { printf '%s' "$1" | tr -cs 'A-Za-z0-9._+-' '_' | cut -c1-120; }

sonar_dependency_report() {
    local out="${1:-${SONAR_REPORT_DIR}/dependency-report.tsv}"
    sonar_report_init
    printf 'COMMAND\tSTATUS\tPATH\n' > "$out"
    local c path status
    for c in bash awk sed grep find sort date python3 curl wget tar gzip sha256sum shasum lsblk blockdev mount umount dd mkfs.ext4 openssl; do
        path="$(command -v "$c" 2>/dev/null || true)"
        status=ABSENT; [[ -n "$path" ]] && status=OK
        printf '%s\t%s\t%s\n' "$c" "$status" "$path" >> "$out"
    done
    echo "$out"
}

sonar_diagnostic_report() {
    sonar_report_init
    local ts out inv cpu_model ram_mb block_devices
    ts="$(sonar_timestamp)"
    out="${SONAR_REPORT_DIR}/diagnostic/SONAR_DIAGNOSTIC_${ts}.txt"
    inv="${SONAR_REPORT_DIR}/diagnostic/SONAR_HARDWARE_${ts}.tsv"
    cpu_model="unknown"
    ram_mb="unknown"
    block_devices="unknown"
    if command -v lscpu >/dev/null 2>&1; then
        cpu_model="$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^ +/,"",$2); print $2; exit}')"
    fi
    if [[ -r /proc/meminfo ]]; then
        ram_mb="$(awk '/MemTotal:/ {printf "%d",$2/1024}' /proc/meminfo)"
    fi
    if command -v lsblk >/dev/null 2>&1; then
        block_devices="$(lsblk -dn -o NAME,SIZE,TYPE,MODEL,TRAN 2>/dev/null | tr '\n' ';')"
    fi
    {
        echo 'SONAR DIAGNOSTIC REPORT'
        echo '======================='
        echo "Version: ${SONAR_VERSION}"
        echo "Date: $(sonar_iso_now)"
        echo "OS: $(sonar_detect_os)"
        echo "ARCH: $(sonar_detect_arch)"
        echo "Kernel: $(uname -srmo 2>/dev/null || true)"
        echo
        echo '[CPU]'
        echo "Model: ${cpu_model}"
        echo
        echo '[MEMORY]'
        echo "RAM_MB: ${ram_mb}"
        [[ -r /proc/meminfo ]] && awk '/MemTotal|MemAvailable/ {print}' /proc/meminfo || true
        echo
        echo '[STORAGE]'
        command -v lsblk >/dev/null 2>&1 && lsblk -o NAME,SIZE,TYPE,FSTYPE,FSAVAIL,FSUSE%,MOUNTPOINTS,MODEL,TRAN || true
        echo
        echo '[UEFI / SECURE BOOT]'
        if command -v mokutil >/dev/null 2>&1; then
            mokutil --sb-state 2>&1 || true
        elif [[ -d /sys/firmware/efi ]]; then
            echo 'UEFI: detected'
            echo 'Secure Boot: not determined'
        else
            echo 'UEFI: not detected'
        fi
        echo
        echo '[NETWORK]'
        command -v ip >/dev/null 2>&1 && ip -brief address 2>/dev/null || true
        command -v ip >/dev/null 2>&1 && ip route 2>/dev/null || true
        echo
        echo '[SECURITY]'
        echo "Role: ${SONAR_ROLE}"
        echo "AI mode: ${AI_MODE}"
        echo 'AI destructive authority: NONE'
        echo
        echo 'NOTE: This report is diagnostic only. It does not prove boot compatibility.'
    } > "$out"
    {
        printf 'FIELD\tVALUE\n'
        printf 'OS\t%s\n' "$(sonar_detect_os)"
        printf 'ARCH\t%s\n' "$(sonar_detect_arch)"
        printf 'KERNEL\t%s\n' "$(uname -sr 2>/dev/null || true)"
        printf 'CPU\t%s\n' "$cpu_model"
        printf 'RAM_MB\t%s\n' "$ram_mb"
        printf 'BLOCK_DEVICES\t%s\n' "$block_devices"
    } > "$inv"
    sonar_audit "DIAGNOSTIC_REPORT" "report=${out}"
    echo "[SONAR] Diagnostic: $out"
    echo "[SONAR] Hardware TSV: $inv"
}

# sonar_selftest_extract_fn SELF FUNCNAME: extrait le corps de FUNCNAME
# depuis le fichier SELF via sed ('/^FUNCNAME() {/,/^}/p'), et imprime
# l'extrait sur stdout SEULEMENT s'il est non vide, contient bien l'en-tete
# "FUNCNAME() {" et passe "bash -n" — sinon echoue bruyamment (message sur
# stderr, code de sortie non nul) au lieu de laisser un `source <(...)`
# vide ou tronque passer silencieusement. Risque theorique que ca evite :
# un heredoc a l'interieur de FUNCNAME contenant "}" en debut de ligne
# refermerait prematurement la plage sed, produisant une fonction tronquee
# qui reste syntaxiquement valide (bash -n ne le detecterait pas non plus
# dans ce cas precis) mais fait moins que prevu — le test tournerait alors
# sur un comportement partiel et pourrait passer par accident. Utilise par
# les ~12 sous-tests de sonar_self_test_v2 qui isolent une fonction unique
# plutot que de sourcer tout le script (evite d'executer main_final).
#
# Angle mort trouve le 2026-09-22 (extraction trop LARGE, pas tronquee) :
# quand FUNCNAME est declaree sur une seule ligne ("fn() { ...; }"), le
# motif de fin de plage sed "/^}/" exige une ligne qui COMMENCE par "}" —
# cette ligne-la n'en est pas une (elle commence par "fn() {"), donc la
# plage sed ne se referme jamais ici et continue jusqu'a la PROCHAINE
# accolade fermante en debut de ligne, avalant potentiellement toute la
# fonction suivante. Reste syntaxiquement valide (bash -n ne le detecte
# pas), donc un sous-test source alors la mauvaise fonction (ou les deux)
# sans avertissement. Verifie empiriquement sur sonar_build_secret_exists()
# (une ligne) : extraction de 29 lignes au lieu d'1, jusqu'a l'accolade de
# sonar_ensure_build_secret() qui suit. Detecte et gere ce cas a part.
sonar_selftest_extract_fn() {
    local self="$1" fn="$2" body header
    header="$(grep -m1 "^${fn}() {" "$self")"
    if [[ "$header" == *"}"* ]]; then
        body="$header"
    else
        body="$(sed -n "/^${fn}() {/,/^}/p" "$self")"
    fi
    if [[ -z "$body" ]]; then
        echo "sonar_selftest_extract_fn: extraction vide pour '${fn}'" >&2
        return 1
    fi
    if ! grep -q "^${fn}() {" <<<"$body"; then
        echo "sonar_selftest_extract_fn: en-tete de '${fn}' absent de l'extrait" >&2
        return 1
    fi
    if ! bash -n <<<"$body" 2>/dev/null; then
        echo "sonar_selftest_extract_fn: extrait de '${fn}' invalide (bash -n)" >&2
        return 1
    fi
    printf '%s\n' "$body"
}

sonar_self_test_v2() {
    sonar_report_init
    # self must be an absolute (slash-containing) path: dozens of checks below
    # invoke it directly as `"$self" --flag` (not `bash "$self"`). A bare
    # BASH_SOURCE[0] like "sonar_master.sh" (no "/") has no slash, so bash's
    # command lookup searches $PATH instead of cwd — it silently fails to
    # find the file whenever the script was launched as `bash sonar_master.sh`
    # (cwd not on PATH), and every one of those checks then fails together
    # because the recursive invocation's stderr is swallowed by `2>/dev/null`.
    # Found 2026-09-17 — see CHANGELOG.md.
    local ts out errors=0 warnings=0 self="${SONAR_SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"
    ts="$(sonar_timestamp)"; out="${SONAR_REPORT_DIR}/runs/SONAR_SELFTEST_${ts}.txt"
    exec 3>&1
    {
        echo 'SONAR SELF-TEST V2'
        echo '=================='
        echo "Version: ${SONAR_VERSION}"
        echo "Date: $(sonar_iso_now)"
        echo
        check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf "PASS\t%s\n" "${label}"; else printf "FAIL\t%s\n" "${label}"; errors=$((errors+1)); fi; }
        check 'bash syntax' bash -n "$self"
        # Non-regression : le prompt IA ne doit plus jamais transiter par
        # argv (visible via /proc/<pid>/cmdline ou "ps" pendant l'execution)
        # — corrige 2026-09-17, meme categorie que le secret HMAC (v3.14.0).
        # Verification ciblee sur les CORPS des deux fonctions concernees
        # (pas tout le fichier : sonar_hmac_sha256_file utilise legitimement
        # sys.argv[2] pour un message non-secret, cf. commentaire a cote).
        _ai_argv_leak=false
        for _fn in ai_query_local ollama_query; do
            _body="$(sed -n "/^${_fn}() {/,/^}/p" "$self")"
            grep -q 'stdin\.read()' <<<"${_body}" || _ai_argv_leak=true
        done
        if [[ "${_ai_argv_leak}" == "true" ]]; then
            printf 'FAIL\tAI query prompt still passed via argv instead of stdin\n'; errors=$((errors+1))
        else
            printf 'PASS\tAI query prompt (ai_query_local, ollama_query) not passed via argv\n'
        fi
        check 'python3' command -v python3
        check 'sha256 engine' bash -c 'command -v sha256sum || command -v shasum'
        if [[ -d "${SOURCE_DIR}" ]]; then printf 'PASS\tsource directory\n'; else printf 'WARN\tsource directory absent (runtime test environment)\n'; warnings=$((warnings+1)); fi
        [[ -d "${ISO_SOURCE_DIR}" ]] && echo 'PASS\tISO source' || { printf 'WARN\tISO source absent\n'; warnings=$((warnings+1)); }
        [[ -d "${PORTABLE_SOURCE_DIR}" ]] && printf 'PASS\tPortable source\n' || { printf 'WARN\tPortable source absent\n'; warnings=$((warnings+1)); }
        [[ -d "${SCRIPTS_SOURCE_DIR}" ]] && echo 'PASS\tScripts source' || { printf 'WARN\tScripts source absent\n'; warnings=$((warnings+1)); }
        [[ -d "${DRIVERS_SOURCE_DIR}" ]] && echo 'PASS\tDrivers source' || { printf 'WARN\tDrivers source absent\n'; warnings=$((warnings+1)); }
        [[ -d "${MACOS_SOURCE_DIR}" ]] && echo 'PASS\tmacOS source' || { printf 'WARN\tmacOS source absent\n'; warnings=$((warnings+1)); }
        grep -q '^sonar_cli() {' "$self" && printf 'PASS\tCLI present\n' || { printf 'FAIL\tCLI missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_self_test_v2() {' "$self" && printf 'PASS\tSelf-Test module present\n' || { printf 'FAIL\tSelf-Test module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_builder_v2() {' "$self" && printf 'PASS\tBuilder module present\n' || { printf 'FAIL\tBuilder module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_launcher_v2() {' "$self" && printf 'PASS\tLauncher module present\n' || { printf 'FAIL\tLauncher module missing\n'; errors=$((errors+1)); }
        if grep -q '^DISK="/dev/sdb"' "$self"; then printf 'FAIL\thard-coded /dev/sdb default\n'; errors=$((errors+1)); else printf 'PASS\tNo hard-coded /dev/sdb default\n'; fi
        if grep -q $'\r' "$self"; then printf 'FAIL\tCRLF detected\n'; errors=$((errors+1)); else printf 'PASS\tLF-only\n'; fi
        if grep -qE '\|\| return$' "$self"; then
            printf 'FAIL\tUnsafe bare "|| return" guard (breaks under set -e when false)\n'
            errors=$((errors+1))
        else
            printf 'PASS\tNo unsafe bare "|| return" guard\n'
        fi
        grep -q '^sonar_recovery_execute() {' "$self" && printf 'PASS\tRecovery execution module present\n' || { printf 'FAIL\tRecovery execution module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_backup_execute() {' "$self" && printf 'PASS\tBackup execution module present\n' || { printf 'FAIL\tBackup execution module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_forensic_acquire() {' "$self" && printf 'PASS\tForensic acquisition module present\n' || { printf 'FAIL\tForensic acquisition module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_clone_guarded() {' "$self" && printf 'PASS\tClone safety guard present\n' || { printf 'FAIL\tClone safety guard missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_module_status_v23() {' "$self" && printf 'PASS\tModule status present\n' || { printf 'FAIL\tModule status missing\n'; errors=$((errors+1)); }
        # stderr capture (2>&1 >/dev/null, dans cet ordre) plutot que
        # >/dev/null 2>&1 pour ces 3 smoke tests specifiquement : un echec
        # ici est une REGRESSION potentielle (pas un cas volontairement
        # invalide comme les tests "rejette X" plus bas), donc la cause
        # merite d'etre visible dans le rapport plutot que noyee comme
        # avant le correctif du bug BASH_SOURCE[0] (v3.36.0) — retire le
        # 2>/dev/null seulement ou l'echec silencieux n'est PAS le
        # comportement attendu (item [13], audit externe).
        if _st_err="$("$self" --module-status 2>&1 >/dev/null)"; then _st_rc=0; else _st_rc=$?; fi
        if [[ $_st_rc -eq 0 ]]; then printf 'PASS\tModule status smoke test\n'; else printf 'FAIL\tModule status smoke test%s\n' "${_st_err:+ (stderr: ${_st_err})}"; errors=$((errors+1)); fi
        if _st_err="$("$self" --recovery-execute collect 2>&1 >/dev/null)"; then _st_rc=0; else _st_rc=$?; fi
        if [[ $_st_rc -eq 0 ]]; then printf 'PASS\tRecovery collect smoke test\n'; else printf 'FAIL\tRecovery collect smoke test%s\n' "${_st_err:+ (stderr: ${_st_err})}"; errors=$((errors+1)); fi
        grep -q '^sonar_smart_advisor() {' "$self" && printf 'PASS\tSmart Advisor module present\n' || { printf 'FAIL\tSmart Advisor module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_verify_hashchain() {' "$self" && printf 'PASS\tHashchain verification present\n' || { printf 'FAIL\tHashchain verification missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_catalog_seal() {' "$self" && printf 'PASS\tCatalog seal module present\n' || { printf 'FAIL\tCatalog seal module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_post_deploy_verify_final() {' "$self" && printf 'PASS\tPost-deploy verification present\n' || { printf 'FAIL\tPost-deploy verification missing\n'; errors=$((errors+1)); }
        if _st_err="$("$self" --verify-hashchain 2>&1 >/dev/null)"; then _st_rc=0; else _st_rc=$?; fi
        if [[ $_st_rc -eq 0 ]]; then printf 'PASS\tHashchain verify smoke test\n'; else printf 'WARN\tHashchain verify smoke test (aucun historique encore%s)\n' "${_st_err:+ ; stderr: ${_st_err}}"; warnings=$((warnings+1)); fi
        # Non-regression du flock ajoute 2026-09-17 : peuple un historique
        # reel (plusieurs entrees, pas juste le cas WARN "vide" ci-dessus)
        # dans un ROOT isole, verifie que --verify-hashchain le lit
        # correctement (chemin PASS reel, pas juste "aucun historique").
        local _hc_dir _hc_out
        _hc_dir="$(mktemp -d)"
        # --self-audit est structurel (grep sur le script), n'appelle jamais
        # sonar_audit : --role-bootstrap + --role-issue-token, eux, ecrivent
        # chacun une entree reelle.
        SONAR_ROOT="${_hc_dir}" "$self" --role-bootstrap >/dev/null 2>&1
        SONAR_ROOT="${_hc_dir}" "$self" --role-issue-token Admin hashchain.selftest.bot 1 >/dev/null 2>&1
        _hc_out="$(SONAR_ROOT="${_hc_dir}" "$self" --verify-hashchain 2>&1)"
        if grep -qi 'integre' <<<"${_hc_out}"; then
            printf 'PASS\tHashchain verify succeeds on a populated, untampered log\n'
        else
            printf 'FAIL\tHashchain verify did not confirm an untampered populated log\n'; errors=$((errors+1))
        fi
        rm -rf "${_hc_dir}"
        grep -q '^sonar_role_enforce_lock() {' "$self" && printf 'PASS\tRole lock module present\n' || { printf 'FAIL\tRole lock module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_role_bootstrap_secret() {' "$self" && printf 'PASS\tRole secret bootstrap present\n' || { printf 'FAIL\tRole secret bootstrap missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_role_revoke_token() {' "$self" && printf 'PASS\tRole token revocation present\n' || { printf 'FAIL\tRole token revocation missing\n'; errors=$((errors+1)); }
        local _esc_out
        _esc_out="$(SONAR_ROLE=Admin SONAR_ROLE_TOKEN='' "$self" --security-status 2>/dev/null)"
        if grep -q 'role: Technician' <<< "${_esc_out}"; then
            printf 'PASS\tRole escalation without token is blocked\n'
        else
            printf 'FAIL\tRole escalation without token was NOT blocked\n'; errors=$((errors+1))
        fi
        # Regression (audit adversarial 2026-09-21) : le marqueur interne « verrou deja verifie » ne doit JAMAIS
        # pouvoir etre fourni par l'environnement (Admin sans jeton avec SONAR_ROLE_LOCK_ENFORCED_SIG='Admin::').
        local _es_root _es_out _es_before _es_after
        _es_root="$(mktemp -d)"
        _es_out="$(SONAR_ROOT="${_es_root}" SONAR_ROLE=Admin SONAR_ROLE_LOCK_ENFORCED_SIG='Admin::' "$self" --security-status 2>/dev/null)"
        if grep -q 'role: Technician' <<< "${_es_out}"; then
            printf 'PASS\tRole lock cannot be bypassed by exporting SONAR_ROLE_LOCK_ENFORCED_SIG\n'
        else
            printf 'FAIL\tSONAR_ROLE_LOCK_ENFORCED_SIG from the environment bypassed the role lock (Admin without a token)\n'; errors=$((errors+1))
        fi
        # Regression : une identite auto-declaree (env, role libre-service) ne doit pas pouvoir forger de lignes de journal.
        SONAR_ROOT="${_es_root}" "$self" --role-bootstrap >/dev/null 2>&1
        _es_before="$(wc -l < "${_es_root}/Secure/Logs/audit.log")"
        SONAR_ROOT="${_es_root}" SONAR_ROLE_IDENTITY=$'x\n2026-01-01T00:00:00Z\tAdmin\tROLE_ELEVATION_GRANTED\trole=Admin;identity=root' "$self" --role-issue-token Admin forged.test >/dev/null 2>&1
        _es_after="$(wc -l < "${_es_root}/Secure/Logs/audit.log")"
        _es_out="$(SONAR_ROOT="${_es_root}" "$self" --verify-hashchain 2>&1)"   # capture d'abord : "| grep -q" sous pipefail = SIGPIPE
        if [[ $((_es_after - _es_before)) -eq 1 ]] && [[ -z "$(awk -F'\t' '$3=="ROLE_ELEVATION_GRANTED" || $1 ~ /^2026-01-01/' "${_es_root}/Secure/Logs/audit.log")" ]] \
           && grep -q 'integre' <<< "${_es_out}"; then
            printf 'PASS\tAn unauthenticated SONAR_ROLE_IDENTITY cannot inject forged lines into the audit log\n'
        else
            printf 'FAIL\tSONAR_ROLE_IDENTITY with a newline/tab injected extra lines into audit.log (%s -> %s)\n' "${_es_before}" "${_es_after}"; errors=$((errors+1))
        fi
        rm -rf "${_es_root}"
        local _rt_root _rt_out _rt_token
        _rt_root="$(mktemp -d)"
        SONAR_ROOT="${_rt_root}" "$self" --role-bootstrap >/dev/null 2>&1
        _rt_token="$(SONAR_ROOT="${_rt_root}" "$self" --role-issue-token Admin selftest.bot 1 2>/dev/null)"
        _rt_out="$(SONAR_ROOT="${_rt_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_rt_token}" "$self" --security-status 2>/dev/null)"
        if grep -q 'role: Admin' <<< "${_rt_out}" && grep -q 'identity: selftest.bot' <<< "${_rt_out}"; then
            printf 'PASS\tPer-identity token grants role\n'
        else
            printf 'FAIL\tPer-identity token did not grant role\n'; errors=$((errors+1))
        fi
        # Revoking now requires an elevated (non-self-service) role itself
        # (2026-09-15 fix — see sonar_role_revoke_token) — authenticate
        # with the same valid Admin token being revoked, exactly how a
        # real operator would use it, instead of the unauthenticated call
        # this test used to make.
        SONAR_ROOT="${_rt_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_rt_token}" "$self" --role-revoke-token "${_rt_token}" >/dev/null 2>&1
        _rt_out="$(SONAR_ROOT="${_rt_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_rt_token}" "$self" --security-status 2>/dev/null)"
        if grep -q 'role: Technician' <<< "${_rt_out}"; then
            printf 'PASS\tRevoked token is rejected\n'
        else
            printf 'FAIL\tRevoked token was NOT rejected\n'; errors=$((errors+1))
        fi
        # Regression test (2026-09-15): an unauthenticated Technician must
        # NOT be able to revoke someone else's token — before this fix,
        # sonar_role_revoke_token had no role gate at all, so any local
        # user could DoS any Admin/Forensic/Senior/Expert token just by
        # reading its identity/role/expiry from audit.log (no signature
        # check was required to revoke). Issue a second token, attempt an
        # unauthenticated revoke, then confirm the token STILL works.
        local _rt2_token _rt2_out
        _rt2_token="$(SONAR_ROOT="${_rt_root}" "$self" --role-issue-token Admin selftest2.bot 1 2>/dev/null)"
        SONAR_ROOT="${_rt_root}" "$self" --role-revoke-token "${_rt2_token}" >/dev/null 2>&1
        _rt2_out="$(SONAR_ROOT="${_rt_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_rt2_token}" "$self" --security-status 2>/dev/null)"
        if grep -q 'role: Admin' <<< "${_rt2_out}"; then
            printf 'PASS\tUnauthenticated revoke attempt is rejected (token still valid)\n'
        else
            printf 'FAIL\tUnauthenticated Technician was able to revoke another token\n'; errors=$((errors+1))
        fi
        local _old_secret_file="${SONAR_ROLE_SECRET_FILE}" _old_revoked_file="${SONAR_ROLE_REVOKED_FILE}" _exp_epoch _exp_sig _exp_token
        _exp_epoch=$(( $(date -u +%s) - 3600 ))
        SONAR_ROLE_SECRET_FILE="${_rt_root}/Secure/Keys/role_secret.key"
        SONAR_ROLE_REVOKED_FILE="${_rt_root}/Secure/Keys/revoked_tokens.tsv"
        _exp_sig="$(sonar_role_sign 'expired.bot' 'Admin' "${_exp_epoch}" 2>/dev/null)"
        SONAR_ROLE_SECRET_FILE="${_old_secret_file}"
        SONAR_ROLE_REVOKED_FILE="${_old_revoked_file}"
        _exp_token="expired.bot:Admin:${_exp_epoch}:${_exp_sig}"
        _rt_out="$(SONAR_ROOT="${_rt_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_exp_token}" "$self" --security-status 2>/dev/null)"
        if grep -q 'role: Technician' <<< "${_rt_out}"; then
            printf 'PASS\tExpired token is rejected\n'
        else
            printf 'FAIL\tExpired token was NOT rejected\n'; errors=$((errors+1))
        fi
        local _it_token
        _it_token="$(SONAR_ROOT="${_rt_root}" "$self" --role-issue-token Admin identity.trace.bot 1 2>/dev/null)"
        SONAR_ROOT="${_rt_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_it_token}" "$self" --diagnostic >/dev/null 2>&1
        if grep -q $'\tDIAGNOSTIC_REPORT\t.*identity=identity.trace.bot' "${_rt_root}/Secure/Logs/audit.log" 2>/dev/null; then
            printf 'PASS\tIdentity propagates to non-lock audit events\n'
        else
            printf 'FAIL\tIdentity did NOT propagate to non-lock audit events\n'; errors=$((errors+1))
        fi
        grep -q '^sonar_forensic_chain_of_custody() {' "$self" && printf 'PASS\tChain-of-custody module present\n' || { printf 'FAIL\tChain-of-custody module missing\n'; errors=$((errors+1)); }
        local _coc_src _coc_dst _coc_token _coc_evroot _coc_doc
        _coc_src="$(mktemp -d)"; _coc_dst="$(mktemp -d)"
        echo "piece" > "${_coc_src}/exhibit.txt"
        _coc_token="$(SONAR_ROOT="${_rt_root}" "$self" --role-issue-token Forensic coc.trace.bot 1 2>/dev/null)"
        SONAR_ROOT="${_rt_root}" SONAR_ROLE=Forensic SONAR_ROLE_TOKEN="${_coc_token}" "$self" --forensic-acquire "${_coc_src}" "${_coc_dst}" >/dev/null 2>&1
        _coc_evroot="$(find "${_coc_dst}" -maxdepth 1 -name 'SONAR_EVIDENCE_*' | head -n1)"
        if [[ -n "${_coc_evroot}" ]]; then
            SONAR_ROOT="${_rt_root}" "$self" --forensic-chain-of-custody "${_coc_evroot}" 'SELFTEST-CASE' >/dev/null 2>&1
            _coc_doc="${_coc_evroot}/reports/CHAIN_OF_CUSTODY.txt"
            if [[ -s "${_coc_doc}" ]] && grep -q 'identity=coc.trace.bot' "${_coc_doc}" && grep -q 'INTACT' "${_coc_doc}"; then
                printf 'PASS\tChain-of-custody links operator identity + hashchain status\n'
            else
                printf 'FAIL\tChain-of-custody document incomplete or missing identity/hashchain link\n'; errors=$((errors+1))
            fi
        else
            printf 'FAIL\tForensic acquisition for chain-of-custody smoke test did not produce evidence\n'; errors=$((errors+1))
        fi
        rm -rf "${_coc_src}" "${_coc_dst}"

        # Regression test: the smoke test above always used an identity-
        # carrying token. A real bug (v3.10.2) only manifested for the more
        # common case — acquisition under the default self-service role,
        # no token, no identity — where the audit-line lookup pipeline
        # returned non-zero (grep found no "identity=" field) and crashed
        # the whole function silently under set -e + pipefail.
        local _coc2_src _coc2_dst _coc2_evroot _coc2_doc
        _coc2_src="$(mktemp -d)"; _coc2_dst="$(mktemp -d)"
        echo "piece" > "${_coc2_src}/exhibit.txt"
        SONAR_ROOT="${_rt_root}" "$self" --forensic-acquire "${_coc2_src}" "${_coc2_dst}" >/dev/null 2>&1
        _coc2_evroot="$(find "${_coc2_dst}" -maxdepth 1 -name 'SONAR_EVIDENCE_*' | head -n1)"
        if [[ -n "${_coc2_evroot}" ]] && SONAR_ROOT="${_rt_root}" "$self" --forensic-chain-of-custody "${_coc2_evroot}" 'NOIDENT-CASE' >/dev/null 2>&1; then
            printf 'PASS\tChain-of-custody works for acquisition without an authenticated identity\n'
        else
            printf 'FAIL\tChain-of-custody crashed for acquisition without an authenticated identity\n'; errors=$((errors+1))
        fi

        # Regression test: a case id containing embedded tab/newline
        # characters must not corrupt audit.log's tab-separated structure
        # or masquerade as a separate fake log entry.
        local _inj_case _inj_before _inj_after
        _inj_case="$(printf 'X\nFAKE\tINJECTED\tROW')"
        _inj_before="$(wc -l < "${_rt_root}/Secure/Logs/audit.log" 2>/dev/null || echo 0)"
        if [[ -n "${_coc2_evroot}" ]]; then
            SONAR_ROOT="${_rt_root}" "$self" --forensic-chain-of-custody "${_coc2_evroot}" "${_inj_case}" >/dev/null 2>&1
        fi
        _inj_after="$(wc -l < "${_rt_root}/Secure/Logs/audit.log" 2>/dev/null || echo 0)"
        if (( _inj_after == _inj_before + 2 )) \
           && [[ "$(tail -n1 "${_rt_root}/Secure/Logs/audit.log")" != *$'\n'* ]] \
           && [[ "$(tail -n1 "${_rt_root}/Secure/Logs/audit.log" | awk -F'\t' '{print NF}')" == "4" ]]; then
            printf 'PASS\tAudit log rejects tab/newline injection in caller-supplied text\n'
        else
            printf 'FAIL\tAudit log structure was corrupted by injected tab/newline\n'; errors=$((errors+1))
        fi
        rm -rf "${_coc2_src}" "${_coc2_dst}"
        rm -rf "${_rt_root}"
        grep -q '^sonar_generate_vault_helper() {' "$self" && printf 'PASS\tVault helper generator present\n' || { printf 'FAIL\tVault helper generator missing\n'; errors=$((errors+1)); }
        if command -v gpg >/dev/null 2>&1; then
            local _vh_dir _vh_src _vh_enc _vh_out
            _vh_dir="$(mktemp -d)"
            ( source <(sonar_selftest_extract_fn "$self" sonar_generate_vault_helper); log_ok() { :; }; sonar_generate_vault_helper "${_vh_dir}" ) >/dev/null 2>&1
            _vh_src="${_vh_dir}/plain.txt"; _vh_enc="${_vh_dir}/v.enc"; _vh_out="${_vh_dir}/plain_out.txt"
            echo "selftest-vault-content" > "${_vh_src}"
            printf 'pw123\npw123\n' | "${_vh_dir}/sonar-vault.sh" create "${_vh_src}" "${_vh_enc}" >/dev/null 2>&1
            printf 'pw123\n' | "${_vh_dir}/sonar-vault.sh" open "${_vh_enc}" "${_vh_out}" >/dev/null 2>&1
            if [[ -s "${_vh_enc}" ]] && ! grep -q 'selftest-vault-content' "${_vh_enc}" 2>/dev/null && diff -q "${_vh_src}" "${_vh_out}" >/dev/null 2>&1; then
                printf 'PASS\tVault helper round-trip (encrypt/decrypt) works\n'
            else
                printf 'FAIL\tVault helper round-trip did NOT work\n'; errors=$((errors+1))
            fi
            rm -rf "${_vh_dir}"
        else
            printf 'WARN\tVault helper round-trip skipped (gpg absent from this environment)\n'; warnings=$((warnings+1))
        fi
        # Regression : un echec de protection du catalogue (gpg absent...) ne doit pas interrompre le
        # deploiement sous "set -e" (cle laissee montee, sans filigrane) : l'appel est dans un "if !".
        if grep -q 'if ! sonar_protect_catalog_final "${mp}"; then' "$self"; then
            printf 'PASS\tCatalog protection failure does not abort the deployment (call guarded)\n'
        else
            printf 'FAIL\tsonar_protect_catalog_final call in copy_payload_final is not guarded against set -e\n'; errors=$((errors+1))
        fi
        grep -q '^sonar_protect_catalog_final() {' "$self" && printf 'PASS\tCatalog protection function present\n' || { printf 'FAIL\tCatalog protection function missing\n'; errors=$((errors+1)); }
        local _pc_mp _pc_root _pc_token
        _pc_mp="$(mktemp -d)"
        mkdir -p "${_pc_mp}/MANIFEST"
        printf 'id\tname\turl\tsha256\n1\ttest-tool\thttp://example.invalid\tabc\n' > "${_pc_mp}/MANIFEST/MANIFEST.tsv"
        ( SONAR_PROTECT_CATALOG=false; log() { :; }; log_ok() { :; }
          sonar_protect_catalog_final "${_pc_mp}" ) >/dev/null 2>&1
        if [[ -s "${_pc_mp}/MANIFEST/MANIFEST.tsv" && ! -e "${_pc_mp}/MANIFEST/MANIFEST.tsv.gpg" ]]; then
            printf 'PASS\t--protect-catalog opt-out leaves MANIFEST.tsv untouched (default)\n'
        else
            printf 'FAIL\t--protect-catalog opt-out changed MANIFEST.tsv when it should not have\n'; errors=$((errors+1))
        fi
        _pc_root="$(mktemp -d)"
        SONAR_ROOT="${_pc_root}" "$self" --role-bootstrap >/dev/null 2>&1
        # SONAR_ROOT="${_pc_root}" "$self" --security-status materialise un
        # policy.tsv frais (defauts actuels du script) sous _pc_root, pour
        # que ce test ne depende jamais d'un policy.tsv deja present ailleurs
        # sur la machine (trouve en pratique le 2026-09-18 : un policy.tsv
        # local perime, genere avant le durcissement RBAC de cette session,
        # accordait encore VAULT=RW a Technician — sonar_security_init ne
        # regenere jamais un fichier deja present, donc un ancien
        # Secure/Policies/policy.tsv reste silencieusement perime tant qu'il
        # n'est pas supprime manuellement).
        SONAR_ROOT="${_pc_root}" "$self" --security-status >/dev/null 2>&1
        ( SONAR_PROTECT_CATALOG=true; SONAR_PROTECT_PASSPHRASE="pw123"; SONAR_ROLE=Technician; SONAR_ROLE_TOKEN=""
          SONAR_ROLE_SECRET_FILE="${_pc_root}/Secure/Keys/role_secret.key"
          SONAR_POLICY_FILE="${_pc_root}/Secure/Policies/policy.tsv"
          log() { :; }; log_ok() { :; }
          sonar_protect_catalog_final "${_pc_mp}" ) >/dev/null 2>&1
        if [[ -s "${_pc_mp}/MANIFEST/MANIFEST.tsv" && ! -e "${_pc_mp}/MANIFEST/MANIFEST.tsv.gpg" ]]; then
            printf 'PASS\t--protect-catalog refuses without a VAULT-capable role (catalog left in clear)\n'
        else
            printf 'FAIL\t--protect-catalog proceeded without a VAULT-capable role\n'; errors=$((errors+1))
        fi
        if command -v gpg >/dev/null 2>&1; then
            _pc_token="$(SONAR_ROOT="${_pc_root}" "$self" --role-issue-token Admin protectcatalog.selftest.bot 1 2>/dev/null)"
            ( SONAR_PROTECT_CATALOG=true; SONAR_PROTECT_PASSPHRASE="pw123"; SONAR_ROLE=Admin; SONAR_ROLE_TOKEN="${_pc_token}"
              SONAR_ROLE_SECRET_FILE="${_pc_root}/Secure/Keys/role_secret.key"
              SONAR_POLICY_FILE="${_pc_root}/Secure/Policies/policy.tsv"
              log() { :; }; log_ok() { :; }; sonar_audit() { :; }
              sonar_protect_catalog_final "${_pc_mp}" ) >/dev/null 2>&1
            local _pc_out
            _pc_out="$(mktemp)"
            if [[ ! -s "${_pc_mp}/MANIFEST/MANIFEST.tsv" ]] && [[ -s "${_pc_mp}/MANIFEST/MANIFEST.tsv.gpg" ]] \
               && ! grep -q 'test-tool' "${_pc_mp}/MANIFEST/MANIFEST.tsv.gpg" 2>/dev/null \
               && printf 'pw123\n' | gpg --batch --yes --passphrase-fd 0 --decrypt -o "${_pc_out}" "${_pc_mp}/MANIFEST/MANIFEST.tsv.gpg" >/dev/null 2>&1 \
               && grep -q 'test-tool' "${_pc_out}"; then
                printf 'PASS\t--protect-catalog with VAULT-capable role encrypts MANIFEST.tsv (plaintext removed, decrypts back correctly)\n'
            else
                printf 'FAIL\t--protect-catalog with a valid role did not produce a correct encrypted catalog\n'; errors=$((errors+1))
            fi
            rm -f "${_pc_out}"
        else
            printf 'WARN\t--protect-catalog encrypt/decrypt round-trip skipped (gpg absent from this environment)\n'; warnings=$((warnings+1))
        fi
        rm -rf "${_pc_mp}" "${_pc_root}"
        # Diagnostic intelligent : suite de tests du moteur (scenarios de faits
        # construits a la main, resultats attendus exacts). Chaque ligne
        # PASS/FAIL est relayee telle quelle ; le nombre d'echecs s'ajoute.
        if [[ -f "${SONAR_SCRIPT_DIR}/tests/diag/run_tests.sh" ]]; then
            local _dg_out _dg_rc
            _dg_out="$(bash "${SONAR_SCRIPT_DIR}/tests/diag/run_tests.sh" 2>&1)"; _dg_rc=$?
            printf '%s\n' "${_dg_out}"
            errors=$((errors + _dg_rc))
        else
            printf 'WARN\tDiagnostic intelligent : tests/diag/run_tests.sh absent, moteur non teste\n'; warnings=$((warnings+1))
        fi
        # Recuperation de donnees (disque de test CONSTRUIT : NTFS, secteurs defectueux simules) et audit de PE tiers.
        local _tsuite _tout _trc
        for _tsuite in recover pe_audit winpe; do
            if [[ -f "${SONAR_SCRIPT_DIR}/tests/${_tsuite}/run_tests.sh" ]]; then
                _tout="$(bash "${SONAR_SCRIPT_DIR}/tests/${_tsuite}/run_tests.sh" 2>&1)"; _trc=$?
                printf '%s\n' "${_tout}"
                errors=$((errors + _trc))
            else
                printf 'WARN\ttests/%s/run_tests.sh absent\n' "${_tsuite}"; warnings=$((warnings+1))
            fi
        done
        # Deverrouillage BitLocker : garde-fous (+ volume reel si SONAR_BL_TEST_IMAGE est fourni).
        if [[ -f "${SONAR_SCRIPT_DIR}/tests/bitlocker/run_tests.sh" ]]; then
            local _bl_out _bl_rc
            _bl_out="$(bash "${SONAR_SCRIPT_DIR}/tests/bitlocker/run_tests.sh" 2>&1)"; _bl_rc=$?
            printf '%s\n' "${_bl_out}"
            errors=$((errors + _bl_rc))
        else
            printf 'WARN\tBitLocker : tests/bitlocker/run_tests.sh absent, deverrouillage non teste\n'; warnings=$((warnings+1))
        fi
        grep -q '^sonar_policy_check_stale() {' "$self" && printf 'PASS\tStale policy.tsv migration check present\n' || { printf 'FAIL\tStale policy.tsv migration check missing\n'; errors=$((errors+1)); }
        local _pol_root _pol_file _pol_bak_count
        _pol_root="$(mktemp -d)"
        mkdir -p "${_pol_root}/Secure/Policies"
        _pol_file="${_pol_root}/Secure/Policies/policy.tsv"
        printf 'ROLE\tAUDIT\tDIAGNOSE\tDEPLOY\tDESTRUCTIVE\tFORENSIC\tVAULT\nViewer\tR\tR\t-\t-\t-\tR\nTechnician\tR\tR\tR\t-\t-\tRW\nSenior\tR\tR\tR\tCONFIRM\tR\tRW\nForensic\tR\tR\t-\t-\tRW\tRW\nAdmin\tRW\tRW\tR\tCONFIRM\tRW\tRW\nExpert\tRW\tRW\tR\tCONFIRM\tRW\tRW\n' > "${_pol_file}"
        SONAR_ROOT="${_pol_root}" "$self" --security-status >/dev/null 2>&1
        _pol_bak_count=$(find "${_pol_root}/Secure/Policies" -maxdepth 1 -name 'policy.tsv.bak.*' | wc -l)
        if [[ "$(awk -F'\t' '$1=="Technician"{print $NF}' "${_pol_file}")" == "-" ]] && [[ "${_pol_bak_count}" -eq 1 ]]; then
            printf 'PASS\tKnown-stale pre-2026-09-17 policy.tsv is auto-migrated with a timestamped backup\n'
        else
            printf 'FAIL\tKnown-stale policy.tsv was NOT migrated (or backup missing)\n'; errors=$((errors+1))
        fi
        rm -rf "${_pol_root}"
        _pol_root="$(mktemp -d)"
        mkdir -p "${_pol_root}/Secure/Policies"
        _pol_file="${_pol_root}/Secure/Policies/policy.tsv"
        printf 'ROLE\tAUDIT\tDIAGNOSE\tDEPLOY\tDESTRUCTIVE\tFORENSIC\tVAULT\nViewer\tR\tR\t-\t-\t-\t-\nTechnician\tR\tR\tR\t-\t-\tCUSTOM\nSenior\tR\tR\tR\tCONFIRM\tR\tRW\nForensic\tR\tR\t-\t-\tRW\tRW\nAdmin\tRW\tRW\tR\tCONFIRM\tRW\tRW\nExpert\tRW\tRW\tR\tCONFIRM\tRW\tRW\n' > "${_pol_file}"
        SONAR_ROOT="${_pol_root}" "$self" --security-status >/dev/null 2>&1
        _pol_bak_count=$(find "${_pol_root}/Secure/Policies" -maxdepth 1 -name 'policy.tsv.bak.*' | wc -l)
        if [[ "$(awk -F'\t' '$1=="Technician"{print $NF}' "${_pol_file}")" == "CUSTOM" ]] && [[ "${_pol_bak_count}" -eq 0 ]]; then
            printf 'PASS\tA non-default (customized) policy.tsv is left untouched, never overwritten\n'
        else
            printf 'FAIL\tA customized policy.tsv was modified when it should have been left alone\n'; errors=$((errors+1))
        fi
        rm -rf "${_pol_root}"
        # Ventoy theme : verifie que "file" dans ventoy.json pointe vers
        # theme.txt (script GRUB2), pas directement vers l'image PNG —
        # cause racine du crash "alloc magic is broken" identifiee le
        # 2026-09-16 (voir CHANGELOG.md). Structurel seulement : confirme
        # que SONAR genere les bons fichiers/references, pas que GRUB les
        # accepte reellement (ca, seul un vrai boot le confirme).
        local _vt_src _vt_mp _vt_json
        _vt_src="$(mktemp -d)"; _vt_mp="$(mktemp -d)"
        mkdir -p "${_vt_src}/Branding"
        printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x00\x03\x00\x01\x8f\xdb\x8e\xb0\x00\x00\x00\x00IEND\xaeB`\x82' > "${_vt_src}/Branding/background.png"
        ( SOURCE_DIR="${_vt_src}"; SONAR_ROOT="${_vt_src}"; INCLUDE_VENTOY_THEME=true
          SONAR_VENTOY_TITLE="Test"; SONAR_VENTOY_CREDIT="Test"
          log() { :; }; sonar_audit() { :; }
          source <(sonar_selftest_extract_fn "$self" sonar_prepare_ventoy_theme)
          sonar_prepare_ventoy_theme "${_vt_mp}" ) >/dev/null 2>&1
        if [[ -s "${_vt_mp}/ventoy/theme/theme.txt" ]] && grep -q 'desktop-image' "${_vt_mp}/ventoy/theme/theme.txt" && [[ -s "${_vt_mp}/ventoy/theme/background.png" ]]; then
            printf 'PASS\tVentoy theme.txt generated with desktop-image directive\n'
        else
            printf 'FAIL\tVentoy theme.txt missing or malformed\n'; errors=$((errors+1))
        fi
        # Regression 2026-09-20 : sans "+ boot_menu", GRUB n'affiche que le
        # fond d'ecran, aucun menu (constate sur materiel reel).
        if grep -q '^+ boot_menu {' "${_vt_mp}/ventoy/theme/theme.txt" 2>/dev/null; then
            printf 'PASS\tVentoy theme.txt declares a boot_menu component (menu is drawn)\n'
        else
            printf 'FAIL\tVentoy theme.txt has no boot_menu — GRUB would show the background only\n'; errors=$((errors+1))
        fi
        ( PERSISTENCE_COUNT=0
          source <(sonar_selftest_extract_fn "$self" generate_ventoy_json_final)
          generate_ventoy_json_final "${_vt_mp}" ) >/dev/null 2>&1
        _vt_json="${_vt_mp}/ventoy/ventoy.json"
        if [[ -s "${_vt_json}" ]] && grep -q '"file": "/ventoy/theme/theme.txt"' "${_vt_json}"; then
            printf 'PASS\tventoy.json theme.file points to theme.txt, not to the raw PNG\n'
        else
            printf 'FAIL\tventoy.json theme.file does not point to theme.txt as expected\n'; errors=$((errors+1))
        fi
        # 2026-09-22 : gfxmode essaie "auto" (resolution native via GOP/EDID) avant les repli
        # 1024x768/800x600 PROUVES fonctionnels sur materiel reel (voir CHANGELOG) — l'un des deux
        # doit rester joignable si "auto" echoue sur un firmware donne.
        if [[ -s "${_vt_json}" ]] && grep -q '"gfxmode": "auto,1024x768,800x600"' "${_vt_json}"; then
            printf 'PASS\tventoy.json gfxmode tries auto (native resolution) before the proven fallbacks\n'
        else
            printf 'FAIL\tventoy.json gfxmode missing "auto" or the proven fallback chain\n'; errors=$((errors+1))
        fi
        rm -rf "${_vt_src}" "${_vt_mp}"
        grep -q '^sonar_generate_build_watermark() {' "$self" && printf 'PASS\tBuild watermark module present\n' || { printf 'FAIL\tBuild watermark module missing\n'; errors=$((errors+1)); }
        local _wm_root _wm_mp
        _wm_root="$(mktemp -d)"; _wm_mp="$(mktemp -d)"
        ( export SONAR_ROOT="${_wm_root}"
          SONAR_SECURITY_DIR="${_wm_root}/Secure"
          SONAR_BUILD_SECRET_FILE="${SONAR_SECURITY_DIR}/Keys/build_secret.key"
          SONAR_BUILD_REGISTRY_FILE="${SONAR_SECURITY_DIR}/Keys/build_registry.tsv"
          SONAR_AUDIT_LOG="${SONAR_SECURITY_DIR}/Logs/audit.log"
          SONAR_HASHCHAIN_LOG="${SONAR_SECURITY_DIR}/Logs/hashchain.log"
          mkdir -p "${SONAR_SECURITY_DIR}/Logs"
          SONAR_ROLE="Technician"; SONAR_ROLE_IDENTITY="wm.trace.bot"; VOL="SELFTEST-USB"
          source <(sonar_selftest_extract_fn "$self" sonar_hash_str)
          source <(sonar_selftest_extract_fn "$self" sonar_hmac_sha256_file)
          source <(sonar_selftest_extract_fn "$self" sonar_const_time_eq)
          source <(sonar_selftest_extract_fn "$self" sonar_audit)
          source <(sonar_selftest_extract_fn "$self" sonar_build_secret_exists)
          source <(sonar_selftest_extract_fn "$self" sonar_ensure_build_secret)
          source <(sonar_selftest_extract_fn "$self" sonar_build_sign)
          source <(sonar_selftest_extract_fn "$self" sonar_generate_build_watermark)
          source <(sonar_selftest_extract_fn "$self" sonar_verify_build_watermark)
          log() { :; }; log_ok() { :; }
          local _rc
          if sonar_generate_build_watermark "${_wm_mp}" >/dev/null 2>&1; then :; fi
          if sonar_verify_build_watermark "${_wm_mp}" > "${_wm_root}/verify_ok.txt" 2>&1; then _rc=0; else _rc=$?; fi
          echo "${_rc}" > "${_wm_root}/verify_ok.rc"
          sed 's/SELFTEST-USB/FORGED-LABEL/' "${_wm_mp}/MANIFEST/BUILD_WATERMARK.txt" > "${_wm_root}/forged.txt"
          if sonar_verify_build_watermark "${_wm_root}/forged.txt" > "${_wm_root}/verify_forged.txt" 2>&1; then _rc=0; else _rc=$?; fi
          echo "${_rc}" > "${_wm_root}/verify_forged.rc"
        ) 2>/dev/null
        if [[ -s "${_wm_mp}/MANIFEST/BUILD_WATERMARK.txt" ]] \
           && grep -q '^0$' "${_wm_root}/verify_ok.rc" 2>/dev/null \
           && grep -q 'identity=wm.trace.bot' "${_wm_root}/Secure/Logs/audit.log" 2>/dev/null \
           && ! grep -q '^0$' "${_wm_root}/verify_forged.rc" 2>/dev/null; then
            printf 'PASS\tBuild watermark: generated, verified authentic, tampering detected\n'
        else
            printf 'FAIL\tBuild watermark generation/verification/tamper-detection did not behave as expected\n'; errors=$((errors+1))
        fi
        if grep -q 'BUILD_SECRET_CREATED' "${_wm_root}/Secure/Logs/audit.log" 2>/dev/null; then
            printf 'PASS\tsonar_ensure_build_secret logs BUILD_SECRET_CREATED on first use\n'
        else
            printf 'FAIL\tBUILD_SECRET_CREATED was not logged on first use of the build secret\n'; errors=$((errors+1))
        fi
        rm -rf "${_wm_root}" "${_wm_mp}"
        grep -q '^SONAR_PROFILES_TSV=' "$self" && printf 'PASS\tTroubleshooting profiles module present\n' || { printf 'FAIL\tTroubleshooting profiles module missing\n'; errors=$((errors+1)); }
        local _prof _prof_ok=true
        for _prof in boot-repair data-recovery malware disk-clone password-reset hardware-diagnostic peripherals-network general-os full; do
            if ! "$self" --profile "${_prof}" >/dev/null 2>&1; then
                printf 'FAIL\tProfile "%s" failed to document\n' "${_prof}"; errors=$((errors+1)); _prof_ok=false
            fi
        done
        [[ "${_prof_ok}" == "true" ]] && printf 'PASS\tAll nine troubleshooting profiles document scenario + tools\n'
        if "$self" --profile bogus-profile >/dev/null 2>&1; then
            printf 'FAIL\tUnknown profile name was NOT rejected\n'; errors=$((errors+1))
        else
            printf 'PASS\tUnknown profile name is rejected\n'
        fi
        local _full_out
        _full_out="$("$self" --profile full 2>/dev/null)"
        if grep -q 'SystemRescue' <<<"${_full_out}" && grep -q 'chntpw' <<<"${_full_out}" && grep -q 'ClamAV' <<<"${_full_out}" && grep -q 'Memtest86+' <<<"${_full_out}" && grep -q 'CrystalDiskInfo' <<<"${_full_out}" && grep -q 'Rufus' <<<"${_full_out}" && grep -q 'Process Explorer' <<<"${_full_out}" && grep -q 'Android Platform Tools' <<<"${_full_out}" && grep -q 'CAINE' <<<"${_full_out}"; then
            printf 'PASS\tProfile "full" is the union of all profiles\n'
        else
            printf 'FAIL\tProfile "full" does not include tools from all sub-profiles\n'; errors=$((errors+1))
        fi
        _full_out="$("$self" --profile boot-repair 2>/dev/null)"
        if grep -q 'LIMITE CONNUE' <<<"${_full_out}" && grep -q 'WinPE' <<<"${_full_out}"; then
            printf 'PASS\tboot-repair profile discloses the WinPE gap (docs/WINPE.md)\n'
        else
            printf 'FAIL\tboot-repair profile does not disclose the WinPE gap\n'; errors=$((errors+1))
        fi
        _full_out="$("$self" --profile password-reset 2>/dev/null)"
        if grep -q 'LIMITE CONNUE' <<<"${_full_out}" && grep -qi 'BIOS' <<<"${_full_out}"; then
            printf 'PASS\tpassword-reset profile discloses the BIOS/UEFI password gap\n'
        else
            printf 'FAIL\tpassword-reset profile does not disclose the BIOS/UEFI password gap\n'; errors=$((errors+1))
        fi
        grep -q '^SONAR_FETCH_MANIFEST_TSV=' "$self" && printf 'PASS\tFetch manifest module present\n' || { printf 'FAIL\tFetch manifest module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_fetch_profile() {' "$self" && printf 'PASS\tFetch profile function present\n' || { printf 'FAIL\tFetch profile function missing\n'; errors=$((errors+1)); }
        local _fm_dir _fm_out
        _fm_dir="$(mktemp -d)"
        local _fm_rc=0
        _fm_out="$(SONAR_ROOT="${_fm_dir}" "$self" --fetch boot-repair 2>&1)" || _fm_rc=$?
        if [[ "${_fm_rc}" -ne 0 ]] && ! grep -qF 'Téléchargement: ' <<<"${_fm_out}"; then
            printf 'PASS\t--fetch refuses to run against an unsealed manifest (no network attempted)\n'
        else
            printf 'FAIL\t--fetch did not refuse an unsealed manifest as expected\n'; errors=$((errors+1))
        fi
        # Structurel plutot qu'un vrai appel reseau (qui ajouterait ~20s a
        # chaque --self-test pour un serveur injoignable reel) : verifie que
        # le correctif est present dans la commande curl elle-meme.
        if grep -qE 'curl -fL --connect-timeout [0-9]+ --max-time [0-9]+' "$self"; then
            printf 'PASS\tsonar_fetch_one_tool curl call has --connect-timeout/--max-time\n'
        else
            printf 'FAIL\tsonar_fetch_one_tool curl call is missing --connect-timeout/--max-time\n'; errors=$((errors+1))
        fi
        # --fetch : post-traitement des archives (rendre les outils utilisables). Fixtures locales,
        # aucun reseau ; sonar_fetch_postprocess n'est appele que sur une archive deja verifiee.
        # Les checks a base de zip/dpkg-deb sont ignores (WARN) si l'outil de fabrication manque.
        local _pp_dir _pp_out
        _pp_dir="$(mktemp -d)"
        (
            ISO_SOURCE_DIR="${_pp_dir}/ISO"; PORTABLE_SOURCE_DIR="${_pp_dir}/Portable"; mkdir -p "${ISO_SOURCE_DIR}" "${PORTABLE_SOURCE_DIR}"
            _pp_ok=0
            _t() { if eval "$2"; then printf 'PASS\t%s\n' "$1"; else printf 'FAIL\t%s\n' "$1"; _pp_ok=$((_pp_ok+1)); fi; }
            _w="${_pp_dir}/work"; mkdir -p "${_w}/src"
            # -- ISO dans un zip (Memtest86+, chntpw)
            if command -v zip >/dev/null 2>&1; then
                printf 'ISO9660-FAKE' > "${_w}/src/mt.iso"; ( cd "${_w}/src" && zip -q "${_w}/mt.zip" mt.iso )
                sonar_fetch_postprocess "Memtest86+" "${_w}/mt.zip" "sha-mt" >/dev/null 2>&1
                _t "Fetch postprocess : un zip contenant une ISO -> ISO/Fetched (ISO_EXTRACTED)" '[[ "${SONAR_FETCH_STATE}" == ISO_EXTRACTED && -s "${ISO_SOURCE_DIR}/Fetched/mt.iso" ]]'
                mkdir -p "${_w}/tool"; printf 'exe' > "${_w}/tool/Autoruns.exe"; printf 'x' > "${_w}/tool/readme.txt"; ( cd "${_w}/tool" && zip -q "${_w}/Autoruns.zip" Autoruns.exe readme.txt )
                sonar_fetch_postprocess "Process Explorer" "${_w}/Autoruns.zip" "sha-ar" >/dev/null 2>&1
                _t "Fetch postprocess : un zip d'outil -> Portable/<Outil>/ (EXTRACTED)" '[[ "${SONAR_FETCH_STATE}" == EXTRACTED && -s "${PORTABLE_SOURCE_DIR}/Process_Explorer/Autoruns.exe" ]]'
                _o="$(sonar_fetch_postprocess "Process Explorer" "${_w}/Autoruns.zip" "sha-ar" 2>&1)"
                _t "Fetch postprocess : idempotent (meme SHA-256 -> pas de re-extraction)" 'grep -q "deja extrait" <<<"${_o}"'
            else
                printf 'WARN\tFetch postprocess : zip absent, cas .zip non teste ici\n'
            fi
            # -- code source : jamais presente comme utilisable
            : > "${_w}/ddrescue-1.30.tar.lz"
            sonar_fetch_postprocess "ddrescue" "${_w}/ddrescue-1.30.tar.lz" "sha-dd" >/dev/null 2>&1
            _t "Fetch postprocess : archive .tar.lz -> SOURCE_ONLY (dit que ce n'est pas un binaire)" '[[ "${SONAR_FETCH_STATE}" == SOURCE_ONLY && ! -e "${PORTABLE_SOURCE_DIR}/ddrescue" ]]'
            # -- fichiers directement utilisables
            printf 'x' > "${_w}/rufus.exe"; sonar_fetch_postprocess "Rufus" "${_w}/rufus.exe" "sha-r" >/dev/null 2>&1
            _t "Fetch postprocess : un .exe / .iso est deja READY" '[[ "${SONAR_FETCH_STATE}" == READY ]]'
            # -- extraction sure : entree ".." refusee, rien n'ecrit hors du dossier
            printf 'evil' > "${_w}/src/evil.txt"
            tar -cf "${_w}/slip.tar.gz" --transform 's|^|../|' -C "${_w}/src" evil.txt 2>/dev/null
            sonar_fetch_postprocess "Piege" "${_w}/slip.tar.gz" "sha-s" >/dev/null 2>&1
            _t "Fetch postprocess : entree '../' dans une archive -> REFUSEE, rien ecrit dehors" '[[ "${SONAR_FETCH_STATE}" == MANUAL && ! -e "${PORTABLE_SOURCE_DIR}/../evil.txt" && ! -e "${_pp_dir}/evil.txt" && ! -d "${PORTABLE_SOURCE_DIR}/Piege" ]]'
            ln -s /etc/passwd "${_w}/src/lien"; tar -czf "${_w}/link.tar.gz" -C "${_w}/src" lien evil.txt
            sonar_fetch_postprocess "Lien" "${_w}/link.tar.gz" "sha-l" >/dev/null 2>&1
            _t "Fetch postprocess : un lien symbolique sortant est supprime a l'extraction" '[[ ! -L "${PORTABLE_SOURCE_DIR}/Lien/lien" && -s "${PORTABLE_SOURCE_DIR}/Lien/evil.txt" ]]'
            # -- ClamAV (.deb) : extrait, elague, lanceurs poses, refuse de tourner sans signatures
            if command -v dpkg-deb >/dev/null 2>&1; then
                mkdir -p "${_w}/deb/usr/local/bin" "${_w}/deb/usr/local/lib" "${_w}/deb/usr/local/include" "${_w}/deb/DEBIAN"
                printf '#!/bin/sh\necho "ClamAV fake $*"\n' > "${_w}/deb/usr/local/bin/clamscan"; cp "${_w}/deb/usr/local/bin/clamscan" "${_w}/deb/usr/local/bin/freshclam"
                chmod +x "${_w}/deb/usr/local/bin/"*; printf 'h' > "${_w}/deb/usr/local/include/x.h"; printf 'a' > "${_w}/deb/usr/local/lib/libx.a"; printf 'so' > "${_w}/deb/usr/local/lib/libx.so"
                printf 'Package: clamav\nVersion: 1\nArchitecture: amd64\nMaintainer: t <t@t>\nDescription: fake\n' > "${_w}/deb/DEBIAN/control"
                chmod 755 "${_w}/deb" "${_w}/deb/DEBIAN"   # umask 077 du script : dpkg-deb exige >= 0755
                dpkg-deb -b "${_w}/deb" "${_w}/clamav-1.5.4.linux.x86_64.deb" >/dev/null 2>&1
                sonar_fetch_postprocess "ClamAV" "${_w}/clamav-1.5.4.linux.x86_64.deb" "sha-c" >/dev/null 2>&1
                _t "Fetch postprocess : ClamAV .deb -> WRAPPED, lanceurs poses, en-tetes/.a retires" '[[ "${SONAR_FETCH_STATE}" == WRAPPED && -x "${PORTABLE_SOURCE_DIR}/ClamAV/sonar-clamscan.sh" && -x "${PORTABLE_SOURCE_DIR}/ClamAV/sonar-freshclam.sh" && ! -e "${PORTABLE_SOURCE_DIR}/ClamAV/usr/local/include" && ! -e "${PORTABLE_SOURCE_DIR}/ClamAV/usr/local/lib/libx.a" && -e "${PORTABLE_SOURCE_DIR}/ClamAV/usr/local/lib/libx.so" ]]'
                _t "Fetch postprocess : sonar-clamscan.sh refuse de tourner sans signatures (code 2, message clair)" '_o="$(sh "${PORTABLE_SOURCE_DIR}/ClamAV/sonar-clamscan.sh" x 2>&1)"; [[ $? -eq 2 ]] && grep -q "sonar-freshclam.sh" <<<"${_o}"'
                : > "${PORTABLE_SOURCE_DIR}/ClamAV/db/main.cvd"
                _t "Fetch postprocess : avec une base de signatures, clamscan est lance depuis la copie portable" '_o="$(sh "${PORTABLE_SOURCE_DIR}/ClamAV/sonar-clamscan.sh" --version 2>&1)"; grep -q "ClamAV fake" <<<"${_o}"'
            else
                printf 'WARN\tFetch postprocess : dpkg-deb absent, cas ClamAV .deb non teste ici\n'
            fi
            # -- ClamAV (Windows, .zip) : sous-dossier versionne aplati, elague, lanceurs .cmd poses, DLL gardees
            if command -v zip >/dev/null 2>&1; then
                mkdir -p "${_w}/winzip/clamav-1.5.4.win.x64/certs" "${_w}/winzip/clamav-1.5.4.win.x64/conf_examples"
                printf 'fake exe' > "${_w}/winzip/clamav-1.5.4.win.x64/clamscan.exe"
                printf 'fake exe' > "${_w}/winzip/clamav-1.5.4.win.x64/sigtool.exe"
                printf 'fake exe' > "${_w}/winzip/clamav-1.5.4.win.x64/freshclam.exe"
                printf 'fake exe' > "${_w}/winzip/clamav-1.5.4.win.x64/clamd.exe"
                printf 'dll' > "${_w}/winzip/clamav-1.5.4.win.x64/libclamav.dll"
                printf 'pdb' > "${_w}/winzip/clamav-1.5.4.win.x64/libclamav.pdb"
                ( cd "${_w}/winzip" && zip -qr "${_w}/clamav-1.5.4.win.x64.zip" clamav-1.5.4.win.x64 )
                sonar_fetch_postprocess "ClamAV-Windows" "${_w}/clamav-1.5.4.win.x64.zip" "sha-w" >/dev/null 2>&1
                _t "Fetch postprocess : ClamAV .zip Windows -> WRAPPED, sous-dossier aplati, .pdb/clamd.exe retires" '[[ "${SONAR_FETCH_STATE}" == WRAPPED && -f "${PORTABLE_SOURCE_DIR}/ClamAV-Windows/clamscan.exe" && -f "${PORTABLE_SOURCE_DIR}/ClamAV-Windows/libclamav.dll" && ! -e "${PORTABLE_SOURCE_DIR}/ClamAV-Windows/libclamav.pdb" && ! -e "${PORTABLE_SOURCE_DIR}/ClamAV-Windows/clamd.exe" && ! -d "${PORTABLE_SOURCE_DIR}/ClamAV-Windows/clamav-1.5.4.win.x64" ]]'
                _t "Fetch postprocess : sonar-clamscan.cmd refuse (dans son texte) de tourner sans base de signatures" 'grep -q "sonar-freshclam.cmd" "${PORTABLE_SOURCE_DIR}/ClamAV-Windows/sonar-clamscan.cmd"'
            else
                printf 'WARN\tFetch postprocess : zip absent, cas ClamAV-Windows .zip non teste ici\n'
            fi
            exit "${_pp_ok}"
        ) > "${_pp_dir}/out.txt" 2>&1
        _pp_rc=$?
        cat "${_pp_dir}/out.txt"
        errors=$((errors + _pp_rc))
        rm -rf "${_pp_dir}"
        SONAR_ROOT="${_fm_dir}" "$self" --role-bootstrap >/dev/null 2>&1
        local _fm_token
        # "Vault" n'est PAS un nom de role valide (known="Viewer Technician
        # Senior Forensic Admin Expert" dans sonar_role_issue_token) — c'etait
        # une confusion avec VAULT, le nom de la COLONNE de policy.tsv. Avec
        # un role invalide, --role-issue-token echouait silencieusement
        # (jeton vide), SONAR_ROLE=Vault retombait sur Technician via le
        # downgrade de sonar_role_enforce_lock, et ce test ne passait que
        # parce que Technician avait alors un acces VAULT non restreint —
        # exactement le bug corrige le 2026-09-17 (voir plus haut,
        # policy.tsv). Corrige pour utiliser un vrai role eleve (Admin).
        _fm_token="$(SONAR_ROOT="${_fm_dir}" "$self" --role-issue-token Admin fetch.selftest.bot 1 2>/dev/null)"
        if SONAR_ROOT="${_fm_dir}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_fm_token}" "$self" --fetch-manifest-seal >/dev/null 2>&1 \
           && SONAR_ROOT="${_fm_dir}" "$self" --fetch-manifest-verify-seal >/dev/null 2>&1; then
            printf 'PASS\tFetch manifest seal/verify round-trip works (role VAULT)\n'
        else
            printf 'FAIL\tFetch manifest seal/verify round-trip did not behave as expected\n'; errors=$((errors+1))
        fi
        # Non-regression du bug corrige le 2026-09-17 : un role libre-service
        # (Technician, sans jeton) doit etre REFUSE par --fetch-manifest-seal.
        # Avant le fix, policy.tsv donnait VAULT=RW a Technician et cette
        # commande reussissait sans aucune elevation.
        local _fm_dir2
        _fm_dir2="$(mktemp -d)"
        if SONAR_ROOT="${_fm_dir2}" "$self" --fetch-manifest-seal >/dev/null 2>&1; then
            printf 'FAIL\t--fetch-manifest-seal succeeded for Technician without a token (VAULT not enforced)\n'; errors=$((errors+1))
        else
            printf 'PASS\t--fetch-manifest-seal rejects a self-service role without a token\n'
        fi
        rm -rf "${_fm_dir2}"
        rm -rf "${_fm_dir}"
        local _hash_tmp _hash_known
        _hash_tmp="$(mktemp)"
        printf 'sonar-fetch-selftest' > "${_hash_tmp}"
        _hash_known="$(sha256_final "${_hash_tmp}")"
        if sonar_fetch_sha256_matches "${_hash_tmp}" "${_hash_known}" && ! sonar_fetch_sha256_matches "${_hash_tmp}" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"; then
            printf 'PASS\tsonar_fetch_sha256_matches accepts correct hash and rejects wrong hash\n'
        else
            printf 'FAIL\tsonar_fetch_sha256_matches did not behave as expected\n'; errors=$((errors+1))
        fi
        rm -f "${_hash_tmp}"
        grep -q '^sonar_export_field_files() {' "$self" && printf 'PASS\tSONAR Field export function present\n' || { printf 'FAIL\tSONAR Field export function missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_field_pin_set() {' "$self" && printf 'PASS\tSONAR Field PIN-set function present\n' || { printf 'FAIL\tSONAR Field PIN-set function missing\n'; errors=$((errors+1)); }
        local _fld_dir
        _fld_dir="$(mktemp -d)"
        sonar_export_field_files "${_fld_dir}" >/dev/null 2>&1
        if bash -n "${_fld_dir}/Scripts/sonar_field.sh" 2>/dev/null; then
            printf 'PASS\tGenerated sonar_field.sh passes bash -n\n'
        else
            printf 'FAIL\tGenerated sonar_field.sh has a syntax error\n'; errors=$((errors+1))
        fi
        if [[ -s "${_fld_dir}/MANIFEST/PROFILES.tsv" && -s "${_fld_dir}/MANIFEST/PROFILES_SCENARIOS.tsv" ]]; then
            printf 'PASS\tSONAR Field profile exports (PROFILES.tsv + PROFILES_SCENARIOS.tsv) present\n'
        else
            printf 'FAIL\tSONAR Field profile exports missing\n'; errors=$((errors+1))
        fi
        local _fld_out
        _fld_out="$(echo q | bash "${_fld_dir}/Scripts/sonar_field.sh" "${_fld_dir}" 2>&1)"
        if grep -q 'que dois-je depanner' <<<"${_fld_out}" && grep -q 'ATTENTION.*PIN' <<<"${_fld_out}"; then
            printf 'PASS\tsonar_field.sh smoke test (menu displays, warns about unset PIN, quits cleanly)\n'
        else
            printf 'FAIL\tsonar_field.sh smoke test did not behave as expected\n'; errors=$((errors+1))
        fi
        if [[ -x "${_fld_dir}/Scripts/sonar_diag.sh" && -s "${_fld_dir}/Scripts/diag_engine.awk" && -s "${_fld_dir}/MANIFEST/DIAG_RULES.txt" ]] \
           && grep -q 'DIAGNOSTIC INTELLIGENT' <<<"${_fld_out}"; then
            printf 'PASS\tSONAR Field deploys the intelligent diagnostic (script + rules) and offers it in its menu\n'
        else
            printf 'FAIL\tSONAR Field export is missing the intelligent diagnostic (Scripts/sonar_diag.sh, MANIFEST/DIAG_RULES.txt, menu entry d)\n'; errors=$((errors+1))
        fi
        if [[ -s "${_fld_dir}/Scripts/client_report.awk" && -s "${_fld_dir}/Scripts/text2pdf.awk" && -s "${_fld_dir}/MANIFEST/CLIENT_TEMPLATES.txt" ]] \
           && grep -q 'RAPPORT CLIENT' <<<"${_fld_out}"; then
            printf 'PASS\tSONAR Field deploys the client report (awk programs + templates) and offers it in its menu\n'
        else
            printf 'FAIL\tSONAR Field export is missing the client report (Scripts/client_report.awk, Scripts/text2pdf.awk, MANIFEST/CLIENT_TEMPLATES.txt, menu entry c)\n'; errors=$((errors+1))
        fi
        if [[ -x "${_fld_dir}/Scripts/sonar_bitlocker.sh" ]] && grep -q 'BITLOCKER' <<<"${_fld_out}"; then
            printf 'PASS\tSONAR Field deploys the BitLocker unlock (read-only) and offers it in its menu\n'
        else
            printf 'FAIL\tSONAR Field export is missing the BitLocker unlock (Scripts/sonar_bitlocker.sh, menu entry b)\n'; errors=$((errors+1))
        fi
        # Regression : chaque outil de tools/ a sa PROPRE garde a l'export. Un outil absent ne doit jamais en
        # empecher un autre (bug corrige : sonar_recover.sh etait copie a l'interieur du if de sonar_bitlocker.sh).
        local _gx_dir _gx_tool _gx_other _gx_bad=0
        _gx_dir="$(mktemp -d)"
        for _gx_tool in sonar_bitlocker.sh sonar_recover.sh sonar_diag.sh; do
            rm -rf "${_gx_dir}/s" "${_gx_dir}/mp"; mkdir -p "${_gx_dir}/s" "${_gx_dir}/mp"
            cp -r "${SONAR_SCRIPT_DIR}/tools" "${_gx_dir}/s/tools"; rm -f "${_gx_dir}/s/tools/${_gx_tool}"
            ( SONAR_SCRIPT_DIR="${_gx_dir}/s"; sonar_export_field_files "${_gx_dir}/mp" ) >/dev/null 2>&1
            for _gx_other in sonar_bitlocker.sh sonar_recover.sh sonar_diag.sh; do
                [[ "$_gx_other" == "$_gx_tool" ]] && continue
                [[ -f "${_gx_dir}/mp/Scripts/${_gx_other}" ]] || { _gx_bad=$((_gx_bad+1)); printf 'FAIL\tField export: sans tools/%s, %s n a PAS ete copie sur la cle\n' "$_gx_tool" "$_gx_other"; }
            done
            [[ ! -f "${_gx_dir}/mp/Scripts/${_gx_tool}" ]] || { _gx_bad=$((_gx_bad+1)); printf 'FAIL\tField export: %s copie alors que la source est absente\n' "$_gx_tool"; }
        done
        rm -rf "${_gx_dir}"
        if [[ $_gx_bad -eq 0 ]]; then
            printf 'PASS\tField export: chaque outil (bitlocker, recover, diag) est copie independamment des autres\n'
        else
            errors=$((errors + _gx_bad))
        fi
        if [[ -x "${_fld_dir}/Scripts/sonar_recover.sh" ]] && grep -q 'RÉCUPÉRATION DE DONNÉES' <<<"${_fld_out}"; then
            printf 'PASS\tSONAR Field deploys the data recovery tool and offers it in its menu\n'
        else
            printf 'FAIL\tSONAR Field export is missing the data recovery tool (Scripts/sonar_recover.sh, menu entry r)\n'; errors=$((errors+1))
        fi
        local _fps_root _fps_out _fps_token
        _fps_root="$(mktemp -d)"
        # --field-pin-set exige desormais un vrai role eleve (VAULT verrouille
        # pour Technician, voir policy.tsv ci-dessus) — "Technicien"/"Admin"
        # passes en argument sont des NIVEAUX SONAR Field (concept distinct,
        # non lie a SONAR_ROLE), donnes tels quels ; le ROLE de l'appelant,
        # lui, doit etre eleve.
        SONAR_ROOT="${_fps_root}" "$self" --role-bootstrap >/dev/null 2>&1
        _fps_token="$(SONAR_ROOT="${_fps_root}" "$self" --role-issue-token Admin fieldpin.selftest.bot 1 2>/dev/null)"
        _fps_out="$(SONAR_ROOT="${_fps_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_fps_token}" "$self" --field-pin-set Technicien abc 2>&1)"
        if [[ ! -s "${_fps_root}/Secure/Vault/field_pins.tsv" ]] && grep -qi 'court' <<<"${_fps_out}"; then
            printf 'PASS\t--field-pin-set rejects a too-short PIN\n'
        else
            printf 'FAIL\t--field-pin-set did not reject a too-short PIN\n'; errors=$((errors+1))
        fi
        _fps_out="$(SONAR_ROOT="${_fps_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_fps_token}" "$self" --field-pin-set Technicien 1234 boot-repair,data-recovery 2>&1)"
        if [[ -s "${_fps_root}/Secure/Vault/field_pins.tsv" ]] && grep -q 'Technicien' "${_fps_root}/Secure/Vault/field_pins.tsv"; then
            printf 'PASS\t--field-pin-set accepts a valid PIN+niveau+profils and writes the file\n'
        else
            printf 'FAIL\t--field-pin-set did not write the pins file for a valid call\n'; errors=$((errors+1))
        fi
        _fps_out="$(SONAR_ROOT="${_fps_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_fps_token}" "$self" --field-pin-set Technicien 1234 profil-bidon 2>&1)"
        if ! grep -q 'profil-bidon' "${_fps_root}/Secure/Vault/field_pins.tsv" && grep -qi 'inconnu' <<<"${_fps_out}"; then
            printf 'PASS\t--field-pin-set rejects an unknown profile name\n'
        else
            printf 'FAIL\t--field-pin-set did not reject an unknown profile name\n'; errors=$((errors+1))
        fi
        SONAR_ROOT="${_fps_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_fps_token}" "$self" --field-pin-set Admin 5678 >/dev/null 2>&1
        if [[ "$(awk -F'\t' 'END{print NR}' "${_fps_root}/Secure/Vault/field_pins.tsv")" -eq 2 ]]; then
            printf 'PASS\t--field-pin-set accumulates a second niveau without overwriting the first\n'
        else
            printf 'FAIL\t--field-pin-set did not accumulate a second niveau correctly\n'; errors=$((errors+1))
        fi
        # Bout en bout : niveau restreint ne voit que ses profils, niveau ALL les voit tous.
        _fld_dir="$(mktemp -d)"
        sonar_export_field_files "${_fld_dir}" >/dev/null 2>&1
        cp "${_fps_root}/Secure/Vault/field_pins.tsv" "${_fld_dir}/MANIFEST/FIELD_PINS.tsv"
        _fld_out="$(printf '1234\nTesteur\nq\n' | bash "${_fld_dir}/Scripts/sonar_field.sh" "${_fld_dir}" 2>&1)"
        if grep -q 'boot-repair' <<<"${_fld_out}" && ! grep -q 'malware' <<<"${_fld_out}"; then
            printf 'PASS\tRestricted niveau (Technicien) only sees its allowed profiles in the menu\n'
        else
            printf 'FAIL\tRestricted niveau did not filter the menu as expected\n'; errors=$((errors+1))
        fi
        _fld_out="$(printf '5678\nTesteur\nq\n' | bash "${_fld_dir}/Scripts/sonar_field.sh" "${_fld_dir}" 2>&1)"
        if grep -q 'boot-repair' <<<"${_fld_out}" && grep -q 'malware' <<<"${_fld_out}"; then
            printf 'PASS\tALL niveau (Admin) sees every profile in the menu\n'
        else
            printf 'FAIL\tALL niveau did not see every profile\n'; errors=$((errors+1))
        fi
        # --field-export : commande indépendante (pas d'appel direct à
        # sonar_export_field_files) — teste le vrai chemin de dispatch CLI,
        # y compris la validation d'arguments et la copie du fichier PINs.
        local _fe_out _fe_dir
        local _fe_iso; _fe_iso="$(mktemp -d)"
        _fe_out="$(SONAR_ROOT="${_fe_iso}" "$self" --field-export 2>&1)"; rm -rf "${_fe_iso}"
        if [[ $? -ne 0 || -n "$(grep -i 'nécessite un point de montage' <<<"${_fe_out}")" ]]; then
            printf 'PASS\t--field-export rejects a missing mount-point argument\n'
        else
            printf 'FAIL\t--field-export did not reject a missing argument\n'; errors=$((errors+1))
        fi
        _fe_dir="$(mktemp -d)"
        _fe_out="$(SONAR_ROOT="${_fps_root}" "$self" --field-export "${_fe_dir}" 2>&1)"
        if [[ -s "${_fe_dir}/MANIFEST/PROFILES.tsv" && -x "${_fe_dir}/Scripts/sonar_field.sh" && -s "${_fe_dir}/MANIFEST/FIELD_PINS.tsv" ]]; then
            printf 'PASS\t--field-export writes profiles, script and PINs file to an existing key\n'
        else
            printf 'FAIL\t--field-export did not write the expected files\n'; errors=$((errors+1))
        fi
        rm -rf "${_fe_dir}"
        rm -rf "${_fld_dir}" "${_fps_root}"
        echo
        echo "ERRORS=$errors"
        echo "WARNINGS=$warnings"
        echo 'BOOT_STATUS=NOT_TESTED'
        echo 'HARDWARE_STATUS=NOT_TESTED'
    } > "$out"
    cat "$out" >&3
    exec 3>&-
    (( errors == 0 ))
}

sonar_recovery_plan() {
    sonar_report_init
    local ts out="${SONAR_REPORT_DIR}/recovery/SONAR_RECOVERY_PLAN_$(sonar_timestamp).txt"
    cat > "$out" <<'EOF'
SONAR RECOVERY PLAN
===================

RULE: DIAGNOSTIC -> BACKUP/ACQUISITION -> REPAIR -> VERIFY -> REPORT

WINDOWS / WINPE / WINRE
- Identify the Windows installation.
- Collect boot/filesystem diagnostics.
- Preserve important data before repair.
- Use DISM/SFC/BCDEdit/boot-repair procedures only after confirmation.
- Reboot/test after repair.

LINUX LIVE / RESCUE
- Identify root/boot partitions.
- Mount read-only first when investigation is required.
- Preserve data before filesystem repair.
- Use fsck/chroot/boot repair only after target confirmation.

DATA RECOVERY
- Prefer imaging/acquisition before repeated filesystem writes.
- Use TestDisk/PhotoRec/ddrescue or equivalent tools according to the case.
- Keep source and destination distinct.

MACOS
- Distinguish Intel and Apple Silicon.
- Use Apple Recovery/createinstallmedia procedures where appropriate.
- Do not claim generic ISO replacement of Apple recovery media.

SONAR does not execute these actions automatically from AI recommendations.
EOF
    echo "[SONAR] Recovery plan: $out"
}

sonar_backup_plan() {
    sonar_report_init
    local out="${SONAR_REPORT_DIR}/recovery/SONAR_BACKUP_CLONE_PLAN_$(sonar_timestamp).txt"
    cat > "$out" <<'EOF'
SONAR BACKUP / CLONE SAFETY PLAN
===============================

PRECHECK
1. Identify source.
2. Identify destination.
3. Verify source != destination.
4. Verify destination capacity.
5. Prefer dry-run.
6. Confirm overwrite explicitly.
7. Record hashes where appropriate.

ORDER
SOURCE -> IMAGE/CLONE -> VERIFY -> REPORT

The operational disk deployment engine remains separate from this planning
layer. No destructive clone/restore is executed by this command.
EOF
    echo "[SONAR] Backup/Clone plan: $out"
}

sonar_forensic_workspace() {
    sonar_report_init
    local ts root
    ts="$(sonar_timestamp)"; root="${SONAR_REPORT_DIR}/forensic/${ts}"
    mkdir -p "$root/evidence" "$root/hashes" "$root/logs" "$root/reports"
    cat > "$root/README_FORENSIC.txt" <<EOF
SONAR FORENSIC WORKSPACE
========================
Created: $(sonar_iso_now)

Acquisition -> Hash -> Preserve -> Analyze -> Report

Do not modify the evidence source intentionally during acquisition.
Keep evidence and working copies separate.
EOF
    sonar_audit "FORENSIC_WORKSPACE" "path=${root}"
    echo "[SONAR] Forensic workspace: $root"
}

sonar_network_diagnostic() {
    sonar_report_init
    local out="${SONAR_REPORT_DIR}/network/SONAR_NETWORK_$(sonar_timestamp).txt"
    {
        echo 'SONAR NETWORK DIAGNOSTIC'
        echo '========================'
        echo "Date: $(sonar_iso_now)"
        echo
        if command -v ip >/dev/null 2>&1; then
            echo '[INTERFACES]'; ip -brief address 2>/dev/null || true
            echo '[ROUTES]'; ip route 2>/dev/null || true
        elif command -v ifconfig >/dev/null 2>&1; then
            echo '[INTERFACES]'; ifconfig 2>/dev/null || true
        fi
        echo '[DNS]'
        [[ -f /etc/resolv.conf ]] && cat /etc/resolv.conf || true
        echo '[CONNECTIVITY]'
        if command -v curl >/dev/null 2>&1; then curl -I --max-time 5 https://example.com 2>&1 | head -n 8 || true; fi
        echo
        echo 'This module performs diagnostics only; it does not run intrusive scans.'
    } > "$out"
    sonar_audit "NETWORK_DIAGNOSTIC" "report=${out}"
    echo "[SONAR] Network report: $out"
}

sonar_builder_v2() {
    sonar_report_init
    local profile="${SONAR_PROFILE:-FULL}"; local root="${SONAR_BUILD_DIR}/$(sonar_safe_name "$profile")"; local ts
    ts="$(sonar_timestamp)"
    mkdir -p "$root"/{CORE,LAUNCHER,DIAGNOSTIC,RECOVERY,BACKUP,FORENSIC,NETWORK,HARDWARE,WINDOWS,LINUX,MACOS,AI,SELFTEST,MANIFEST,DOCS,ISO,PORTABLE,SCRIPTS,DRIVERS,Logs}
    cp -f "${BASH_SOURCE[0]}" "$root/CORE/sonar-master.sh"
    chmod +x "$root/CORE/sonar-master.sh"
    if [[ -d "$SOURCE_DIR" ]]; then
        for d in ISO Portable Scripts Drivers macOS; do
            [[ -d "${SOURCE_DIR}/${d}" ]] && cp -a "${SOURCE_DIR}/${d}" "$root/" || true
        done
        [[ -f "${MANIFEST_SOURCE}" ]] && cp -f "${MANIFEST_SOURCE}" "$root/MANIFEST/MANIFEST.tsv"
    fi
    cat > "$root/VERSION" <<EOF
${SONAR_VERSION}
PROFILE=${profile}
BUILT=$(sonar_iso_now)
STATUS=BUILD_CANDIDATE
EOF
    cat > "$root/README.md" <<'EOF'
# SONAR Operational Build

This is a build candidate generated by SONAR Builder.

Modules: Core, Launcher, Diagnostic, Recovery, Backup, Forensic, Network,
Hardware, Windows, Linux, macOS, AI, Self-Test, Manifest.

Hardware/boot compatibility requires real-device validation.
EOF
    (cd "$root" && find . -type f -print0 | sort -z | xargs -0 sha256sum > MANIFEST/FILES.sha256)
    # A heredoc never interprets \t as a real tab (only $()/${} expand here) —
    # printf does, keeping this TSV consistent with every other one the file
    # writes (e.g. FILES.sha256's manifest just above).
    {
        printf 'FIELD\tVALUE\n'
        printf 'VERSION\t%s\n' "${SONAR_VERSION}"
        printf 'PROFILE\t%s\n' "${profile}"
        printf 'BUILT\t%s\n' "$(sonar_iso_now)"
        printf 'STATUS\tBUILD_CANDIDATE\n'
    } > "$root/MANIFEST/BUILD_INFO.tsv"
    sonar_audit "BUILDER" "profile=${profile};root=${root}"
    echo "[SONAR] Build candidate: $root"
}

sonar_release_report() {
    sonar_report_init
    local out="${SONAR_REPORT_DIR}/release/SONAR_RELEASE_REPORT_$(sonar_timestamp).txt"
    local hash="$(sonar_hash "${BASH_SOURCE[0]}" 2>/dev/null || echo unavailable)"
    {
        echo 'SONAR RELEASE REPORT'
        echo '===================='
        echo "Version: ${SONAR_VERSION}"
        echo "Date: $(sonar_iso_now)"
        echo "Script SHA256: ${hash}"
        echo
        echo 'Implemented operational layers:'
        echo '- Core security / roles / audit / hash chain'
        echo '- Ventoy deployment and persistence'
        echo '- AI/Ollama discovery, audit and verified download pipeline'
        echo '- Launcher'
        echo '- Diagnostic'
        echo '- Recovery planning'
        echo '- Backup/Clone safety planning'
        echo '- Forensic workspace'
        echo '- Network diagnostics'
        echo '- Hardware reporting'
        echo '- Builder'
        echo '- Self-Test'
        echo '- Manifest / integrity'
        echo '- Smart Advisor (deterministic rules engine)'
        echo '- Hashchain verification'
        echo '- Catalog seal / tamper detection'
        echo '- Post-deploy hash re-verification'
        echo
        echo 'NOT YET PROVEN:'
        echo '- Universal UEFI compatibility'
        echo '- Universal Secure Boot compatibility'
        echo '- Universal Windows/WinPE/WinRE boot'
        echo '- Universal Linux Live/Rescue boot'
        echo '- Universal macOS boot/recovery'
        echo '- Successful deployment on every USB/disc/controller'
        echo
        echo 'RELEASE GATE: CANDIDATE until real hardware/boot matrix passes.'
    } > "$out"
    echo "[SONAR] Release report: $out"
}

# ============================================================================
# SONAR SMART ADVISOR — deterministic reasoning engine
# ============================================================================
# This is NOT a call to an LLM: it is a transparent, auditable rules engine
# that correlates signals SONAR already collects (dependencies, self-test,
# catalog validation coverage, manifest freshness, hashchain integrity, role
# adequacy) into a single prioritized action list. Every recommendation
# states the rule that fired, so the operator can verify the reasoning
# instead of trusting a black box. This mirrors the project's own AI
# philosophy: the LLM layer (Ollama) stays advisory-only, and this
# deterministic layer remains the source of truth — the same discipline is
# applied here, just without a model in the loop at all.
SONAR_ADVISOR_MANIFEST_MAX_AGE_DAYS="${SONAR_ADVISOR_MANIFEST_MAX_AGE_DAYS:-30}"

sonar_advisor_catalog_coverage() {
    # Prints: total, functional-ish (FUNCTIONAL/STRUCTURAL/CATALOG/GUARDED), not-validated
    awk -F '\t' '
        NR==1 { for (i=1;i<=NF;i++) if ($i=="VALIDATION") vcol=i; next }
        vcol {
            total++
            v=$(vcol)
            if (v=="NOT_HARDWARE_TESTED" || v=="NOT_VALIDATED") not_validated++
            else validated++
        }
        END { printf "%d\t%d\t%d\n", total+0, validated+0, not_validated+0 }
    ' <<< "${SONAR_EMBEDDED_CATALOG_TSV}"
}

sonar_advisor_manifest_age_days() {
    [[ -s "${SONAR_MANIFEST}" ]] || { echo "-1"; return; }
    local now mtime
    now="$(date -u +%s)"
    mtime="$(date -u -r "${SONAR_MANIFEST}" +%s 2>/dev/null || echo "$now")"
    echo $(( (now - mtime) / 86400 ))
}

# sonar_smart_advisor: run every check, emit CRITICAL/HIGH/MEDIUM/INFO findings
# with the reasoning behind each, plus a transparent readiness score built
# from explicit weights (printed alongside the score — never a hidden number).
sonar_smart_advisor() {
    sonar_report_init
    local ts out; ts="$(sonar_timestamp)"; out="${SONAR_REPORT_DIR}/runs/SONAR_ADVISOR_${ts}.txt"
    local score=100 findings=0
    {
        echo 'SONAR SMART ADVISOR — RAPPORT DE RAISONNEMENT'
        echo '=============================================='
        echo "Date: $(sonar_iso_now)"
        echo "Role actuel: ${SONAR_ROLE}"
        echo 'Moteur: regles deterministes locales (aucun appel LLM implique).'
        echo
        echo '--- Dependances systeme ---'
        local dep_tmp dep_missing
        dep_tmp="$(mktemp)"
        sonar_dependency_report "${dep_tmp}" >/dev/null
        dep_missing="$(awk -F '\t' '$2=="ABSENT" {print $1}' "${dep_tmp}" | tr '\n' ' ')"
        rm -f "${dep_tmp}"
        if [[ -n "${dep_missing// }" ]]; then
            echo "[CRITICAL] Outil(s) requis manquant(s): ${dep_missing}"
            echo "  Raison: preflight_final exigera ces commandes avant tout --disk reel."
            score=$((score-30)); findings=$((findings+1))
        else
            echo "[OK] Toutes les dependances connues sont presentes."
        fi
        echo
        echo '--- Integrite du hashchain audit ---'
        if [[ -s "${SONAR_HASHCHAIN_LOG}" ]]; then
            local chain_tmp; chain_tmp="$(mktemp)"
            if sonar_verify_hashchain >"${chain_tmp}" 2>&1; then
                echo "[OK] Hashchain verifie: $(tail -n1 "${chain_tmp}")"
            else
                echo "[CRITICAL] $(tail -n1 "${chain_tmp}")"
                echo "  Raison: une rupture de chaine indique une modification a posteriori du journal d'audit."
                score=$((score-40)); findings=$((findings+1))
            fi
            rm -f "${chain_tmp}"
        else
            echo "[INFO] Aucun historique d'audit encore present (premier run)."
        fi
        echo
        echo '--- Fraicheur du manifeste SHA-256 ---'
        local age; age="$(sonar_advisor_manifest_age_days)"
        if [[ "$age" == "-1" ]]; then
            echo "[MEDIUM] Aucun manifeste construit (${SONAR_MANIFEST})."
            echo "  Raison: sans manifeste, --verify-manifest ne peut rien confirmer apres coup."
            score=$((score-10)); findings=$((findings+1))
        elif (( age > SONAR_ADVISOR_MANIFEST_MAX_AGE_DAYS )); then
            echo "[MEDIUM] Manifeste vieux de ${age} jours (seuil: ${SONAR_ADVISOR_MANIFEST_MAX_AGE_DAYS})."
            echo "  Raison: le contenu source a pu changer depuis; regenerez avec --build-manifest."
            score=$((score-10)); findings=$((findings+1))
        else
            echo "[OK] Manifeste a jour (${age} jour(s))."
        fi
        echo
        echo '--- Couverture de validation du catalogue ---'
        local total validated not_validated pct
        IFS=$'\t' read -r total validated not_validated < <(sonar_advisor_catalog_coverage)
        pct=0; (( total > 0 )) && pct=$(( validated * 100 / total ))
        echo "Entrees catalogue: ${total} | validees/structurelles: ${validated} (${pct}%) | non testees materiel: ${not_validated}"
        if (( pct < 50 )); then
            echo "[HIGH] Moins de 50% du catalogue est valide/structurel."
            echo "  Raison: une majorite d'outils restent NOT_HARDWARE_TESTED / NOT_VALIDATED."
            score=$((score-20)); findings=$((findings+1))
        else
            echo "[OK] Couverture de validation raisonnable."
        fi
        echo
        echo '--- Scelle du catalogue embarque ---'
        if [[ -s "${SONAR_CATALOG_SEAL_FILE:-${SONAR_SECURITY_DIR}/Vault/catalog.sha256}" ]]; then
            local seal_tmp; seal_tmp="$(mktemp)"
            if sonar_catalog_verify_seal >"${seal_tmp}" 2>&1; then
                echo "[OK] $(tail -n1 "${seal_tmp}")"
            else
                echo "[CRITICAL] Le catalogue ne correspond plus a son scelle — voir --catalog-verify-seal."
                score=$((score-30)); findings=$((findings+1))
            fi
            rm -f "${seal_tmp}"
        else
            echo "[INFO] Catalogue non scelle. Executez --catalog-seal apres validation manuelle du contenu."
        fi
        echo
        echo '--- Adequation du role courant ---'
        if sonar_role_can DESTRUCTIVE; then
            echo "[INFO] Le role '${SONAR_ROLE}' peut engager des actions DESTRUCTIVE (avec CONFIRM)."
        else
            echo "[OK] Le role '${SONAR_ROLE}' ne peut pas engager d'action destructrice — moindre privilege respecte."
        fi
        echo
        echo '--- Verrou de role (SONAR_ROLE) ---'
        if sonar_role_secret_exists; then
            echo "[OK] Verrou de role actif: les roles eleves (Senior/Forensic/Admin/Expert) exigent un jeton valide."
        else
            echo "[HIGH] Aucun secret de verrouillage de role initialise (${SONAR_ROLE_SECRET_FILE})."
            echo "  Raison: n'importe qui peut s'auto-attribuer Admin/Senior/Forensic/Expert via SONAR_ROLE ou --role."
            echo "  Correction: --role-bootstrap puis --role-issue-token <ROLE> pour distribuer des jetons."
            score=$((score-20)); findings=$((findings+1))
        fi
        echo
        (( score < 0 )) && score=0
        echo '--- Score de preparation (ponderation explicite ci-dessus) ---'
        echo "SCORE: ${score}/100 — ${findings} point(s) d'attention."
        if (( score >= 90 )); then echo 'VERDICT: Pret pour un deploiement --dry-run puis materiel supervise.'
        elif (( score >= 60 )); then echo 'VERDICT: Utilisable, mais traitez les points CRITICAL/HIGH ci-dessus d''abord.'
        else echo 'VERDICT: Ne pas deployer sur disque reel avant correction des points CRITICAL.'
        fi
    } | tee "${out}"
    sonar_audit "SMART_ADVISOR_RUN" "report=${out};score_findings=${findings}"
    echo
    echo "[SONAR] Rapport advisor: ${out}"
}

# sonar_mission_report: single combined deliverable for a technician handing
# off a job — advisor verdict + dependencies in one dated Markdown file,
# instead of several TSVs the reader has to cross-reference.
sonar_mission_report() {
    sonar_report_init
    local ts out; ts="$(sonar_timestamp)"; out="${SONAR_REPORT_DIR}/release/SONAR_MISSION_REPORT_${ts}.md"
    local dep_tmp; dep_tmp="$(mktemp)"
    sonar_dependency_report "${dep_tmp}" >/dev/null
    {
        echo "# SONAR — Rapport de mission (${ts})"
        echo
        echo "- Version script: ${SONAR_VERSION}"
        echo "- Role: ${SONAR_ROLE}"
        echo "- OS: $(sonar_detect_os) / ARCH: $(sonar_detect_arch)"
        echo
        echo '## Advisor'
        echo '```'
        sonar_smart_advisor 2>&1
        echo '```'
        echo
        echo '## Dependances'
        echo '```'
        cat "${dep_tmp}"
        echo '```'
    } > "$out"
    rm -f "${dep_tmp}"
    sonar_audit "MISSION_REPORT" "report=${out}"
    echo "[SONAR] Rapport de mission: ${out}"
}

sonar_launcher_v2() {
    while true; do
        cat <<'MENU'

================ SONAR OPERATIONAL LAUNCHER ================
1) Diagnostic complet
2) Self-Test
3) Recovery plan
4) Backup / Clone safety plan
5) Forensic workspace
6) Network diagnostic
7) Builder
8) Release report
9) Security status
10) Recovery execution (non-destructive)
11) Backup execution (file/directory)
12) Forensic acquisition (file/directory)
13) Module status
14) Smart Advisor (analyse + score)
15) Rapport de mission complet
16) Vérifier le hashchain d'audit
17) Sceller / vérifier le catalogue embarqué
18) Verrou de rôle (bootstrap / émettre un jeton)
19) Chaîne de possession forensique
0) Quitter
============================================================
MENU
        read -r -p 'SONAR> ' choice || return 0
        case "$choice" in
            1) sonar_diagnostic_report ;;
            2) sonar_self_test_v2 || true ;;
            3) sonar_recovery_plan ;;
            4) sonar_backup_plan ;;
            5) sonar_forensic_workspace ;;
            6) sonar_network_diagnostic ;;
            7) sonar_builder_v2 ;;
            8) sonar_release_report ;;
            9) sonar_security_status ;;
            10) read -r -p 'Mode [collect/verify] : ' mode; sonar_recovery_execute "${mode:-collect}" ;;
            11) read -r -p 'Source : ' src; read -r -p 'Destination : ' dst; sonar_backup_execute "$src" "$dst" copy ;;
            12) read -r -p 'Evidence source : ' src; read -r -p 'Destination : ' dst; sonar_forensic_acquire "$src" "$dst" ;;
            13) sonar_module_status_v23 ;;
            14) sonar_smart_advisor || true ;;
            15) sonar_mission_report || true ;;
            16) sonar_verify_hashchain || true ;;
            17)
                read -r -p 'Action [seal/verify] : ' sv
                case "$sv" in
                    seal) sonar_catalog_seal ;;
                    verify) sonar_catalog_verify_seal ;;
                    *) echo 'Choix invalide.' ;;
                esac
                ;;
            18)
                read -r -p 'Action [bootstrap/issue/revoke] : ' rl
                case "$rl" in
                    bootstrap) sonar_role_bootstrap_secret ;;
                    issue)
                        read -r -p 'Rôle (Senior/Forensic/Admin/Expert) : ' rr
                        read -r -p 'Identité (ex: j.dupont) : ' ri
                        read -r -p 'Validité en jours [30] : ' rj
                        sonar_role_issue_token "$rr" "$ri" "${rj:-30}"
                        ;;
                    revoke) read -r -p 'Coller le jeton complet à révoquer : ' rt; sonar_role_revoke_token "$rt" ;;
                    *) echo 'Choix invalide.' ;;
                esac
                ;;
            19)
                read -r -p 'Dossier de preuves (sortie de --forensic-acquire) : ' cocroot
                read -r -p "N° de dossier [NON_SPECIFIE] : " cocid
                sonar_forensic_chain_of_custody "$cocroot" "${cocid:-NON_SPECIFIE}"
                ;;
            0) return 0 ;;
            *) echo 'Choix invalide.' ;;
        esac
    done
}


# ============================================================================
# SONAR V2.3 — PHASE 3 GUARDED EXECUTION LAYER
# No physical disk deployment is performed by these modules.
# ============================================================================
sonar_require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "[SONAR][ERROR] Required command not found: $1" >&2; return 127; }; }
sonar_confirm_phrase() { local expected="$1" prompt="${2:-Type ${1} to continue: }" answer; read -r -p "$prompt" answer || return 1; [[ "$answer" == "$expected" ]]; }
sonar_recovery_execute() {
  sonar_require_role DIAGNOSE || return 1
  sonar_report_init; local mode="${1:-collect}" ts out; ts="$(sonar_timestamp)"; out="${SONAR_REPORT_DIR}/recovery/SONAR_RECOVERY_EXEC_${ts}.txt"
  { echo 'SONAR RECOVERY EXECUTION'; echo '========================'; echo "Mode: ${mode}"; echo "Date: $(sonar_iso_now)"; echo "OS: $(sonar_detect_os)"; echo
    case "$mode" in
      collect) echo '[SAFE COLLECTION]'; echo 'Filesystem mounts:'; if command -v findmnt >/dev/null 2>&1; then findmnt -rn || true; elif command -v mount >/dev/null 2>&1; then mount || true; fi; echo; echo 'Block devices:'; command -v lsblk >/dev/null 2>&1 && lsblk -f || true; echo; echo 'Boot environment:'; [[ -d /sys/firmware/efi ]] && echo 'UEFI=detected' || echo 'UEFI=not-detected';;
      verify) echo '[NON-DESTRUCTIVE VERIFICATION]'; command -v dmesg >/dev/null 2>&1 && dmesg --level=err,warn 2>/dev/null | tail -n 200 || true; command -v journalctl >/dev/null 2>&1 && journalctl -p warning -n 100 --no-pager 2>/dev/null || true;;
      *) echo 'ERROR: supported modes are collect and verify'; return 2;;
    esac
    echo; echo 'No filesystem repair, boot rewrite, partitioning, or disk erase was performed.'
  } > "$out"; sonar_audit 'RECOVERY_EXECUTE' "mode=${mode};report=${out}"; echo "[SONAR] Recovery execution report: $out"
}
sonar_backup_execute() {
  sonar_report_init; local source="${1:-}" destination="${2:-}" mode="${3:-copy}" ts out
  [[ -n "$source" && -n "$destination" ]] || { echo 'Usage: --backup-execute SOURCE DESTINATION [copy]' >&2; return 2; }
  [[ -e "$source" ]] || { echo "[SONAR][ERROR] Source does not exist: $source" >&2; return 2; }; [[ "$source" != "$destination" ]] || { echo '[SONAR][ERROR] Source and destination are identical.' >&2; return 2; }
  sonar_require_cmd cp || return 127
  sonar_require_cmd mkdir || return 127
  ts="$(sonar_timestamp)"; out="${SONAR_REPORT_DIR}/recovery/SONAR_BACKUP_EXEC_${ts}.txt"; echo "[SONAR] Backup source: $source"; echo "[SONAR] Backup destination: $destination"
  case "$mode" in copy) sonar_confirm_phrase "BACKUP-$(basename "$source")" "Type BACKUP-$(basename "$source") to confirm: " || { echo '[SONAR] Cancelled.'; return 1; }; mkdir -p "$destination"; if [[ -d "$source" ]]; then cp -a "$source"/. "$destination"/; else cp -a "$source" "$destination"/; fi;; *) echo "[SONAR][ERROR] Unsupported backup mode: $mode" >&2; return 2;; esac
  { echo 'SONAR BACKUP EXECUTION'; echo '======================'; echo "Date: $(sonar_iso_now)"; echo "Source: $source"; echo "Destination: $destination"; echo "Mode: $mode"; echo 'Status: COMPLETED'; [[ -f "$source" ]] && { echo 'Source SHA-256:'; sonar_hash "$source" || true; }; } > "$out"; sonar_audit 'BACKUP_EXECUTE' "source=${source};destination=${destination};mode=${mode}"; echo "[SONAR] Backup completed: $out"
}
sonar_forensic_acquire() {
  sonar_report_init; local source="${1:-}" destination="${2:-}" ts root hashfile
  [[ -n "$source" && -n "$destination" ]] || { echo 'Usage: --forensic-acquire SOURCE DESTINATION' >&2; return 2; }; [[ -e "$source" ]] || { echo '[SONAR][ERROR] Evidence source does not exist.' >&2; return 2; }; [[ "$source" != "$destination" ]] || { echo '[SONAR][ERROR] Source and destination are identical.' >&2; return 2; }
  sonar_require_cmd cp || return 127
  sonar_require_cmd find || return 127
  sonar_require_cmd sort || return 127
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo '[SONAR][ERROR] Ni sha256sum ni shasum disponible — acquisition impossible sans moteur de hachage.' >&2
    return 127
  fi
  ts="$(sonar_timestamp)"; root="${destination%/}/SONAR_EVIDENCE_${ts}"; mkdir -p "$root/evidence" "$root/hashes" "$root/logs" "$root/reports"
  if [[ -d "$source" ]]; then cp -a "$source"/. "$root/evidence"/; else cp -a "$source" "$root/evidence"/; fi
  hashfile="$root/hashes/SHA256.txt"; if command -v sha256sum >/dev/null 2>&1; then (cd "$root/evidence" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$hashfile"; else (cd "$root/evidence" && find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do shasum -a 256 "$f"; done) > "$hashfile"; fi
  printf 'SONAR FORENSIC ACQUISITION\n==========================\nDate: %s\nSource: %s\nDestination: %s\nHash file: %s\n\nNo block-device imaging was performed.\n' "$(sonar_iso_now)" "$source" "$root" "$hashfile" > "$root/reports/ACQUISITION.txt"; sonar_audit 'FORENSIC_ACQUIRE' "source=${source};destination=${root}"; echo "[SONAR] Forensic acquisition: $root"
}
sonar_clone_guarded() { echo '[SONAR][ERROR] Raw block-device cloning is intentionally disabled in V2.3.'; echo '[SONAR] Use the planning layer until a dedicated physical test matrix is approved.'; return 126; }

# sonar_forensic_chain_of_custody EVIDENCE_ROOT [CASE_ID]: turns a raw
# sonar_forensic_acquire output (evidence copy + SHA-256 hash list) into a
# formal chain-of-custody record. Cross-references the audit log for the
# original FORENSIC_ACQUIRE entry (operator identity, timestamp) and the
# hashchain's integrity status at generation time, so the record's own
# trustworthiness is itself verifiable, not just asserted. Later custody
# transfers (courier, storage, handoff to a third party) happen outside
# SONAR's control — the template leaves blank rows for those, anchored to
# the cryptographic evidence this tool CAN attest to.
sonar_forensic_chain_of_custody() {
    local root="${1:-}" case_id out audit_line identity_field operator ts_acquired file_count meta_hash chain_status
    case_id="$(sonar_sanitize_value "${2:-NON_SPECIFIE}")"
    [[ -n "$root" && -d "$root" ]] || { echo 'Usage: --forensic-chain-of-custody EVIDENCE_ROOT [CASE_ID]' >&2; return 2; }
    hashfile="${root%/}/hashes/SHA256.txt"
    [[ -s "$hashfile" ]] || { echo "[SONAR][ERROR] ${hashfile} introuvable — ${root} n'est pas un dossier d'acquisition SONAR valide." >&2; return 2; }
    mkdir -p "${root%/}/reports"
    out="${root%/}/reports/CHAIN_OF_CUSTODY.txt"

    audit_line="$(grep "FORENSIC_ACQUIRE" "${SONAR_AUDIT_LOG}" 2>/dev/null | grep -F "destination=${root%/}" | tail -n1 || true)"
    if [[ -n "$audit_line" ]]; then
        ts_acquired="$(awk -F '\t' '{print $1}' <<< "$audit_line")"
        operator="$(awk -F '\t' '{print $2}' <<< "$audit_line")"
        identity_field="$(grep -oE 'identity=[^;[:space:]]+' <<< "$audit_line" | head -n1 || true)"
        [[ -n "$identity_field" ]] && operator="${operator} (${identity_field})"
    else
        ts_acquired="INCONNU"
        operator="INCONNU — entrée d'audit d'acquisition introuvable pour ce chemin"
    fi

    file_count="$(wc -l < "$hashfile" | tr -d ' ')"
    meta_hash="$(sha256sum "$hashfile" 2>/dev/null | awk '{print $1}')"
    [[ -z "$meta_hash" ]] && meta_hash="$(shasum -a 256 "$hashfile" 2>/dev/null | awk '{print $1}')"

    if sonar_verify_hashchain >/dev/null 2>&1; then chain_status="INTACT"; else chain_status="COMPROMIS — voir --verify-hashchain"; fi

    {
        echo "SONAR — CHAINE DE POSSESSION (CHAIN OF CUSTODY)"
        echo "================================================"
        echo "Dossier n: ${case_id}"
        echo "Genere le: $(sonar_iso_now)"
        echo
        echo "--- Acquisition ---"
        echo "Horodatage de l'acquisition: ${ts_acquired}"
        echo "Operateur: ${operator}"
        echo "Dossier de preuves: ${root}"
        echo "Fichiers acquis (comptes dans la liste de hachage): ${file_count}"
        echo
        echo "--- Integrite cryptographique ---"
        echo "Liste de hachage: ${hashfile}"
        echo "Empreinte SHA-256 de la liste de hachage elle-meme (meta-integrite): ${meta_hash}"
        echo "Statut du hashchain d'audit au moment de la generation: ${chain_status}"
        echo
        echo "AVERTISSEMENT: SONAR atteste de ce qui precede (qui, quand, quels"
        echo "fichiers, avec quelles empreintes) via son propre journal d'audit"
        echo "chaine. Il n'atteste PAS des transferts de possession ulterieurs"
        echo "(transport, stockage, remise a un tiers) -- ceux-ci doivent etre"
        echo "consignes manuellement ci-dessous."
        echo
        echo "--- Transferts de possession (a completer manuellement) ---"
        printf '%-20s %-20s %-20s %-30s %-15s\n' "Date" "De" "A" "Motif" "Signature"
        printf '%s\n' "--------------------------------------------------------------------------------------------------"
        for _ in 1 2 3 4 5; do
            printf '%-20s %-20s %-20s %-30s %-15s\n' "" "" "" "" ""
        done
    } > "$out"

    sonar_audit "CHAIN_OF_CUSTODY_GENERATED" "case_id=${case_id};evidence_root=${root};hashchain_status=${chain_status}"
    echo "[SONAR] Chaine de possession: ${out}"
}

# ----------------------------------------------------------------------------
# BUILD WATERMARKING — traceability, not prevention.
# ----------------------------------------------------------------------------
# Nothing software-only can stop a bit-for-bit `dd` clone of a finished USB
# stick — that requires a secure element on the medium itself, which
# consumer USB drives essentially never have. What IS achievable: every real
# --disk deployment embeds a unique, HMAC-signed watermark on the medium
# (build id, timestamp, operator identity, disk label). If a copy ever
# surfaces where it shouldn't, the watermark proves which specific,
# authorized build it came from — deterrence and forensic attribution, not
# a lock. The watermark's own signing secret is DELIBERATELY separate from
# the role-lock secret (SONAR_ROLE_SECRET_FILE): they protect different
# things (who can act vs. which build this medium came from), and mixing
# them would let anyone able to verify a watermark also derive role tokens.
SONAR_BUILD_SECRET_FILE="${SONAR_BUILD_SECRET_FILE:-${SONAR_SECURITY_DIR}/Keys/build_secret.key}"
SONAR_BUILD_REGISTRY_FILE="${SONAR_BUILD_REGISTRY_FILE:-${SONAR_SECURITY_DIR}/Keys/build_registry.tsv}"

sonar_build_secret_exists() { [[ -s "${SONAR_BUILD_SECRET_FILE}" ]]; }

# Not privilege-granting (unlike the role-lock secret), so it's created
# transparently on first real use rather than requiring an explicit
# bootstrap step — the worst case of a missing secret is "no watermark
# gets signed on this build", not a security regression of anything else.
sonar_ensure_build_secret() {
    sonar_build_secret_exists && return 0
    mkdir -p "$(dirname "${SONAR_BUILD_SECRET_FILE}")"
    chmod 700 "$(dirname "${SONAR_BUILD_SECRET_FILE}")" 2>/dev/null || true
    local secret
    secret="$(sonar_generate_secret_hex)" || return 1
    [[ -n "$secret" ]] || return 1
    printf '%s' "$secret" > "${SONAR_BUILD_SECRET_FILE}"
    chmod 600 "${SONAR_BUILD_SECRET_FILE}"
    sonar_audit "BUILD_SECRET_CREATED" "file=${SONAR_BUILD_SECRET_FILE}"
    # Avertissement explicite plutot qu'un role eleve exige (option (a)
    # ecartee: sonar_generate_build_watermark() appelle cette fonction a
    # CHAQUE --disk normal, pas seulement --fetch-manifest-seal — exiger
    # VAULT ici casserait le premier build sur une machine fraiche pour
    # tout Technician self-service, personne n'ayant de role eleve avant
    # le tout premier build). La racine de confiance HMAC est donc
    # detenue par le premier utilisateur de cette machine : le signaler
    # clairement au lieu de laisser croire a une ceremonie de creation
    # plus formelle qu'elle ne l'est. Trouve par un audit externe, option
    # tranchee avec l'auteur (2026-09-17) plutot que decidee seule.
    echo "[SONAR][ATTENTION] Secret de build cree automatiquement (premiere utilisation) : ${SONAR_BUILD_SECRET_FILE}" >&2
    echo "[SONAR][ATTENTION] Sur une machine partagee entre plusieurs personnes, ce secret devrait etre administre explicitement (genere par une seule personne de confiance, distribue hors-bande) plutot que laisse a la premiere invocation venue." >&2
}

# sonar_build_sign BUILD_ID TS OPERATOR LABEL -> HMAC-SHA256
sonar_build_sign() {
    local build_id="$1" ts="$2" operator="$3" label="$4"
    sonar_build_secret_exists || return 1
    sonar_hmac_sha256_file "${SONAR_BUILD_SECRET_FILE}" "${build_id}|${ts}|${operator}|${label}"
}

# sonar_generate_build_watermark MOUNT_POINT: writes a signed watermark file
# onto the deployed medium (MANIFEST/BUILD_WATERMARK.txt — not secret, just
# an attestation) and records the same build id in a LOCAL registry that
# never leaves the admin's own machine (never copied to the target disk),
# so a later lookup can attach real-world context (job/client name) to a
# build id recovered from a watermark.
sonar_generate_build_watermark() {
    local mp="$1" build_id ts operator label sig
    sonar_ensure_build_secret || { log "[WATERMARK] Secret indisponible — build non filigrané."; return 0; }
    build_id="$(head -c 16 /dev/urandom | sha256sum 2>/dev/null | awk '{print $1}')"
    [[ -z "$build_id" ]] && build_id="$(head -c 16 /dev/urandom | shasum -a 256 | awk '{print $1}')"
    ts="$(sonar_iso_now)"
    # Sanitize before signing (not after) so the HMAC covers exactly the
    # values written below — DISK_LABEL/VOL are env/volume-label controlled
    # and, unsanitized, a newline here forges an extra SONAR_BUILD_*= line in
    # BUILD_WATERMARK.txt that sonar_verify_build_watermark's line-based awk
    # parser would then mis-read.
    operator="$(sonar_sanitize_value "${SONAR_ROLE_IDENTITY:-${SONAR_ROLE}}")"
    label="$(sonar_sanitize_value "${VOL:-${DISK_LABEL:-INCONNU}}")"
    sig="$(sonar_build_sign "$build_id" "$ts" "$operator" "$label")" || { log "[WATERMARK] Échec de signature — build non filigrané."; return 0; }

    mkdir -p "${mp}/MANIFEST"
    {
        echo "SONAR_BUILD_ID=${build_id}"
        echo "SONAR_BUILD_TIMESTAMP=${ts}"
        echo "SONAR_BUILD_OPERATOR=${operator}"
        echo "SONAR_BUILD_LABEL=${label}"
        echo "SONAR_BUILD_SIGNATURE=${sig}"
    } > "${mp}/MANIFEST/BUILD_WATERMARK.txt"

    mkdir -p "$(dirname "${SONAR_BUILD_REGISTRY_FILE}")"
    printf '%s\t%s\t%s\t%s\n' "$ts" "$build_id" "$operator" "$label" >> "${SONAR_BUILD_REGISTRY_FILE}"
    chmod 600 "${SONAR_BUILD_REGISTRY_FILE}" 2>/dev/null || true

    sonar_audit "BUILD_WATERMARKED" "build_id=${build_id};label=${label}"
    log_ok "Build filigrané: ${build_id} (registre local: ${SONAR_BUILD_REGISTRY_FILE})"
}

# sonar_verify_build_watermark PATH: PATH may be the watermark file itself
# or a directory containing MANIFEST/BUILD_WATERMARK.txt (e.g. a mounted
# suspect USB, or an extracted copy). Recomputes the signature from the
# LOCAL build secret — this only succeeds on the machine that holds that
# secret, i.e. typically the one that originally built (or could have
# built) the medium. Cross-references the local registry if the build id
# is found there.
sonar_verify_build_watermark() {
    local path="${1:-}" wm identity build_id ts operator label sig expected
    [[ -n "$path" ]] || { echo 'Usage: --verify-watermark <fichier_ou_dossier>' >&2; return 2; }
    if [[ -d "$path" ]]; then wm="${path%/}/MANIFEST/BUILD_WATERMARK.txt"; else wm="$path"; fi
    [[ -s "$wm" ]] || { echo "[SONAR] Filigrane introuvable: ${wm}" >&2; return 2; }

    build_id="$(awk -F= '/^SONAR_BUILD_ID=/{print $2}' "$wm")"
    ts="$(awk -F= '/^SONAR_BUILD_TIMESTAMP=/{print $2}' "$wm")"
    operator="$(awk -F= '/^SONAR_BUILD_OPERATOR=/{print $2}' "$wm")"
    label="$(awk -F= '/^SONAR_BUILD_LABEL=/{print $2}' "$wm")"
    sig="$(awk -F= '/^SONAR_BUILD_SIGNATURE=/{print $2}' "$wm")"
    if [[ -z "$build_id" || -z "$sig" ]]; then
        echo "[SONAR] Filigrane illisible ou incomplet: ${wm}" >&2
        return 2
    fi

    echo "Build ID   : ${build_id}"
    echo "Horodatage : ${ts}"
    echo "Opérateur  : ${operator}"
    echo "Label disque: ${label}"

    if ! sonar_build_secret_exists; then
        echo "[SONAR] Aucun secret local de watermark — authenticité NON vérifiable sur cette machine." >&2
        return 1
    fi
    expected="$(sonar_build_sign "$build_id" "$ts" "$operator" "$label")" || { echo "[SONAR] Échec du calcul de signature." >&2; return 1; }
    if sonar_const_time_eq "$sig" "$expected"; then
        echo "Authenticité: CONFIRMÉE (signature valide contre le secret local)"
    else
        echo "Authenticité: ÉCHEC — signature invalide (build non reconnu, ou filigrane altéré)" >&2
        sonar_audit "BUILD_WATERMARK_VERIFY_FAILED" "build_id=${build_id}"
        return 1
    fi

    if [[ -s "${SONAR_BUILD_REGISTRY_FILE}" ]] && grep -qF "$build_id" "${SONAR_BUILD_REGISTRY_FILE}"; then
        echo "Registre local: trouvé — $(grep -F "$build_id" "${SONAR_BUILD_REGISTRY_FILE}" | head -n1)"
    else
        echo "Registre local: build id non trouvé (normal si vérifié sur une autre machine que celle du build)."
    fi
    sonar_audit "BUILD_WATERMARK_VERIFIED" "build_id=${build_id}"
}
sonar_module_status_v23() { cat <<'EOF'
SONAR V2.4 RELEASE CANDIDATE MODULE STATUS
==================================
Core                    READY / audited
Launcher                READY
Diagnostic              READY
Recovery                EXECUTABLE: collect, verify
Backup                  EXECUTABLE: guarded file/directory copy
Clone                   GUARDED: raw block clone disabled
Forensic                EXECUTABLE: file/directory acquisition + SHA-256,
                          chain-of-custody generation (cross-references audit
                          identity + hashchain status)
Network                 READY / diagnostic only
Builder                 READY / build candidate
AI                      ADVISORY ONLY
Self-Test               READY
Smart Advisor            READY: deterministic rules engine, no LLM in the loop
Hashchain verification    READY: recomputes and checks the full audit chain
Catalog seal              READY: SHA-256 seal + tamper check (RBAC: VAULT)
Role lock                 READY: per-identity tokens (identity:role:expiry:sig),
                          expiry-checked, individually revocable, best-effort
                          constant-time signature compare (--role-bootstrap)
Post-deploy verification READY: re-hashes files on the mounted device after
                          write, before --disk deployment is reported complete
Physical disk deployment EXECUTABLE: --disk writes Ventoy + payload to the
                          target device (see AVERTISSEMENT / --yes gate)
Raw block cloning        NOT TOUCHED: disabled pending hardware validation
Boot validation          NOT TESTED
EOF
}

# >>> SONAR EMBEDDED TOOL CATALOG V2 BEGIN
SONAR_EMBEDDED_CATALOG_TSV=$(cat <<'SONAR_CATALOG_EOF'
DOMAIN	SUBDOMAIN	TOOL_OR_COMPONENT	OS	ARCHITECTURE	LICENSE	FUNCTION	OFFLINE	PORTABLE	BOOTABLE	WINPE	LIVE_LINUX	MACOS_RECOVERY	UEFI	SECURE_BOOT	DEPENDENCIES	PRIORITY_SONAR	VALIDATION
Core	Runtime	SONAR Core	Windows/Linux/macOS	x86_64/arm64	Project-defined	Orchestration, safety, logging	YES	YES	NO	YES	YES	YES	YES	YES	Bash/runtime	CRITICAL	STRUCTURAL
Core	Launcher	SONAR Launcher	Windows/Linux/macOS	x86_64/arm64	Project-defined	Unified module launcher	YES	YES	NO	YES	YES	YES	YES	YES	SONAR Core	CRITICAL	STRUCTURAL
Core	Self-Test	SONAR Self-Test	Windows/Linux/macOS	x86_64/arm64	Project-defined	Syntax, dependency, integrity and module checks	YES	YES	NO	YES	YES	YES	YES	YES	Bash	CRITICAL	FUNCTIONAL
Build	Media	Ventoy	Windows/Linux	x86_64/arm64	GPLv3	USB/multiboot media preparation	YES	YES	YES	YES	YES	NO	YES	CONDITIONAL	Ventoy release package	CRITICAL	NOT_HARDWARE_TESTED
Build	Persistence	Persistence layer	Linux	x86_64/arm64	Mixed	Persistent Live environment storage	YES	YES	YES	NO	YES	NO	YES	CONDITIONAL	Filesystem/image tools	HIGH	STRUCTURAL
Build	Manifest	SHA-256 manifest	Windows/Linux/macOS	x86_64/arm64	Standard tool	Integrity verification	YES	YES	NO	YES	YES	YES	YES	YES	sha256sum/shasum	CRITICAL	FUNCTIONAL
Diagnostic	Hardware	Hardware inventory	Windows/Linux/macOS	x86_64/arm64	OS-dependent	CPU/RAM/GPU/storage/device inventory	YES	YES	NO	YES	YES	YES	YES	YES	OS utilities	CRITICAL	FUNCTIONAL
Diagnostic	Storage	SMART / storage diagnostics	Windows/Linux	x86_64/arm64	Mixed	Storage health and diagnostics	YES	YES	NO	YES	YES	NO	YES	CONDITIONAL	OS/storage utilities	CRITICAL	NOT_HARDWARE_TESTED
Recovery	Windows	WinPE/WinRE resources	Windows	x86_64/arm64	Microsoft terms apply	Windows recovery and deployment	YES	YES	YES	YES	NO	NO	YES	CONDITIONAL	Windows ADK/WinRE resources	CRITICAL	NOT_VALIDATED
Recovery	Linux	Live/Rescue environment	Linux	x86_64/arm64	Distribution-dependent	Linux rescue and recovery	YES	YES	YES	NO	YES	NO	YES	CONDITIONAL	Linux ISO/tools	CRITICAL	NOT_VALIDATED
Recovery	macOS	macOS Recovery resources	macOS	Intel/Apple Silicon	Apple terms apply	macOS recovery workflows	YES	LIMITED	YES	NO	NO	YES	YES	CONDITIONAL	Apple recovery mechanisms	CRITICAL	NOT_VALIDATED
Backup	Files	Guarded file backup	Windows/Linux/macOS	x86_64/arm64	OS/project dependent	File/directory backup	YES	YES	NO	YES	YES	YES	YES	YES	cp or platform equivalent	CRITICAL	FUNCTIONAL
Backup	Clone	Raw block clone guard	Windows/Linux/macOS	x86_64/arm64	Project-defined	Safety gate for raw cloning	YES	YES	NO	YES	YES	YES	YES	YES	CORE safety checks	CRITICAL	GUARDED
Forensic	Acquisition	Forensic acquisition workspace	Windows/Linux/macOS	x86_64/arm64	Mixed	Evidence acquisition and hashing	YES	YES	NO	YES	YES	YES	YES	YES	cp + SHA-256	CRITICAL	FUNCTIONAL-LIMITED
Network	Diagnostics	Network diagnostics	Windows/Linux/macOS	x86_64/arm64	OS-dependent	Interfaces, routes, DNS, connectivity	YES	YES	NO	YES	YES	YES	YES	YES	OS network tools	HIGH	FUNCTIONAL
AI	Assistant	Ollama integration	Windows/Linux/macOS	x86_64/arm64	Ollama license applies	Local advisory AI	YES	YES	NO	OPTIONAL	OPTIONAL	OPTIONAL	NO	NO	Ollama optional	HIGH	FUNCTIONAL-LIMITED
AI	Downloader	AI-assisted downloader	Windows/Linux/macOS	x86_64/arm64	Project-defined	Discovery with deterministic verification	OPTIONAL	YES	NO	OPTIONAL	OPTIONAL	OPTIONAL	NO	NO	Ollama/network optional	HIGH	STRUCTURAL
Builder	Profiles	SONAR Builder	Windows/Linux/macOS	x86_64/arm64	Project-defined	Build profiles and dependency resolution	YES	YES	YES	YES	YES	YES	YES	YES	Catalog + Core	CRITICAL	FUNCTIONAL-LIMITED
Builder	Profiles	MINIMAL	Windows/Linux/macOS	x86_64/arm64	Mixed	Minimal SONAR build profile	YES	YES	YES	YES	YES	YES	YES	YES	Catalog	HIGH	CATALOG
Builder	Profiles	TECHNICIAN	Windows/Linux/macOS	x86_64/arm64	Mixed	Technician build profile	YES	YES	YES	YES	YES	YES	YES	YES	Catalog	HIGH	CATALOG
Builder	Profiles	RECOVERY	Windows/Linux/macOS	x86_64/arm64	Mixed	Recovery-focused build profile	YES	YES	YES	YES	YES	YES	YES	YES	Catalog	CRITICAL	CATALOG
Builder	Profiles	FORENSIC	Windows/Linux/macOS	x86_64/arm64	Mixed	Forensic-focused build profile	YES	YES	YES	YES	YES	YES	YES	YES	Catalog	CRITICAL	CATALOG
Builder	Profiles	ADMIN	Windows/Linux/macOS	x86_64/arm64	Mixed	Administration build profile	YES	YES	YES	YES	YES	YES	YES	YES	Catalog	HIGH	CATALOG
Builder	Profiles	FULL	Windows/Linux/macOS	x86_64/arm64	Mixed	Full build profile	YES	YES	YES	YES	YES	YES	YES	YES	Catalog	CRITICAL	CATALOG
Builder	Profiles	CUSTOM	Windows/Linux/macOS	x86_64/arm64	Mixed	User-selected build profile	YES	YES	YES	YES	YES	YES	YES	YES	Catalog	CRITICAL	CATALOG
Documentation	Release	Release manifest/report	Windows/Linux/macOS	x86_64/arm64	Project-defined	Release traceability	YES	YES	NO	YES	YES	YES	YES	YES	SHA-256	CRITICAL	FUNCTIONAL
Windows	Deployment	DISM	Windows	x86_64/arm64	Microsoft terms apply	Windows image servicing/deployment	YES	NO	YES	YES	NO	NO	YES	CONDITIONAL	Windows ADK/OS	CRITICAL	NOT_HARDWARE_TESTED
Windows	Recovery	BCDBoot	Windows	x86_64/arm64	Microsoft terms apply	Boot environment repair	YES	NO	YES	YES	NO	NO	YES	CONDITIONAL	Windows OS/WinPE	CRITICAL	NOT_VALIDATED
Windows	Diagnostics	PowerShell	Windows	x86_64/arm64	MIT	Automation and diagnostics	YES	YES	NO	YES	NO	NO	YES	YES	Windows	HIGH	STRUCTURAL
Windows	Networking	ipconfig/netsh	Windows	x86_64/arm64	OS component	Network diagnostics/configuration	YES	NO	NO	YES	NO	NO	YES	YES	Windows	HIGH	STRUCTURAL
Linux	Storage	lsblk	Linux	x86_64/arm64	GPL/util-linux	Block-device inventory	YES	YES	NO	NO	YES	NO	YES	YES	util-linux	CRITICAL	FUNCTIONAL
Linux	Storage	smartctl	Linux	x86_64/arm64	GPLv2	SMART diagnostics	YES	YES	NO	NO	YES	NO	YES	CONDITIONAL	smartmontools	HIGH	NOT_HARDWARE_TESTED
Linux	Recovery	fsck	Linux	x86_64/arm64	Filesystem-dependent	Filesystem consistency checks	YES	YES	NO	NO	YES	NO	YES	CONDITIONAL	Filesystem utilities	CRITICAL	NOT_HARDWARE_TESTED
Linux	Networking	ip	Linux	x86_64/arm64	GPLv2	Network interfaces/routes	YES	YES	NO	NO	YES	NO	YES	YES	iproute2	HIGH	FUNCTIONAL
Linux	Networking	ss	Linux	x86_64/arm64	GPLv2	Socket diagnostics	YES	YES	NO	NO	YES	NO	YES	YES	iproute2	HIGH	FUNCTIONAL
macOS	Diagnostics	diskutil	macOS	Intel/Apple Silicon	Apple terms apply	Disk and volume management	YES	NO	NO	NO	NO	YES	YES	CONDITIONAL	macOS	CRITICAL	NOT_HARDWARE_TESTED
macOS	Recovery	diskutil/Recovery tools	macOS	Intel/Apple Silicon	Apple terms apply	Recovery storage workflows	YES	NO	YES	NO	NO	YES	YES	CONDITIONAL	macOS Recovery	CRITICAL	NOT_VALIDATED
macOS	Networking	networksetup	macOS	Intel/Apple Silicon	Apple terms apply	Network configuration/diagnostics	YES	NO	NO	NO	NO	YES	YES	CONDITIONAL	macOS	HIGH	STRUCTURAL
Cross-Platform	Integrity	sha256sum/shasum	Windows/Linux/macOS	x86_64/arm64	Mixed	File integrity hashing	YES	YES	NO	YES	YES	YES	YES	YES	Hash utility	CRITICAL	FUNCTIONAL
Cross-Platform	Archive	tar	Windows/Linux/macOS	x86_64/arm64	Mixed	Archive/extraction	YES	YES	NO	YES	YES	YES	YES	YES	OS archive tools	HIGH	FUNCTIONAL
Cross-Platform	Download	curl	Windows/Linux/macOS	x86_64/arm64	curl license	Verified downloads	OPTIONAL	YES	NO	OPTIONAL	OPTIONAL	OPTIONAL	NO	NO	Network	HIGH	FUNCTIONAL
Cross-Platform	Download	wget	Windows/Linux/macOS	x86_64/arm64	GPLv3	Verified downloads	OPTIONAL	YES	NO	OPTIONAL	OPTIONAL	OPTIONAL	NO	NO	Network	MEDIUM	FUNCTIONAL
Security	Integrity	GPG	Windows/Linux/macOS	x86_64/arm64	GPLv3	Signature verification	YES	YES	NO	YES	YES	YES	YES	YES	GnuPG	CRITICAL	FUNCTIONAL-LIMITED
Security	Hashing	OpenSSL	Windows/Linux/macOS	x86_64/arm64	Apache-style license	Cryptographic utilities	YES	YES	NO	YES	YES	YES	YES	YES	OpenSSL	HIGH	FUNCTIONAL-LIMITED
Builder	Resolver	Dependency resolver	Windows/Linux/macOS	x86_64/arm64	Project-defined	Resolve required components before build	YES	YES	NO	YES	YES	YES	YES	YES	Catalog	CRITICAL	STRUCTURAL
Builder	Verifier	Artifact verifier	Windows/Linux/macOS	x86_64/arm64	Project-defined	Hash/signature verification before packaging	YES	YES	NO	YES	YES	YES	YES	YES	SHA-256/GPG optional	CRITICAL	STRUCTURAL
SONAR_CATALOG_EOF
)
# <<< SONAR EMBEDDED TOOL CATALOG V2 END

sonar_embedded_catalog_install() {
    local root="${SONAR_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    mkdir -p "$root/catalog"
    printf '%s\n' "$SONAR_EMBEDDED_CATALOG_TSV" > "$root/catalog/SONAR_MASTER_TOOL_CATALOG.tsv"
    echo "[SONAR] Embedded catalog installed: $root/catalog/SONAR_MASTER_TOOL_CATALOG.tsv"
}

sonar_embedded_catalog_validate() {
    local tmp rc
    tmp="$(mktemp)"
    printf '%s\n' "$SONAR_EMBEDDED_CATALOG_TSV" > "$tmp"
    # `|| rc=$?` (not a bare statement + separate `rc=$?`) keeps this exempt
    # from the script's global `set -e`: awk legitimately exits 2/3 on a
    # malformed schema, and under errexit a bare failing statement here would
    # trip the ERR trap before rc is captured or the temp file is cleaned up.
    rc=0
    awk -F '\t' 'NR==1 {if ($1!="DOMAIN" || NF<18) exit 2} NR>1 {if (NF<18) exit 3}' "$tmp" || rc=$?
    rm -f "$tmp"
    if [[ $rc -eq 0 ]]; then echo '[SONAR] Embedded catalog schema: PASS'; else echo '[SONAR] Embedded catalog schema: FAIL' >&2; fi
    return "$rc"
}

# sonar_catalog_seal / sonar_catalog_verify_seal: the schema check above only
# proves the TSV has the right shape; it says nothing about content tampering.
# Sealing hashes the exact catalog content into a protected file (RBAC: VAULT)
# so a later run can prove the embedded catalog hasn't been silently edited.
SONAR_CATALOG_SEAL_FILE="${SONAR_CATALOG_SEAL_FILE:-${SONAR_SECURITY_DIR}/Vault/catalog.sha256}"

sonar_catalog_seal() {
    sonar_require_role VAULT || return 1
    mkdir -p "$(dirname "${SONAR_CATALOG_SEAL_FILE}")"
    local hash
    hash="$(sonar_hash_str "${SONAR_EMBEDDED_CATALOG_TSV}")" || { echo "[SONAR] Hachage indisponible." >&2; return 1; }
    printf '%s\t%s\t%s\n' "$(sonar_iso_now)" "${SONAR_ROLE}" "${hash}" > "${SONAR_CATALOG_SEAL_FILE}"
    sonar_audit "CATALOG_SEALED" "hash=${hash}"
    echo "[SONAR] Catalogue scelle: ${SONAR_CATALOG_SEAL_FILE}"
    echo "[SONAR] SHA256: ${hash}"
}

sonar_catalog_verify_seal() {
    [[ -s "${SONAR_CATALOG_SEAL_FILE}" ]] || { echo "[SONAR] Aucun scelle trouve (${SONAR_CATALOG_SEAL_FILE}); executez --catalog-seal d'abord." >&2; return 2; }
    # Pas de sonar_require_role VAULT ici, volontairement (retire 2026-09-17) :
    # verifier un scelle est une operation de lecture qui ne cree aucune
    # confiance nouvelle, contrairement a sonar_catalog_seal ci-dessus qui EN
    # cree une et reste gate. Meme raisonnement que sonar_fetch_manifest_
    # verify_seal (jamais gate). L'exiger ici cassait --smart-advisor pour
    # tout operateur non-elevated dans le cas normal (catalogue scelle,
    # verification en lecture) : le refus de role se confondait avec une
    # vraie alerte de falsification.
    local sealed_hash current_hash sealed_ts
    sealed_ts="$(awk -F '\t' '{print $1}' "${SONAR_CATALOG_SEAL_FILE}")"
    sealed_hash="$(awk -F '\t' '{print $NF}' "${SONAR_CATALOG_SEAL_FILE}")"
    current_hash="$(sonar_hash_str "${SONAR_EMBEDDED_CATALOG_TSV}")" || { echo "[SONAR] Hachage indisponible." >&2; return 1; }
    if [[ "${sealed_hash}" == "${current_hash}" ]]; then
        echo "[SONAR] Catalogue conforme au scelle du ${sealed_ts}. Aucune alteration detectee."
        sonar_audit "CATALOG_SEAL_VERIFIED" "status=MATCH"
        return 0
    else
        echo "[SONAR][ALERTE] Le catalogue a change depuis le scelle du ${sealed_ts}." >&2
        echo "[SONAR] Scelle : ${sealed_hash}" >&2
        echo "[SONAR] Actuel : ${current_hash}" >&2
        sonar_audit "CATALOG_SEAL_VERIFIED" "status=MISMATCH;sealed=${sealed_hash};current=${current_hash}"
        return 1
    fi
}

sonar_builder_profile() {
    local p="${1:-FULL}"
    case "$p" in MINIMAL|TECHNICIAN|RECOVERY|FORENSIC|ADMIN|FULL|CUSTOM) ;; *) echo "[SONAR][ERROR] Unknown profile: $p" >&2; return 2;; esac
    echo "SONAR BUILDER PROFILE: $p"
}

# === SONAR FINAL COMMAND DISPATCH ===
sonar_security_init
sonar_role_enforce_lock || true
case "${1:-}" in
    --launcher) if sonar_launcher_v2; then exit 0; else exit $?; fi ;;
    --module-status) if sonar_module_status_v23; then exit 0; else exit $?; fi ;;
    --recovery-execute) shift; if sonar_recovery_execute "${1:-collect}"; then exit 0; else exit $?; fi ;;
    --backup-execute) shift; if sonar_backup_execute "${1:-}" "${2:-}" "${3:-copy}"; then exit 0; else exit $?; fi ;;
    --forensic-acquire) shift; if sonar_forensic_acquire "${1:-}" "${2:-}"; then exit 0; else exit $?; fi ;;
    --forensic-chain-of-custody) shift; if sonar_forensic_chain_of_custody "${1:-}" "${2:-}"; then exit 0; else exit $?; fi ;;
    --clone-execute) if sonar_clone_guarded; then exit 0; else exit $?; fi ;;
    --diagnostic) if sonar_diagnostic_report; then exit 0; else exit $?; fi ;;
    --self-test) if sonar_self_test_v2; then exit 0; else exit $?; fi ;;
    --recovery-plan) if sonar_recovery_plan; then exit 0; else exit $?; fi ;;
    --backup-plan) if sonar_backup_plan; then exit 0; else exit $?; fi ;;
    --forensic-workspace) if sonar_forensic_workspace; then exit 0; else exit $?; fi ;;
    --network-diagnostic) if sonar_network_diagnostic; then exit 0; else exit $?; fi ;;
    --builder) shift; [[ $# -ge 1 ]] && SONAR_PROFILE="$1"; if sonar_builder_v2; then exit 0; else exit $?; fi ;;
    --release-report) if sonar_release_report; then exit 0; else exit $?; fi ;;
    --dependencies-report) if sonar_dependency_report; then exit 0; else exit $?; fi ;;
    --self-audit)
        if sonar_structural_self_audit; then exit 0; else exit $?; fi
        ;;
    --build-ai-queue)
        if sonar_build_ai_queue_from_catalogue; then exit 0; else exit $?; fi
        ;;
    --ai-audit)
        shift
        if sonar_ai_dry_run_report "$@"; then exit 0; else exit $?; fi
        ;;
    --ollama-audit)
        shift
        if sonar_ollama_catalogue_audit "$@"; then exit 0; else exit $?; fi
        ;;
    --ai-download)
        shift
        if sonar_ai_downloader_main "$@"; then exit 0; else exit $?; fi
        ;;
    --ai-download-dry-run)
        shift
        if sonar_ai_downloader_main --dry-run "$@"; then exit 0; else exit $?; fi
        ;;
    --catalog-download-resolve) if sonar_catalog_resolve_apt; then exit 0; else exit $?; fi ;;
    --catalog-download-dry-run) if sonar_catalog_download_final --dry-run; then exit 0; else exit $?; fi ;;
    --catalog-download) if sonar_catalog_download_final; then exit 0; else exit $?; fi ;;
    --profile)
        shift
        if [[ -z "${1:-}" || "${1:-}" == "list" ]]; then
            if sonar_profile_list_all; then exit 0; else exit $?; fi
        else
            if sonar_profile_doc "${1:-}"; then exit 0; else exit $?; fi
        fi
        ;;
    --fetch-manifest-seal) if sonar_fetch_manifest_seal; then exit 0; else exit $?; fi ;;
    --fetch-manifest-verify-seal) if sonar_fetch_manifest_verify_seal; then exit 0; else exit $?; fi ;;
    --fetch) shift; if sonar_fetch_profile "${1:-}"; then exit 0; else exit $?; fi ;;
    --field-pin-set) shift; if sonar_field_pin_set "${1:-}" "${2:-}" "${3:-ALL}"; then exit 0; else exit $?; fi ;;
    --field-export) shift; if sonar_field_export "${1:-}"; then exit 0; else exit $?; fi ;;
    --diag-analyze) shift; sonar_diag_analyze "$@"; exit $? ;;
    --catalog-install) if sonar_embedded_catalog_install; then exit 0; else exit $?; fi ;;
    --catalog-validate-embedded) if sonar_embedded_catalog_validate; then exit 0; else exit $?; fi ;;
    --catalog-seal) if sonar_catalog_seal; then exit 0; else exit $?; fi ;;
    --catalog-verify-seal) if sonar_catalog_verify_seal; then exit 0; else exit $?; fi ;;
    --builder-profile) shift; if sonar_builder_profile "${1:-FULL}"; then exit 0; else exit $?; fi ;;
    --smart-advisor) if sonar_smart_advisor; then exit 0; else exit $?; fi ;;
    --mission-report) if sonar_mission_report; then exit 0; else exit $?; fi ;;
    --verify-hashchain) if sonar_verify_hashchain; then exit 0; else exit $?; fi ;;
    --role-bootstrap) if sonar_role_bootstrap_secret; then exit 0; else exit $?; fi ;;
    --role-issue-token) shift; if sonar_role_issue_token "${1:-}" "${2:-}" "${3:-30}"; then exit 0; else exit $?; fi ;;
    --role-revoke-token) shift; if sonar_role_revoke_token "${1:-}"; then exit 0; else exit $?; fi ;;
    --verify-watermark) shift; if sonar_verify_build_watermark "${1:-}"; then exit 0; else exit $?; fi ;;

esac

main_final "$@"
