#!/bin/bash

#========================================================================
# hybx-script.sh - Version Debian Forky v4 (2024)
# Support switching entre environnements sans retour LightDM
#========================================================================

LOG_FILE="/tmp/hybryde-session.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "SESSION HYBRYDE - Démarrage"
date
echo "========================================="

#========================================================================
# VARIABLES
#========================================================================

SWITCHING_FLAG="/tmp/hybryde-switching"

sound="/usr/share/hybryde/sounds/login.ogg"
autostart="$HOME/.hybryde/autostart/autostart.sh"
home="/tmp/home.txt"
tmp="/tmp/hybryde-pid.txt"

#========================================================================
# FONCTIONS DE DÉTECTION
#========================================================================

start_gsd_plugins() {
    echo "Lancement plugins gnome-settings-daemon (GNOME 49)..."
    
    local plugins=(
        "gsd-xsettings"
        "gsd-keyboard"
        "gsd-media-keys"
        "gsd-power"
    )
    
    local started=0
    for plugin in "${plugins[@]}"; do
        local plugin_path="/usr/libexec/$plugin"
        if [ -x "$plugin_path" ]; then
            if ! pgrep -f "$plugin" > /dev/null 2>&1; then
                "$plugin_path" &
                echo $! >> "$tmp"
                echo "  ✓ $plugin démarré"
                started=$((started + 1))
            else
                echo "  ✓ $plugin déjà actif"
                started=$((started + 1))
            fi
        fi
    done
    
    if [ $started -eq 0 ]; then
        echo "  ⚠️  Aucun plugin GSD trouvé (peut utiliser xfsettingsd à la place)"
        return 1
    else
        echo "  ✓ $started plugins GSD actifs"
        return 0
    fi
}

# Détection window manager — Openbox en priorité (plus léger, plus à jour)
if command -v openbox &> /dev/null; then
    wm="openbox"
elif command -v metacity &> /dev/null; then
    wm="metacity"
elif command -v marco &> /dev/null; then
    wm="marco"
else
    echo "✗ ERREUR: Aucun window manager!"
    yad --error --title="Hybryde — Erreur" \
        --text="Aucun window manager trouvé.\nInstallez openbox : <b>sudo apt install openbox</b>" \
        --button="OK:0" --width=360 2>/dev/null
    exit 1
fi

echo "✓ Window Manager: $wm"

# Vérifier Cairo-Dock
if ! command -v cairo-dock &> /dev/null; then
    echo "✗ ERREUR: Cairo-Dock absent!"
    yad --error --title="Hybryde — Erreur" \
        --text="Cairo-Dock absent.\nInstallez-le : <b>sudo apt install cairo-dock</b>" \
        --button="OK:0" --width=360 2>/dev/null
    exit 1
fi

#========================================================================
# PREMIER DÉMARRAGE
#========================================================================

if [ -z "$1" ]; then
    echo "Nettoyage propriétés X..."
    xprop -root -remove _NET_NUMBER_OF_DESKTOPS \
          -remove _NET_DESKTOP_NAMES \
          -remove _NET_CURRENT_DESKTOP 2> /dev/null
    
    if [ -f "$sound" ] && command -v canberra-gtk-play &> /dev/null; then
        canberra-gtk-play -f "$sound" &
    fi
fi

echo "$HOME" > "$home"

#========================================================================
# NETTOYAGE
#========================================================================

echo "Nettoyage processus précédents..."
killall xterm cairo-dock nautilus 2>/dev/null

# Supprimer le flag de switching au démarrage
rm -f "$SWITCHING_FLAG"

#========================================================================
# LANCEMENT WINDOW MANAGER
#========================================================================

echo "Lancement $wm..."
if [ "$wm" = "openbox" ]; then
    # Utiliser la config Openbox de Hybryde si elle existe
    # sinon Openbox utilise ~/.config/openbox/rc.xml par défaut
    openbox --replace &
else
    $wm --replace &
fi
echo $! > "$tmp"
sleep 2

if pgrep -x "$wm" > /dev/null; then
    echo "✓ $wm actif"
else
    echo "✗ ERREUR: $wm n'a pas démarré!"
fi

#========================================================================
# NETTOYAGE PROCESSUS OBSOLÈTES
#========================================================================

echo "Nettoyage processus obsolètes..."
killall unity-applications-daemon unity-window-decorator \
        unity-files-daemon unity-panel-service \
        bamfdaemon zeitgeist-daemon 2>/dev/null

#========================================================================
# SERVICES GNOME/XFCE
#========================================================================

echo "========================================="
echo "Démarrage services système..."
echo "========================================="

# Essayer d'abord les plugins GSD (GNOME 49)
if ! start_gsd_plugins; then
    # Fallback: utiliser xfsettingsd (XFCE)
    echo "Fallback sur xfsettingsd..."
    if command -v xfsettingsd &> /dev/null; then
        if ! pgrep -x xfsettingsd > /dev/null; then
            xfsettingsd &
            echo $! >> "$tmp"
            sleep 1
            echo "✓ xfsettingsd actif"
        else
            echo "✓ xfsettingsd déjà actif"
        fi
    else
        echo "⚠️  Aucun settings daemon disponible"
    fi
fi

