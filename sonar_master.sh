#!/bin/bash
#===============================================================================
# SONAR MASTER — SCRIPT DE DÉPLOIEMENT AUTOMATISÉ - OUTIL DE MAINTENANCE IT PORTABLE
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
# Copyright 2026 [REMPLACER PAR VOTRE NOM OU ORGANISATION]
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
SONAR_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SONAR_ROOT="${SONAR_ROOT:-${SONAR_SCRIPT_DIR}}"

# Stable runtime root: do not depend on the caller's current directory.
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
SONAR_ROLE="${SONAR_ROLE:-Technician}"
SONAR_AI_SECURITY_MODE="${SONAR_AI_SECURITY_MODE:-advisory}"

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
# The signature is a real HMAC-SHA256 (RFC 2104, via `openssl dgst -hmac`),
# not a bespoke keyed hash — openssl is a hard requirement for the role-lock
# specifically (checked at first use, fails closed with a clear message if
# missing, never silently falls back to a weaker construction). Comparison
# still goes through sonar_const_time_eq, a best-effort constant-time
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
    if command -v sha256sum >/dev/null 2>&1; then
        secret="$(head -c 32 /dev/urandom | sha256sum | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        secret="$(head -c 32 /dev/urandom | shasum -a 256 | awk '{print $1}')"
    else
        echo "[SONAR] Aucun moteur SHA-256 disponible pour générer le secret." >&2
        return 1
    fi
    [[ -n "$secret" ]] || { echo "[SONAR] Échec de génération du secret." >&2; return 1; }
    printf '%s' "$secret" > "${SONAR_ROLE_SECRET_FILE}"
    chmod 600 "${SONAR_ROLE_SECRET_FILE}"
    : > "${SONAR_ROLE_REVOKED_FILE}"
    chmod 600 "${SONAR_ROLE_REVOKED_FILE}"
    sonar_audit "ROLE_SECRET_BOOTSTRAPPED" "file=${SONAR_ROLE_SECRET_FILE}"
    echo "[SONAR] Secret de verrouillage de rôle initialisé: ${SONAR_ROLE_SECRET_FILE} (chmod 600)."
    echo "[SONAR] Émettez des jetons avec: --role-issue-token <ROLE> <IDENTITE> [JOURS_VALIDITE=30]."
}

# sonar_require_openssl: hard dependency for the role-lock's HMAC. Fails
# closed with a clear message — never silently downgrades to a weaker
# construction, consistent with the fail-safe posture of the rest of the
# lock (an unclear failure mode here would be worse than a loud one).
sonar_require_openssl() {
    command -v openssl >/dev/null 2>&1 && return 0
    echo "[SONAR] openssl est requis pour signer/vérifier les jetons de rôle (HMAC-SHA256)." >&2
    echo "[SONAR] Installez-le (ex: apt install openssl) puis réessayez." >&2
    return 1
}

