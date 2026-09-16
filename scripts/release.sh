#!/bin/bash
# SONAR — Script de release avec signature GPG
#
# Crée un tarball signé pour distribution publique.
# Utiliser APRÈS que la CI est verte et les tests matériels passés.
#
# Usage:
#   ./scripts/release.sh <VERSION>
#   Exemple: ./scripts/release.sh 3.31.0
#
# Prérequis:
#   - Clé GPG configurée (gpg --list-keys)
#   - git tag de la version déjà créé
#   - CI verte sur le commit du tag

set -euo pipefail

VERSION="${1:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <VERSION>"
    echo "Exemple: $0 3.31.0"
    echo
    echo "Prérequis :"
    echo "  1. git tag -a v<VERSION> -m 'Description'"
    echo "  2. CI verte sur le commit du tag"
    echo "  3. gpg --list-keys (au moins une clé disponible)"
    exit 1
fi

cd "$PROJECT_DIR"

RELEASE_DIR="${PROJECT_DIR}/RELEASE"
RELEASE_NAME="sonar-${VERSION}"
TARBALL="${RELEASE_NAME}.tar.gz"
CHECKSUM="${TARBALL}.sha256"
SIGNATURE="${TARBALL}.asc"

echo "=== SONAR Release v${VERSION} ==="
echo

# Vérifications
if ! command -v gpg >/dev/null 2>&1; then
    echo "[ERREUR] gpg n'est pas installé."
    exit 1
fi

GPG_KEYS=$(gpg --list-keys --keyid-format long 2>/dev/null | grep -c '^pub' || echo 0)
if [[ "$GPG_KEYS" -eq 0 ]]; then
    echo "[ERREUR] Aucune clé GPG trouvée."
    echo "  Créez-en une : gpg --full-generate-key"
    exit 1
fi

# Vérifier le tag
if ! git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "[ERREUR] Le tag v${VERSION} n'existe pas."
    echo "  Créez-le : git tag -a v${VERSION} -m 'Release ${VERSION}'"
    exit 1
fi

# Créer le répertoire de release
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "[1/6] Création de l'archive..."
git archive --format=tar.gz --prefix="${RELEASE_NAME}/" "v${VERSION}" \
    -o "${RELEASE_DIR}/${TARBALL}"
echo "  ${TARBALL} : $(du -h "${RELEASE_DIR}/${TARBALL}" | cut -f1)"

echo "[2/6] Calcul du checksum SHA-256..."
cd "$RELEASE_DIR"
sha256sum "$TARBALL" > "$CHECKSUM"
echo "  $(cat "$CHECKSUM")"

echo "[3/6] Signature GPG du tarball..."
gpg --armor --detach-sign "$TARBALL"
echo "  ${SIGNATURE} créé"

echo "[4/6] Signature GPG du checksum..."
gpg --armor --detach-sign "$CHECKSUM"
echo "  ${CHECKSUM}.asc créé"

echo "[5/6] Vérification des signatures..."
gpg --verify "${SIGNATURE}" "$TARBALL" 2>&1 | head -3
echo
gpg --verify "${CHECKSUM}.asc" "$CHECKSUM" 2>&1 | head -3

echo "[6/6] Résumé de la release..."
echo
echo "=== Fichiers de release ==="
ls -lh "${RELEASE_DIR}/"
echo
echo "=== Instructions pour les utilisateurs ==="
echo
echo "# Télécharger"
echo "wget https://github.com/USER/sonar/releases/download/v${VERSION}/${TARBALL}"
echo "wget https://github.com/USER/sonar/releases/download/v${VERSION}/${SIGNATURE}"
echo "wget https://github.com/USER/sonar/releases/download/v${VERSION}/${CHECKSUM}"
echo
echo "# Vérifier le checksum"
echo "sha256sum -c ${CHECKSUM}"
echo
echo "# Vérifier la signature (après import de la clé publique)"
echo "gpg --verify ${SIGNATURE} ${TARBALL}"
echo
echo "# Extraire"
echo "tar xzf ${TARBALL}"
echo "cd ${RELEASE_NAME}/"
echo "chmod +x sonar_master.sh"
echo "./sonar_master.sh --self-audit && ./sonar_master.sh --self-test"
echo
echo "Release prête dans : ${RELEASE_DIR}/"
echo "Uploadez ces fichiers sur GitHub Releases :"
echo "  - ${TARBALL}"
echo "  - ${SIGNATURE}"
echo "  - ${CHECKSUM}"
echo "  - ${CHECKSUM}.asc"
