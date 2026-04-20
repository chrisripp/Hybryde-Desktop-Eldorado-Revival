#!/bin/bash
#
# About Hybryde - Script de lancement
# Version modernisée pour Python 3
#

# Déterminer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chemins possibles pour le script Python
PYTHON_SCRIPT_PATHS=(
    "/usr/share/hybryde/scripts/slides/about-hybryde-py3.sh"
    "/usr/share/hybryde/scripts/about-hybryde-py3.sh"
    "$SCRIPT_DIR/about-hybryde-py3.sh"
)

# Trouver le script Python
PYTHON_SCRIPT=""
for path in "${PYTHON_SCRIPT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        PYTHON_SCRIPT="$path"
        break
    fi
done

if [ -z "$PYTHON_SCRIPT" ]; then
    echo "Erreur: Impossible de trouver le script Python about-hybryde-py3.sh"
    echo "Chemins recherchés:"
    printf '%s\n' "${PYTHON_SCRIPT_PATHS[@]}"
    exit 1
fi

# Vérifier que les dépendances sont installées
if ! python3 -c "import gi; gi.require_version('Gtk', '3.0')" 2>/dev/null; then
    echo "Erreur: Les dépendances requises ne sont pas installées."
    echo ""
    echo "Pour installer les dépendances, exécutez:"
    echo "  sudo apt install python3-gi gir1.2-webkit2-4.1"
    echo ""
    echo "Ou avec la version 6.0 :"
    echo "  sudo apt install python3-gi gir1.2-webkit-6.0"
    echo ""
    echo "Autres distributions:"
    echo "  - Fedora/RHEL: sudo dnf install python3-gobject webkit2gtk4.1"
    echo "  - Arch: sudo pacman -S python-gobject webkit2gtk-4.1"
    exit 1
fi

# Vérifier WebKit2GTK (essayer 4.1 puis 6.0)
WEBKIT_OK=false
for version in "4.1" "6.0" "4.0"; do
    if python3 -c "import gi; gi.require_version('WebKit2', '$version')" 2>/dev/null; then
        WEBKIT_OK=true
        break
    fi
done

if [ "$WEBKIT_OK" = false ]; then
    echo "Erreur: WebKit2GTK n'est pas installé."
    echo ""
    echo "Pour installer les dépendances, exécutez:"
    echo "  sudo apt install python3-gi gir1.2-webkit2-4.1"
    echo ""
    echo "Ou avec la version 6.0 :"
    echo "  sudo apt install python3-gi gir1.2-webkit-6.0"
    echo ""
    echo "Autres distributions:"
    echo "  - Fedora/RHEL: sudo dnf install python3-gobject webkit2gtk4.1"
    echo "  - Arch: sudo pacman -S python-gobject webkit2gtk-4.1"
    exit 1
fi

# Lancer l'application Python
exec python3 "$PYTHON_SCRIPT" "$@"