# NetworkManager applet
echo ""
echo "NetworkManager applet..."
if ! pgrep -x "nm-applet" > /dev/null; then
    nm-applet &
    echo $! >> "$tmp"
    sleep 1
    if pgrep -x "nm-applet" > /dev/null; then
        echo "✓ nm-applet actif"
    else
        echo "⚠️  nm-applet n'a pas démarré"
    fi
else
    echo "✓ nm-applet déjà actif"
fi

# Nautilus
#echo ""
#echo "Nautilus..."
#if ! pgrep -x "nautilus" > /dev/null; then
    # nautilus --no-default-window &
    # echo $! >> $tmp
#    sleep 2
#    if pgrep -x "nautilus" > /dev/null; then
#        echo "✓ nautilus actif"
#    else
#        echo "⚠️  nautilus n'a pas démarré"
#    fi
#else
#    echo "✓ nautilus déjà actif"
#fi

#sleep 2

#========================================================================
# CAIRO-DOCK
#========================================================================

echo "========================================="
echo "Lancement Cairo-Dock (interface principale)"
echo "========================================="

mkdir -p "$HOME/.dock-accueil" 2>/dev/null
mkdir -p "$HOME/.dock-panel" 2>/dev/null

launch_cairo_dock() {
    local config_dir="$1"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Tentative $attempt/$max_attempts: cairo-dock -c $config_dir"
        
        /usr/bin/cairo-dock -c "$config_dir" &
        local pid=$!
        echo $pid >> "$tmp"
        
        sleep 2
        
        if pgrep -x cairo-dock > /dev/null; then
            echo "✓ Cairo-Dock instance lancée ($config_dir)"
            return 0
        else
            echo "✗ Échec tentative $attempt"
            attempt=$((attempt + 1))
        fi
    done
    
    return 1
}

launch_cairo_dock ".dock-accueil"
launch_cairo_dock ".dock-panel"

CAIRO_COUNT=$(pgrep -x cairo-dock | wc -l)
echo "Instances Cairo-Dock actives: $CAIRO_COUNT"

if [ "$CAIRO_COUNT" -eq 0 ]; then
    echo "✗ ERREUR CRITIQUE: Cairo-Dock n'a pas démarré!"
    yad --error --title="Hybryde — Erreur critique" \
        --text="Cairo-Dock n'a pas démarré !\nConsultez : <tt>$LOG_FILE</tt>" \
        --button="OK:0" --width=400 2>/dev/null
    exit 1
else
    echo "✓ Cairo-Dock actif ($CAIRO_COUNT instances)"
fi

#========================================================================
# AUTOSTART
#========================================================================

if [ -f "$autostart" ]; then
    echo "========================================="
    echo "Exécution autostart.sh..."
    echo "========================================="
    "$autostart" "$1"
    echo "✓ Autostart exécuté"
else
    echo "⚠️  Pas de fichier autostart: $autostart"
fi

#========================================================================
# RÉCAPITULATIF
#========================================================================

echo "========================================="
echo "SESSION HYBRYDE DÉMARRÉE"
echo "========================================="
echo "État des composants:"
pgrep -x "$wm" > /dev/null && echo "  ✓ $wm" || echo "  ✗ $wm"
pgrep -x "cairo-dock" > /dev/null && echo "  ✓ cairo-dock ($CAIRO_COUNT)" || echo "  ✗ cairo-dock"
pgrep -f "gsd-" > /dev/null && echo "  ✓ gsd plugins" || echo "  ⚠️  gsd plugins"
pgrep -x "xfsettingsd" > /dev/null && echo "  ✓ xfsettingsd" || echo "  - xfsettingsd"
pgrep -x "nm-applet" > /dev/null && echo "  ✓ nm-applet" || echo "  ✗ nm-applet"
pgrep -x "nautilus" > /dev/null && echo "  ✓ nautilus" || echo "  ✗ nautilus"
echo "========================================="
echo "Log complet: $LOG_FILE"
echo "========================================="

#========================================================================
# GARDER LA SESSION ACTIVE - AVEC SUPPORT SWITCHING
#========================================================================

echo ""
echo "Session active - en attente..."
echo "La session restera active tant que Cairo-Dock tourne."
echo ""

# Attendre que Cairo-Dock se termine
wait_for_cairo() {
    while true; do
        # Vérifier si Cairo-Dock tourne
        if ! pgrep -x cairo-dock > /dev/null 2>&1; then
            # Cairo-Dock est mort
            
            # Vérifier si on est en train de switcher
            if [ -f "$SWITCHING_FLAG" ]; then
                echo "Switch en cours détecté - Attente..."
                # Attendre que le switch soit terminé
                # Le flag sera supprimé par HYBRYDE.sh ou le nouveau hybx-script.sh
                while [ -f "$SWITCHING_FLAG" ]; do
                    sleep 2
                done
                echo "Switch terminé - Reprise normale"
                # Continuer à attendre Cairo-Dock
                sleep 2
                continue
            else
                # Pas de switch en cours, Cairo-Dock a été tué normalement
                echo "Cairo-Dock terminé - Fin de session"
                break
            fi
        fi
        
        sleep 5
    done
}

# Attendre Cairo-Dock
wait_for_cairo

# Nettoyage à la sortie
echo "Nettoyage avant sortie..."
rm -f "$SWITCHING_FLAG"
killall openbox metacity marco nm-applet nautilus 2>/dev/null

exit 0
