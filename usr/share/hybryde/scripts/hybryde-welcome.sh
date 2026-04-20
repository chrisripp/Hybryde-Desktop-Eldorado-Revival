#!/bin/bash

#========================================================================
# hybryde-welcome.sh — Fenêtre de bienvenue au premier lancement
# Lance hybryde-slideshow.py une seule fois (marqueur dans ~/.config/hybryde/)
# Compatible avec autostart.sh — à appeler en fin d'autostart
#========================================================================

SLIDESHOW="/usr/share/hybryde/scripts/slides/hybryde-slideshow.py"
CONF_DIR="$HOME/.config/hybryde"
FIRST_RUN_MARKER="$CONF_DIR/welcome-shown"

mkdir -p "$CONF_DIR"

#========================================================================
# FONCTIONS
#========================================================================

check_python() {
    if ! command -v python3 &> /dev/null; then
        echo "⚠️  python3 absent — hybryde-welcome ignoré"
        return 1
    fi
    return 0
}

check_gtk() {
    if ! python3 -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk" \
         > /dev/null 2>&1; then
        echo "⚠️  PyGObject absent — hybryde-welcome ignoré"
        echo "   sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0"
        return 1
    fi
    return 0
}

check_slideshow() {
    if [ ! -f "$SLIDESHOW" ]; then
        echo "⚠️  $SLIDESHOW introuvable — hybryde-welcome ignoré"
        return 1
    fi
    return 0
}

launch_slideshow() {
    echo "Lancement hybryde-slideshow.py..."
    python3 "$SLIDESHOW" &
    echo "✓ Slideshow lancé (PID $!)"
}

#========================================================================
# POINT D'ENTRÉE
#========================================================================

# Mode --force : ignorer le marqueur et relancer (pour tests ou reset)
if [ "$1" = "--force" ]; then
    echo "[hybryde-welcome] Mode forcé — relancement du slideshow"
    check_python  || exit 1
    check_gtk     || exit 1
    check_slideshow || exit 1
    launch_slideshow
    exit 0
fi

# Mode --reset : supprimer le marqueur (prochaine session = affichage)
if [ "$1" = "--reset" ]; then
    rm -f "$FIRST_RUN_MARKER"
    echo "[hybryde-welcome] Marqueur supprimé — le slideshow s'affichera à la prochaine session"
    exit 0
fi

# Mode --status : dire si le slideshow a déjà été affiché
if [ "$1" = "--status" ]; then
    if [ -f "$FIRST_RUN_MARKER" ]; then
        echo "Slideshow déjà affiché le : $(cat "$FIRST_RUN_MARKER")"
    else
        echo "Slideshow pas encore affiché (premier lancement)"
    fi
    exit 0
fi

# Comportement normal : vérifier si premier lancement
if [ -f "$FIRST_RUN_MARKER" ]; then
    echo "[hybryde-welcome] Déjà affiché — pas de slideshow ($(cat "$FIRST_RUN_MARKER"))"
    exit 0
fi

# Premier lancement : vérifications puis lancement
echo "[hybryde-welcome] Premier lancement détecté"

check_python    || exit 1
check_gtk       || exit 1
check_slideshow || exit 1

# Poser le marqueur AVANT de lancer (évite double lancement si crash)
date "+%Y-%m-%d %H:%M" > "$FIRST_RUN_MARKER"

launch_slideshow
