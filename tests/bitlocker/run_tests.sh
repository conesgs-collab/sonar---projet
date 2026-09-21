#!/bin/bash
# Tests de tools/sonar_bitlocker.sh.
# Sortie : une ligne PASS/FAIL/WARN par verification ; code retour = nombre d'echecs.
#
# Deux niveaux :
#   - toujours : options, garde-fous, absence de fuite de la cle (aucun volume requis) ;
#   - si fournis : un VRAI volume BitLocker, jamais commite (BitLocker ne se cree que sous
#     Windows) :  SONAR_BL_TEST_IMAGE=/chemin/image.raw  SONAR_BL_TEST_OFFSET=65536 \
#                 SONAR_BL_TEST_KEY=269258-...-591404  SONAR_BL_TEST_FILE=secret.txt
#     (root + losetup + cryptsetup >= 2.3 requis). Sans eux : WARN, jamais un faux PASS.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BL="${DIR}/../../tools/sonar_bitlocker.sh"
fails=0
ok()   { printf 'PASS\t%s\n' "$1"; }
ko()   { printf 'FAIL\t%s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

[[ -f "$BL" ]] || { ko "BitLocker : sonar_bitlocker.sh present"; exit "$fails"; }

check "BitLocker : syntaxe bash valide"                              'bash -n "$BL"'
check "BitLocker : --help affiche l'usage"                           'bash "$BL" --help | grep -q "LECTURE SEULE"'
check "BitLocker : une option sans valeur ne boucle pas (regression : shift 2)" 'timeout 10 bash "$BL" --unlock >/dev/null 2>&1; [[ $? -ne 124 ]]'
check "BitLocker : option inconnue -> code 2"                        'bash "$BL" --nimporte-quoi >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "BitLocker : sans action -> usage, code 2"                     'bash "$BL" >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "BitLocker : --unlock sans peripherique -> code 2"             'bash "$BL" --unlock >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "BitLocker : un fichier qui n'est pas un peripherique est refuse (code 2)" 'bash "$BL" --unlock "$BL" --key-stdin --yes </dev/null >/dev/null 2>&1; [[ $? -eq 2 ]]'
check "BitLocker : aucune option d'ecriture n'existe (lecture seule imposee)" '! grep -Eq -- "--(rw|write|read-write)" "$BL" && grep -q "bitlkOpen --readonly" "$BL" && grep -q "mount -o ro" "$BL"'
check "BitLocker : la cle n'est jamais dans une ligne de commande (ps)"       '! grep -Eq "cryptsetup[^|]*(-p|--password|--key )[ =]*\\\$\{?KEY|dislocker[^|]*-p\\\$" "$BL" && grep -q "printf .%s. \"\$KEY\" | cryptsetup" "$BL"'
check "BitLocker : la cle n'est jamais journalisee"                  '! grep -Eq "audit [A-Z_]+ .*\\\$\{?KEY" "$BL"'

# --- volume reel (optionnel)
if [[ -n "${SONAR_BL_TEST_IMAGE:-}" && -r "${SONAR_BL_TEST_IMAGE}" ]] && [[ $EUID -eq 0 ]] && command -v losetup >/dev/null 2>&1 && command -v cryptsetup >/dev/null 2>&1; then
    _L="$(losetup -f --show -o "${SONAR_BL_TEST_OFFSET:-0}" "$SONAR_BL_TEST_IMAGE" 2>/dev/null)"
    _K="${SONAR_BL_TEST_KEY:-}"; _F="${SONAR_BL_TEST_FILE:-secret.txt}"
    export SONAR_BL_MOUNT_ROOT="$(mktemp -d)" SONAR_AUDIT_FILE="$(mktemp)"
    check "BitLocker (reel) : le volume est detecte par --list"      'bash "$BL" --list 2>/dev/null | grep -q "^$_L"'
    check "BitLocker (reel) : mauvaise cle refusee (code 1)"         'echo 111111-222222-333333-444444-555555-666666-777777-888888 | bash "$BL" --unlock "$_L" --key-stdin --yes >/dev/null 2>&1; [[ $? -eq 1 ]]'
    check "BitLocker (reel) : cle au mauvais format refusee (code 2)" 'echo 12345-6 | bash "$BL" --unlock "$_L" --key-stdin --yes >/dev/null 2>&1; [[ $? -eq 2 ]]'
    check "BitLocker (reel) : bonne cle -> ouvert, fichier lisible"  'echo "$_K" | bash "$BL" --unlock "$_L" --key-stdin --yes >/dev/null 2>&1 && [[ -s "$SONAR_BL_MOUNT_ROOT/$(basename "$_L")/$_F" ]]'
    check "BitLocker (reel) : le montage est en lecture seule"       '! touch "$SONAR_BL_MOUNT_ROOT/$(basename "$_L")/sonar_ecriture_interdite" 2>/dev/null'
    check "BitLocker (reel) : deja ouvert -> refuse (code 1)"        'echo "$_K" | bash "$BL" --unlock "$_L" --key-stdin --yes >/dev/null 2>&1; [[ $? -eq 1 ]]'
    check "BitLocker (reel) : --lock referme proprement"             'bash "$BL" --lock "$_L" >/dev/null 2>&1 && [[ ! -e "/dev/mapper/sonarbl_$(basename "$_L")" ]]'
    check "BitLocker (reel) : le journal contient l'evenement mais JAMAIS la cle" 'grep -q "BITLOCKER_UNLOCKED" "$SONAR_AUDIT_FILE" && ! grep -q "${_K//-/}" <(tr -d "-" < "$SONAR_AUDIT_FILE")'
    losetup -d "$_L" 2>/dev/null; rm -rf "$SONAR_BL_MOUNT_ROOT" "$SONAR_AUDIT_FILE"
else
    printf 'WARN\tBitLocker : aucun volume de test fourni (SONAR_BL_TEST_IMAGE) ou pas root/cryptsetup : ouverture reelle NON testee ici\n'
fi
exit "$fails"
