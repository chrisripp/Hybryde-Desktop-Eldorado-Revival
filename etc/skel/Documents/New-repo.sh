#!/bin/bash

# Vérifie si un nom est fourni
if [ -z "$1" ]; then
  echo "❌ Usage: ./newrepo.sh nom-du-repo [public|private]"
  exit 1
fi

REPO_NAME=$1
VISIBILITY=${2:-public}  # public par défaut

echo "🚀 Création du repo $REPO_NAME ($VISIBILITY)..."

# Création du repo sur GitHub
gh repo create "$REPO_NAME" --$VISIBILITY --confirm

# Création du dossier local
mkdir "$REPO_NAME"
cd "$REPO_NAME" || exit

# Initialisation git
git init
echo "# $REPO_NAME" > README.md
git add .
git commit -m "Initial commit"

# Lien avec le repo distant
git branch -M main
git remote add origin https://github.com/$(gh api user -q .login)/$REPO_NAME.git
git push -u origin main

echo "✅ Repo prêt : https://github.com/$(gh api user -q .login)/$REPO_NAME"
