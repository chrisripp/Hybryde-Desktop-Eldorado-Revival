#!/bin/bash

#========================================================================
# autostart.sh - Version modernisée 2024
# Compatible Debian Forky
#========================================================================

# Fichier pour stocker les PIDs
PID_FILE="/tmp/hybryde-pid.txt"

# Fonction pour lancer et enregistrer un processus
start_process() {
    local cmd="$1"
    local name="$2"
    
    if command -v "$cmd" &> /dev/null; then
        "$cmd" &
        echo $! >> "$PID_FILE"
        echo "✓ Démarré: $name"
    else
        echo "✗ Non trouvé: $name ($cmd)"
    fi
}

# Fonction pour lancer avec des arguments
start_process_args() {
    local name="$1"
    shift
    
    if command -v "$1" &> /dev/null; then
        "$@" &
        echo $! >> "$PID_FILE"
        echo "✓ Démarré: $name"
    else
        echo "✗ Non trouvé: $name"
    fi
}

echo "=== Démarrage autostart Hybryde ==="

#========================================================================
# THÈME GTK — Restauration au retour depuis un autre DE
#========================================================================

GTK_CONF="$HOME/.config/hybryde/gtk-settings.conf"

save_gtk_theme() {
    mkdir -p "$HOME/.config/hybryde"
    {
        echo "HYB_GTK_THEME=$(gsettings get org.gnome.desktop.interface gtk-theme    2>/dev/null | tr -d "'")"
        echo "HYB_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme  2>/dev/null | tr -d "'")"
        echo "HYB_CURSOR_THEME=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")"
        echo "HYB_FONT_NAME=$(gsettings get org.gnome.desktop.interface font-name    2>/dev/null | tr -d "'")"
    } > "$GTK_CONF"
    echo "✓ Thème GTK initial sauvegardé dans $GTK_CONF"
}

restore_gtk_theme() {
    if [ -f "$GTK_CONF" ]; then
        # shellcheck source=/dev/null
        source "$GTK_CONF"
        [ -n "$HYB_GTK_THEME" ]    && gsettings set org.gnome.desktop.interface gtk-theme    "$HYB_GTK_THEME"
        [ -n "$HYB_ICON_THEME" ]   && gsettings set org.gnome.desktop.interface icon-theme   "$HYB_ICON_THEME"
        [ -n "$HYB_CURSOR_THEME" ] && gsettings set org.gnome.desktop.interface cursor-theme "$HYB_CURSOR_THEME"
        [ -n "$HYB_FONT_NAME" ]    && gsettings set org.gnome.desktop.interface font-name    "$HYB_FONT_NAME"
        # GTK2 — réappliquer si le thème est disponible
        if [ -n "$HYB_GTK_THEME" ] && [ -f "$HOME/.gtkrc-2.0" ] && \
           [ -d "/usr/share/themes/$HYB_GTK_THEME" ]; then
            sed -i "s/^gtk-theme-name=.*/gtk-theme-name=\"$HYB_GTK_THEME\"/" \
                "$HOME/.gtkrc-2.0" 2>/dev/null
        fi
        echo "✓ Thème GTK restauré : ${HYB_GTK_THEME:-?} / icônes : ${HYB_ICON_THEME:-?}"
    else
        # Première session : pas encore de sauvegarde, on crée la référence
        save_gtk_theme
    fi
}

restore_gtk_theme

#========================================================================
# SERVICES ESSENTIELS
#========================================================================

# gnome-settings-daemon est normalement déjà lancé par hybx-script.sh
# On ne le relance que s'il n'est pas déjà actif
if ! pgrep -x "gnome-settings-daemon" > /dev/null 2>&1; then
    start_process "gnome-settings-daemon" "GNOME Settings Daemon"
fi

#========================================================================
# RÉSEAU - NetworkManager
#========================================================================

# Tuer wicd s'il tourne encore (pour éviter les conflits)
killall wicd-client wicd-daemon 2>/dev/null

# nm-applet est normalement déjà lancé par hybx-script.sh
if ! pgrep -x "nm-applet" > /dev/null 2>&1; then
    start_process "nm-applet" "NetworkManager Applet"
fi

#========================================================================
# BARRE DE TÂCHES
#========================================================================

# Tint2 - non disponible sur Forky
# start_process "tint2" "Tint2 Panel"

#========================================================================
# GESTION DE L'ÉNERGIE
#========================================================================

if command -v xfce4-power-manager &> /dev/null; then
    start_process "xfce4-power-manager" "XFCE Power Manager"
elif command -v mate-power-manager &> /dev/null; then
    start_process "mate-power-manager" "MATE Power Manager"
