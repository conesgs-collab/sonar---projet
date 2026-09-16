#!/bin/bash
# SONAR — Script de connexion GitHub
#
# Ce script prépare le dépôt local pour la CI GitHub Actions.
# Il ne fait QUE la configuration Git — il ne pousse rien sans
# votre confirmation explicite.
#
# Usage:
#   ./scripts/setup-github.sh <NOM_REPO_GITHUB>
#   Exemple: ./scripts/setup-github.sh sonar
#
# Prérequis:
#   - Un compte GitHub
#   - gh CLI installé (https://cli.github.com/) OU une clé SSH configurée
#   - Le repo créé sur GitHub (vide, sans README ni .gitignore)

set -euo pipefail

REPO_NAME="${1:-}"

if [[ -z "$REPO_NAME" ]]; then
    echo "Usage: $0 <NOM_REPO_GITHUB>"
    echo "Exemple: $0 sonar"
    echo
    echo "Étapes préalables (à faire sur github.com) :"
    echo "  1. Créer un repo VIDE (pas de README, pas de .gitignore, pas de licence)"
    echo "  2. Noter le nom exact du repo"
    echo "  3. Relancer ce script avec ce nom"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=== SONAR — Connexion GitHub ==="
echo "Répertoire : $(pwd)"
echo "Repo cible : $REPO_NAME"
echo

# Vérifier que Git est disponible
if ! command -v git >/dev/null 2>&1; then
    echo "[ERREUR] git n'est pas installé."
    echo "  Ubuntu/Debian : sudo apt install git"
    echo "  macOS : xcode-select --install"
    exit 1
fi

# Initialiser le dépôt local si nécessaire
if [[ ! -d ".git" ]]; then
    echo "[1/5] Initialisation du dépôt Git local..."
    git init -b main
    echo "  Fait."
else
    echo "[1/5] Dépôt Git déjà initialisé."
fi

# Activer le hook pre-commit
echo "[2/5] Activation du hook pre-commit..."
git config core.hooksPath hooks/
chmod +x hooks/pre-commit 2>/dev/null || true
echo "  core.hooksPath = $(git config --get core.hooksPath)"

# Vérifier qu'un remote n'existe pas déjà
EXISTING_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [[ -n "$EXISTING_REMOTE" ]]; then
    echo "[3/5] Remote 'origin' existe déjà : $EXISTING_REMOTE"
    read -rp "  Remplacer ? (o/N) " replace
    if [[ "$replace" != "o" && "$replace" != "O" ]]; then
        echo "  Conservé tel quel."
    else
        git remote remove origin
        EXISTING_REMOTE=""
    fi
fi

if [[ -z "$EXISTING_REMOTE" ]]; then
    echo "[3/5] Configuration du remote 'origin'..."

    # Essayer gh CLI d'abord
    if command -v gh >/dev/null 2>&1; then
        echo "  Détection de 'gh' CLI..."
        GH_USER=$(gh api user -q .login 2>/dev/null || echo "")
        if [[ -n "$GH_USER" ]]; then
            REMOTE_URL="git@github.com:${GH_USER}/${REPO_NAME}.git"
            echo "  Utilisateur GitHub : $GH_USER"
            git remote add origin "$REMOTE_URL"
            echo "  Remote ajouté : $REMOTE_URL"
        else
            echo "  [ATTENTION] gh n'est pas authentifié. Lancez: gh auth login"
            echo "  En attendant, configurez manuellement :"
            echo "    git remote add origin git@github.com:VOTRE_USER/${REPO_NAME}.git"
        fi
    else
        echo "  gh CLI non détecté. Configuration manuelle requise :"
        echo "    git remote add origin git@github.com:VOTRE_USER/${REPO_NAME}.git"
        echo
        echo "  Alternatives :"
        echo "    - Installer gh : https://cli.github.com/"
        echo "    - Utiliser HTTPS : git remote add origin https://github.com/VOTRE_USER/${REPO_NAME}.git"
    fi
fi

# Ajouter les fichiers au staging
echo "[4/5] Ajout des fichiers au staging..."
git add -A
echo "  Fichiers stagés : $(git diff --cached --stat | tail -1)"

# Résumé (PAS de push automatique)
echo
echo "[5/5] PRÊT. Résumé :"
echo "  Remote : $(git remote get-url origin 2>/dev/null || echo 'NON CONFIGURÉ')"
echo "  Branche : main"
echo "  Fichiers : $(git diff --cached --name-only | wc -l) fichiers stagés"
echo
echo "=== PROCHAINES ÉTAPES (manuelles) ==="
echo
echo "1. Vérifiez que le remote est correct :"
echo "   git remote -v"
echo
echo "2. Commitez (le hook pre-commit s'exécutera automatiquement) :"
echo "   git commit -m 'Initialisation du dépôt SONAR'"
echo
echo "3. Poussez vers GitHub (la CI se lancera automatiquement) :"
echo "   git push -u origin main"
echo
echo "4. Vérifiez que la CI est verte :"
echo "   - Allez sur https://github.com/VOTRE_USER/${REPO_NAME}/actions"
echo "   - Le workflow 'SONAR CI' doit afficher ✓ (vert)"
echo
echo "5. Si la CI est verte, taggez la version :"
echo "   git tag -a v${SONAR_TAG_HINT:-X.Y.Z} -m 'Description de la release'"
echo "   git push --tags"