# sonar_role_sign IDENTITY ROLE EXPIRY -> HMAC-SHA256(secret, "identity|role|expiry")
sonar_role_sign() {
    local identity="$1" role="$2" expiry="$3" secret
    sonar_require_openssl || return 1
    sonar_role_secret_exists || return 1
    secret="$(cat "${SONAR_ROLE_SECRET_FILE}")" || return 1
    printf '%s' "${identity}|${role}|${expiry}" | openssl dgst -sha256 -hmac "${secret}" -r | awk '{print $1}'
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
    local provided="$1" identity role expiry sig token_id
    IFS=':' read -r identity role expiry sig <<< "${provided}"
    [[ -n "$identity" && -n "$role" && -n "$expiry" ]] || { echo "[SONAR] Jeton illisible (format attendu: identite:role:expiry:signature)." >&2; return 2; }
    mkdir -p "$(dirname "${SONAR_ROLE_REVOKED_FILE}")"
    token_id="$(sonar_role_token_id "$identity" "$role" "$expiry")"
    if sonar_role_is_revoked "$token_id"; then
        echo "[SONAR] Jeton déjà révoqué (identity=${identity}, role=${role})."
        return 0
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$identity" "$role" "$expiry" "$token_id" >> "${SONAR_ROLE_REVOKED_FILE}"
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
    [[ "${SONAR_ROLE_LOCK_ENFORCED:-0}" == "1" ]] && return 0
    SONAR_ROLE_LOCK_ENFORCED=1
    sonar_role_is_self_service "${SONAR_ROLE}" && return 0
    local provided="${SONAR_ROLE_TOKEN}"
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

    if [[ ! -f "${SONAR_POLICY_FILE}" ]]; then
        cat > "${SONAR_POLICY_FILE}" <<'EOF'
ROLE	AUDIT	DIAGNOSE	DEPLOY	DESTRUCTIVE	FORENSIC	VAULT
Viewer	R	R	-	-	-	R
Technician	R	R	R	-	-	RW
Senior	R	R	R	CONFIRM	R	RW
Forensic	R	R	-	-	RW	RW
Admin	RW	RW	R	CONFIRM	RW	RW
Expert	RW	RW	R	CONFIRM	RW	RW
EOF
    fi

    touch "${SONAR_AUDIT_LOG}" "${SONAR_HASHCHAIN_LOG}"
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

sonar_audit() {
    local event="${1:-event}"
    local details="${2:-}"
    local ts prev hash
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    # Fold the authenticated identity into every audit entry, not just the
    # role-lock's own events — so a backup, forensic acquisition, or real
    # --disk deployment run under an elevated token is attributable to the
    # named operator, not just to the role. Single source of truth here:
    # callers must not embed "identity=" themselves (see sonar_role_enforce_lock).
    if [[ -n "${SONAR_ROLE_IDENTITY:-}" ]]; then
        details="${details:+${details};}identity=${SONAR_ROLE_IDENTITY}"
    fi
    printf '%s\t%s\t%s\t%s\n' "$ts" "${SONAR_ROLE}" "$event" "$details" >> "${SONAR_AUDIT_LOG}"

    prev="$(tail -n 1 "${SONAR_HASHCHAIN_LOG}" 2>/dev/null | awk -F '\t' '{print $NF}')"
    prev="${prev:-GENESIS}"
    hash="$(sonar_hash_str "${prev}|${ts}|${SONAR_ROLE}|${event}|${details}")" || hash="UNAVAILABLE"
    printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "${SONAR_ROLE}" "$event" "$details" "$hash" >> "${SONAR_HASHCHAIN_LOG}"
}

# sonar_verify_hashchain: recompute each hashchain entry from GENESIS forward and
# compare against the stored hash. Detects any insertion, deletion, reordering or
# edition of a past audit entry. Without this, the hashchain was write-only —
# tamper-evidence requires a reader that actually recomputes the chain.
sonar_verify_hashchain() {
    [[ -s "${SONAR_HASHCHAIN_LOG}" ]] || { echo "[SONAR] Hashchain vide ou absent: ${SONAR_HASHCHAIN_LOG}" >&2; return 1; }
    local prev="GENESIS" ts role event details stored_hash computed_hash lineno=0 broken=0 total=0
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
    echo "  mode: ${SONAR_AI_SECURITY_MODE}"
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
SONAR — moteur unique

Usage:
  sudo ./deploy_it_toolkit_SONAR_MASTER.sh --disk /dev/sdX [options]

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

IA:
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
  --help|-h                  Afficher cette aide

Commandes indépendantes (à la place de --disk):
  --self-audit               Auto-vérification structurelle du script
  --build-ai-queue           Générer la file IA depuis le catalogue (SONAR_CATALOGUE_EMBEDDED=/chemin pour un fichier externe personnalisé; jamais écrasé s'il existe déjà)
  --ai-audit [--queue F]     Rapport de simulation sur la file IA
  --ollama-audit [--queue F] Audit du catalogue via Ollama (lecture seule)
  --ai-download [--queue F]  Résolution + téléchargement vérifié via Ollama
  --ai-download-dry-run      Comme --ai-download, sans téléchargement réel

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
  --builder [PROFILE]         Construire un support logiciel local
  --release-report            Générer le rapport de release
  --dependencies-report       Générer le rapport des dépendances

Intelligence & intégrité (moteur déterministe, aucun appel LLM):
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
            --no-logging) INCLUDE_LOGGING=false; shift ;;
            --no-readme) GENERATE_README=false; shift ;;
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
            response=$(curl -fsS --max-time 120 http://127.0.0.1:11434/api/generate \
              -H 'Content-Type: application/json' \
              -d "$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"prompt":sys.argv[2],"stream":False}))' "$model" "$prompt")") || { ai_log "Ollama: échec de la requête HTTP."; return 1; }
            [[ -n "${response}" ]] || { ai_log "Ollama: réponse vide."; return 1; }
            ai_parse_llm_response "ollama" <<<"${response}" || { ai_log "Ollama: réponse JSON invalide ou vide."; return 1; }
            ;;
        llama.cpp)
            local model="${AI_MODEL:-local}"
            response=$(curl -fsS --max-time 120 http://127.0.0.1:8080/v1/chat/completions \
              -H 'Content-Type: application/json' \
              -d "$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"messages":[{"role":"system","content":"Tu es Sonar AI. Tu es prudent, factuel et tu ne proposes jamais une action destructive sans validation humaine."},{"role":"user","content":sys.argv[2]}],"temperature":0.1}))' "$model" "$prompt")") || { ai_log "llama.cpp: échec de la requête HTTP."; return 1; }
            [[ -n "${response}" ]] || { ai_log "llama.cpp: réponse vide."; return 1; }
            ai_parse_llm_response "llama.cpp" <<<"${response}" || { ai_log "llama.cpp: réponse JSON invalide ou vide."; return 1; }
            ;;
        openai-compatible)
            [[ -n "${OPENAI_API_KEY:-}" ]] || { ai_log "openai-compatible: OPENAI_API_KEY absente."; return 1; }
            local -a curl_opts=(-fsS --max-time 120)
            [[ -n "${SONAR_CA_CERT:-}" ]] && curl_opts+=(--cacert "${SONAR_CA_CERT}")
            response=$(curl "${curl_opts[@]}" "${AI_ENDPOINT}" \
              -H 'Content-Type: application/json' -H "Authorization: Bearer ${OPENAI_API_KEY}" \
              -d "$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"messages":[{"role":"system","content":"Tu es Sonar AI. Ne donne jamais d ordre destructif automatique. Réponds de façon factuelle."},{"role":"user","content":sys.argv[2]}],"temperature":0.1}))' "${AI_MODEL:-gpt-4.1-mini}" "$prompt")") || { ai_log "openai-compatible: échec de la requête HTTP."; return 1; }
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
    for c in awk basename blockdev findmnt lsblk mount umount sync dd mkfs.ext4 sha256sum tar gzip sed grep find sort date head python3 wget curl; do
        require_cmd_final "$c"
    done
    [[ -d "${SOURCE_DIR}" ]] || error_exit "Source absente: ${SOURCE_DIR}"
    mkdir -p "${SOURCE_DIR}"/{ISO,Portable,Scripts,Drivers,macOS}
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
    if ! cp -a "$1/." "$2/"; then
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
    generate_ventoy_json_final "${mp}"
    [[ "${INCLUDE_VERACRYPT}" == "true" ]] && sonar_generate_vault_helper "${mp}/Scripts"
    sonar_generate_build_watermark "${mp}"
    unmount_final "${mp}"
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
    : > "${mp}/MANIFEST/ISO.sha256"
    while IFS= read -r -d '' f; do sha256sum "$f" >> "${mp}/MANIFEST/ISO.sha256"; done \
        < <(find "${mp}/ISO" -type f -iname '*.iso' -print0 | sort -z)
    : > "${mp}/MANIFEST/FILES.sha256"
    while IFS= read -r -d '' f; do sha256sum "$f" >> "${mp}/MANIFEST/FILES.sha256"; done \
        < <(find "${mp}/Portable" "${mp}/Scripts" "${mp}/Drivers" "${mp}/macOS" -type f -print0 2>/dev/null | sort -z)
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
    local mp checked=0 failed=0 mf n rel_tmp
    mp="$(mount_ventoy_final)"
    for mf in "${mp}/MANIFEST/ISO.sha256" "${mp}/MANIFEST/FILES.sha256"; do
        [[ -s "$mf" ]] || continue
        n="$(wc -l < "$mf" | tr -d ' ')"
        checked=$((checked + n))
        # Manifest lines carry the mount point that was live when the manifest
        # was written; mount_ventoy_final always mounts on a fresh mktemp -d
        # path, so we rewrite to paths relative to the *current* mount point
        # (anchored at the known top-level folders) before re-checking.
        rel_tmp="$(mktemp)"
        sed -E 's#(^[0-9a-fA-F]+  ).*/(ISO/|Portable/|Scripts/|Drivers/|macOS/)#\1\2#' "$mf" > "$rel_tmp"
        if ! ( cd "$mp" && sha256sum -c --quiet "$rel_tmp" ) 2>>"${LOG_FILE:-/dev/null}"; then
            failed=$((failed+1))
            log_err "Vérification post-déploiement échouée: $(basename "$mf")"
        fi
        rm -f "$rel_tmp"
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
            log "SONAR MASTER — moteur unique, catalogue conservé"
            [[ "${DRY_RUN}" == "true" ]] && log "MODE DRY-RUN."
            for ((i=1;i<=BATCH_COUNT;i++)); do
                deploy_single_disk_final "$i"
                if (( i < BATCH_COUNT )); then
                    read -r -p "Insérez le disque suivant puis Entrée..."
                fi
            done
            log "SONAR MASTER — TERMINÉ"
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
    printf '%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$SONAR_AI_LOG"
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
    python3 - "$SONAR_AI_URL" "$SONAR_AI_MODEL" "$1" "$SONAR_TIMEOUT" <<'PY'