elif command -v gnome-power-manager &> /dev/null; then
    start_process "gnome-power-manager" "GNOME Power Manager"
else
    echo "⚠️  Aucun gestionnaire d'énergie trouvé"
fi

#========================================================================
# SERVICES OPTIONNELS
#========================================================================

# PolicyKit Agent (pour authentification graphique)
# Tuer toute instance précédente pour éviter les doublons au retour depuis un autre DE
killall xfce-polkit polkit-mate-authentication-agent-1 \
        polkit-gnome-authentication-agent-1 2>/dev/null
sleep 0.5

if [ -x /usr/libexec/xfce-polkit ]; then
    /usr/libexec/xfce-polkit &
    echo $! >> "$PID_FILE"
    echo "✓ Démarré: xfce-polkit"
elif [ -x /usr/libexec/polkit-mate-authentication-agent-1 ]; then
    /usr/libexec/polkit-mate-authentication-agent-1 &
    echo $! >> "$PID_FILE"
    echo "✓ Démarré: PolicyKit MATE Agent"
else
    echo "⚠️  Aucun agent PolicyKit trouvé"
fi

# Gestionnaire de presse-papier (optionnel)
if command -v clipit &> /dev/null; then
    start_process "clipit" "Clipboard Manager"
elif command -v parcellite &> /dev/null; then
    start_process "parcellite" "Clipboard Manager"
fi

#========================================================================
# COMPOSITEUR pour transparence et effets
#========================================================================

# Lire la préférence utilisateur (sauvegardée par hybryde-config.sh)
CONF_FILE="$HOME/.config/hybryde/session.conf"
COMPOSITOR_ENABLED="true"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
fi

if [ "$1" != "no-compositor" ] && [ "$COMPOSITOR_ENABLED" = "true" ]; then
    if ! pgrep -x "picom"    > /dev/null 2>&1 && \
       ! pgrep -x "compton"  > /dev/null 2>&1 && \
       ! pgrep -x "xcompmgr" > /dev/null 2>&1; then
        sleep 1
        if command -v picom &> /dev/null; then
            start_process_args "Picom Compositor" picom --backend xrender --no-vsync -b
        elif command -v compton &> /dev/null; then
            start_process_args "Compton Compositor" compton --backend xrender -b
        fi
    else
        echo "✓ Compositeur déjà actif"
    fi
elif [ "$COMPOSITOR_ENABLED" = "false" ]; then
    echo "✓ Compositeur désactivé par préférence utilisateur"
    killall picom compton xcompmgr 2>/dev/null
fi

#========================================================================
# APPLICATIONS UTILISATEUR (Personnalisable)
#========================================================================

# Fond d'écran — toujours restaurer depuis ~/.fehbg-hybryde (référence Hybryde)
# ~/.fehbg peut avoir été écrasé par un DE invité (GNOME, Cinnamon, MATE…)
if command -v feh &> /dev/null; then
    if [ -f "$HOME/.fehbg-hybryde" ]; then
        # Retour depuis un DE invité : restaurer la référence Hybryde
        cp "$HOME/.fehbg-hybryde" "$HOME/.fehbg"
        bash "$HOME/.fehbg" &
        echo "✓ Fond d'écran Hybryde restauré depuis .fehbg-hybryde"
    elif [ -f "$HOME/.fehbg" ]; then
        # Premier démarrage : sauvegarder comme référence et appliquer
        cp "$HOME/.fehbg" "$HOME/.fehbg-hybryde"
        bash "$HOME/.fehbg" &
        echo "✓ Fond d'écran appliqué et sauvegardé comme référence Hybryde"
    else
        echo "⚠️  Aucun fichier .fehbg trouvé"
    fi
else
    echo "⚠️  feh non disponible — fond d'écran non restauré"
fi

# Conky (optionnel)
# if command -v conky &> /dev/null; then
#     start_process "conky" "Conky System Monitor"
# fi

# Redshift (optionnel)
# if command -v redshift-gtk &> /dev/null; then
#     start_process "redshift-gtk" "Redshift"
# fi

#========================================================================
# APPLICATIONS PERSONNALISÉES
#========================================================================

# start_process "syncthing-gtk" "Syncthing"
# start_process "dropbox" "Dropbox"

echo "=== Autostart terminé ==="

# Relance feh avec délai en fin d'autostart pour garantir que le fond d'écran
# Hybryde s'applique APRÈS les settings daemons (gsd-*, mate-settings-daemon…)
# qui pourraient repaindre leur propre fond au démarrage de leurs plugins.
if command -v feh &>/dev/null && [ -f "$HOME/.fehbg-hybryde" ]; then
    (sleep 6 && bash "$HOME/.fehbg-hybryde") &
fi

exit 0