import json, sys, urllib.request
url, model, prompt, timeout = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
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

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'
    fi
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
        actual="$(sha256_file "$out")"
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
        echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
        echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
    return "$errors"
}

# ============================================================================
# SONAR OPERATIONAL EXTENSIONS V2
# Non-destructive operational layer: Launcher, Diagnostic, Recovery plans,
# Backup/Clone safety checks, Forensic workspace, Network diagnostics,
# Builder, Self-Test and Release report.
# Destructive disk actions remain exclusively in the existing deploy workflow.
# ============================================================================

SONAR_VERSION="3.10.1-dep-guard"
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
        echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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

sonar_self_test_v2() {
    sonar_report_init
    local ts out errors=0 warnings=0 self="${BASH_SOURCE[0]}"
    ts="$(sonar_timestamp)"; out="${SONAR_REPORT_DIR}/runs/SONAR_SELFTEST_${ts}.txt"
    exec 3>&1
    {
        echo 'SONAR SELF-TEST V2'
        echo '=================='
        echo "Version: ${SONAR_VERSION}"
        echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo
        check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf "PASS\t%s\n" "${label}"; else printf "FAIL\t%s\n" "${label}"; errors=$((errors+1)); fi; }
        check 'bash syntax' bash -n "$self"
        check 'python3' command -v python3
        check 'sha256 engine' bash -c 'command -v sha256sum || command -v shasum'
        if [[ -d "${SOURCE_DIR}" ]]; then echo 'PASS\tsource directory'; else printf 'WARN\tsource directory absent (runtime test environment)\n'; warnings=$((warnings+1)); fi
        [[ -d "${ISO_SOURCE_DIR}" ]] && echo 'PASS\tISO source' || { printf 'WARN\tISO source absent\n'; warnings=$((warnings+1)); }
        [[ -d "${PORTABLE_SOURCE_DIR}" ]] && echo 'PASS\tPortable source' || { printf 'WARN\tPortable source absent\n'; warnings=$((warnings+1)); }
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
        if "$self" --module-status >/dev/null 2>&1; then printf 'PASS\tModule status smoke test\n'; else printf 'FAIL\tModule status smoke test\n'; errors=$((errors+1)); fi
        if "$self" --recovery-execute collect >/dev/null 2>&1; then printf 'PASS\tRecovery collect smoke test\n'; else printf 'FAIL\tRecovery collect smoke test\n'; errors=$((errors+1)); fi
        grep -q '^sonar_smart_advisor() {' "$self" && printf 'PASS\tSmart Advisor module present\n' || { printf 'FAIL\tSmart Advisor module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_verify_hashchain() {' "$self" && printf 'PASS\tHashchain verification present\n' || { printf 'FAIL\tHashchain verification missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_catalog_seal() {' "$self" && printf 'PASS\tCatalog seal module present\n' || { printf 'FAIL\tCatalog seal module missing\n'; errors=$((errors+1)); }
        grep -q '^sonar_post_deploy_verify_final() {' "$self" && printf 'PASS\tPost-deploy verification present\n' || { printf 'FAIL\tPost-deploy verification missing\n'; errors=$((errors+1)); }
        if "$self" --verify-hashchain >/dev/null 2>&1; then printf 'PASS\tHashchain verify smoke test\n'; else printf 'WARN\tHashchain verify smoke test (aucun historique encore)\n'; warnings=$((warnings+1)); fi
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
        SONAR_ROOT="${_rt_root}" "$self" --role-revoke-token "${_rt_token}" >/dev/null 2>&1
        _rt_out="$(SONAR_ROOT="${_rt_root}" SONAR_ROLE=Admin SONAR_ROLE_TOKEN="${_rt_token}" "$self" --security-status 2>/dev/null)"
        if grep -q 'role: Technician' <<< "${_rt_out}"; then
            printf 'PASS\tRevoked token is rejected\n'
        else
            printf 'FAIL\tRevoked token was NOT rejected\n'; errors=$((errors+1))
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
        rm -rf "${_rt_root}"
        grep -q '^sonar_generate_vault_helper() {' "$self" && printf 'PASS\tVault helper generator present\n' || { printf 'FAIL\tVault helper generator missing\n'; errors=$((errors+1)); }
        if command -v gpg >/dev/null 2>&1; then
            local _vh_dir _vh_src _vh_enc _vh_out
            _vh_dir="$(mktemp -d)"
            ( source <(sed -n '/^sonar_generate_vault_helper() {/,/^}/p' "$self"); log_ok() { :; }; sonar_generate_vault_helper "${_vh_dir}" ) >/dev/null 2>&1
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
          source <(sed -n '/^sonar_hash_str() {/,/^}/p' "$self")
          source <(sed -n '/^sonar_require_openssl() {/,/^}/p' "$self")
          source <(sed -n '/^sonar_const_time_eq() {/,/^}/p' "$self")
          source <(sed -n '/^sonar_audit() {/,/^}/p' "$self")
          source <(sed -n '/^sonar_build_secret_exists() {/,/^}/p' "$self")
          source <(sed -n '/^sonar_ensure_build_secret() {/,/^}/p' "$self")
          source <(sed -n '/^sonar_build_sign() {/,/^}/p' "$self")
          source <(sed -n '/^sonar_generate_build_watermark() {/,/^}/p' "$self")
          source <(sed -n '/^sonar_verify_build_watermark() {/,/^}/p' "$self")
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
        rm -rf "${_wm_root}" "${_wm_mp}"
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
Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

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
        echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
BUILT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
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
    cat > "$root/MANIFEST/BUILD_INFO.tsv" <<EOF
FIELD\tVALUE
VERSION\t${SONAR_VERSION}
PROFILE\t${profile}
BUILT\t$(date -u '+%Y-%m-%dT%H:%M:%SZ')
STATUS\tBUILD_CANDIDATE
EOF
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
        echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
        echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
  sonar_report_init; local mode="${1:-collect}" ts out; ts="$(sonar_timestamp)"; out="${SONAR_REPORT_DIR}/recovery/SONAR_RECOVERY_EXEC_${ts}.txt"
  { echo 'SONAR RECOVERY EXECUTION'; echo '========================'; echo "Mode: ${mode}"; echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; echo "OS: $(sonar_detect_os)"; echo
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
  { echo 'SONAR BACKUP EXECUTION'; echo '======================'; echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; echo "Source: $source"; echo "Destination: $destination"; echo "Mode: $mode"; echo 'Status: COMPLETED'; [[ -f "$source" ]] && { echo 'Source SHA-256:'; sonar_hash "$source" || true; }; } > "$out"; sonar_audit 'BACKUP_EXECUTE' "source=${source};destination=${destination};mode=${mode}"; echo "[SONAR] Backup completed: $out"
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
  printf 'SONAR FORENSIC ACQUISITION\n==========================\nDate: %s\nSource: %s\nDestination: %s\nHash file: %s\n\nNo block-device imaging was performed.\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$source" "$root" "$hashfile" > "$root/reports/ACQUISITION.txt"; sonar_audit 'FORENSIC_ACQUIRE' "source=${source};destination=${root}"; echo "[SONAR] Forensic acquisition: $root"
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
    local root="${1:-}" case_id="${2:-NON_SPECIFIE}" hashfile out audit_line identity_field operator ts_acquired file_count meta_hash chain_status
    [[ -n "$root" && -d "$root" ]] || { echo 'Usage: --forensic-chain-of-custody EVIDENCE_ROOT [CASE_ID]' >&2; return 2; }
    hashfile="${root%/}/hashes/SHA256.txt"
    [[ -s "$hashfile" ]] || { echo "[SONAR][ERROR] ${hashfile} introuvable — ${root} n'est pas un dossier d'acquisition SONAR valide." >&2; return 2; }
    mkdir -p "${root%/}/reports"
    out="${root%/}/reports/CHAIN_OF_CUSTODY.txt"

    audit_line="$(grep "FORENSIC_ACQUIRE" "${SONAR_AUDIT_LOG}" 2>/dev/null | grep -F "destination=${root%/}" | tail -n1)"
    if [[ -n "$audit_line" ]]; then
        ts_acquired="$(awk -F '\t' '{print $1}' <<< "$audit_line")"
        operator="$(awk -F '\t' '{print $2}' <<< "$audit_line")"
        identity_field="$(grep -oE 'identity=[^;[:space:]]+' <<< "$audit_line" | head -n1)"
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
        echo "Genere le: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
    if command -v sha256sum >/dev/null 2>&1; then
        secret="$(head -c 32 /dev/urandom | sha256sum | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        secret="$(head -c 32 /dev/urandom | shasum -a 256 | awk '{print $1}')"
    else
        return 1
    fi
    [[ -n "$secret" ]] || return 1
    printf '%s' "$secret" > "${SONAR_BUILD_SECRET_FILE}"
    chmod 600 "${SONAR_BUILD_SECRET_FILE}"
    sonar_audit "BUILD_SECRET_CREATED" "file=${SONAR_BUILD_SECRET_FILE}"
}

# sonar_build_sign BUILD_ID TS OPERATOR LABEL -> HMAC-SHA256
sonar_build_sign() {
    local build_id="$1" ts="$2" operator="$3" label="$4" secret
    sonar_require_openssl || return 1
    sonar_build_secret_exists || return 1
    secret="$(cat "${SONAR_BUILD_SECRET_FILE}")" || return 1
    printf '%s' "${build_id}|${ts}|${operator}|${label}" | openssl dgst -sha256 -hmac "${secret}" -r | awk '{print $1}'
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
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    operator="${SONAR_ROLE_IDENTITY:-${SONAR_ROLE}}"
    label="${VOL:-${DISK_LABEL:-INCONNU}}"
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
    awk -F '\t' 'NR==1 {if ($1!="DOMAIN" || NF<18) exit 2} NR>1 {if (NF<18) exit 3}' "$tmp"
    rc=$?
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
    printf '%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${SONAR_ROLE}" "${hash}" > "${SONAR_CATALOG_SEAL_FILE}"
    sonar_audit "CATALOG_SEALED" "hash=${hash}"
    echo "[SONAR] Catalogue scelle: ${SONAR_CATALOG_SEAL_FILE}"
    echo "[SONAR] SHA256: ${hash}"
}

sonar_catalog_verify_seal() {
    [[ -s "${SONAR_CATALOG_SEAL_FILE}" ]] || { echo "[SONAR] Aucun scelle trouve (${SONAR_CATALOG_SEAL_FILE}); executez --catalog-seal d'abord." >&2; return 2; }
    sonar_require_role VAULT || return 1
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
    --launcher) sonar_launcher_v2; exit $? ;;
    --module-status) sonar_module_status_v23; exit $? ;;
    --recovery-execute) shift; sonar_recovery_execute "${1:-collect}"; exit $? ;;
    --backup-execute) shift; sonar_backup_execute "${1:-}" "${2:-}" "${3:-copy}"; exit $? ;;
    --forensic-acquire) shift; sonar_forensic_acquire "${1:-}" "${2:-}"; exit $? ;;
    --forensic-chain-of-custody) shift; sonar_forensic_chain_of_custody "${1:-}" "${2:-}"; exit $? ;;
    --clone-execute) sonar_clone_guarded; exit $? ;;
    --diagnostic) sonar_diagnostic_report; exit $? ;;
    --self-test) sonar_self_test_v2; exit $? ;;
    --recovery-plan) sonar_recovery_plan; exit $? ;;
    --backup-plan) sonar_backup_plan; exit $? ;;
    --forensic-workspace) sonar_forensic_workspace; exit $? ;;
    --network-diagnostic) sonar_network_diagnostic; exit $? ;;
    --builder) shift; [[ $# -ge 1 ]] && SONAR_PROFILE="$1"; sonar_builder_v2; exit $? ;;
    --release-report) sonar_release_report; exit $? ;;
    --dependencies-report) sonar_dependency_report; exit $? ;;
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
    --catalog-install) sonar_embedded_catalog_install; exit $? ;;
    --catalog-validate-embedded) sonar_embedded_catalog_validate; exit $? ;;
    --catalog-seal) sonar_catalog_seal; exit $? ;;
    --catalog-verify-seal) sonar_catalog_verify_seal; exit $? ;;
    --builder-profile) shift; sonar_builder_profile "${1:-FULL}"; exit $? ;;
    --smart-advisor) sonar_smart_advisor; exit $? ;;
    --mission-report) sonar_mission_report; exit $? ;;
    --verify-hashchain) sonar_verify_hashchain; exit $? ;;
    --role-bootstrap) sonar_role_bootstrap_secret; exit $? ;;
    --role-issue-token) shift; sonar_role_issue_token "${1:-}" "${2:-}" "${3:-30}"; exit $? ;;
    --role-revoke-token) shift; sonar_role_revoke_token "${1:-}"; exit $? ;;
    --verify-watermark) shift; sonar_verify_build_watermark "${1:-}"; exit $? ;;

esac

main_final "$@"
