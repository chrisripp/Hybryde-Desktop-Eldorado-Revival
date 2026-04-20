#!/bin/bash

#========================================================================
# HYBRYDE.sh - Version v4.10 (2024)
# Script de gestion multi-environnements
# Correction: GPU busy - GNOME Classic avec Metacity, GNOME Shell libère GPU
#========================================================================

# Obtenir le dernier PID
last_pid=$(ps -A | tail -1 | awk '{print $1}')
export last_pid=$last_pid

# Flag pour indiquer qu'on est en train de switcher
SWITCHING_FLAG="/tmp/hybryde-switching"

# Flag de retour vers Hybryde (lu par hybryde-session.sh)
FLAG_RETURN="/tmp/hybryde-return-flag"

# Sécurité : si HYBRYDE.sh quitte pour n'importe quelle raison,
# garantir que la session revient à Hybryde et non à LightDM
trap 'touch "$FLAG_RETURN"; rm -f "$SWITCHING_FLAG"' EXIT

# Sauvegarder les variables d'environnement X
export SAVED_DISPLAY="$DISPLAY"
export SAVED_XAUTHORITY="$XAUTHORITY"

#========================================================================
# FONCTIONS DE NETTOYAGE
#========================================================================

killprocess()
{
    # Sauvegarder le thème GTK Hybryde AVANT de passer au DE cible
    # (chaque DE écrase DConf avec ses propres thèmes)
    GTK_CONF="$HOME/.config/hybryde/gtk-settings.conf"
    mkdir -p "$HOME/.config/hybryde"
    {
        echo "HYB_GTK_THEME=$(gsettings get org.gnome.desktop.interface gtk-theme    2>/dev/null | tr -d "'")"
        echo "HYB_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme  2>/dev/null | tr -d "'")"
        echo "HYB_CURSOR_THEME=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")"
        echo "HYB_FONT_NAME=$(gsettings get org.gnome.desktop.interface font-name    2>/dev/null | tr -d "'")"
    } > "$GTK_CONF"
    echo "✓ Thème GTK Hybryde sauvegardé"

    # Créer le flag AVANT de tuer Cairo-Dock
    echo "switching" > "$SWITCHING_FLAG"
    echo "Création flag switching..."
    sleep 1
    
    # Tuer TOUS les Cairo-Dock de manière agressive
    echo "Arrêt de Cairo-Dock..."
    killall -9 cairo-dock 2>/dev/null
    sleep 1
    
    # Double vérification
    if pgrep -x cairo-dock > /dev/null 2>&1; then
        echo "  Processus Cairo-Dock persistants, forçage..."
        pkill -9 -x cairo-dock 2>/dev/null
        sleep 1
    fi
    
    # Vérifier que Cairo-Dock est bien mort
    local retries=0
    while pgrep -x cairo-dock > /dev/null 2>&1 && [ $retries -lt 5 ]; do
        echo "  Cairo-Dock encore actif, tentative $((retries+1))/5..."
        killall -9 cairo-dock 2>/dev/null
        sleep 1
        retries=$((retries + 1))
    done
    
    if ! pgrep -x cairo-dock > /dev/null 2>&1; then
        echo "✓ Cairo-Dock arrêté"
    else
        echo "⚠️  Cairo-Dock partiellement arrêté"
    fi
    
    # Lire les PIDs de la session Hybryde actuelle
    if [ -f /tmp/hybryde-pid.txt ]; then
        accueil=$(cat /tmp/hybryde-pid.txt)
        for i in $accueil; do
            kill -9 "$i" 2>/dev/null
        done
    fi
    
    # Tuer les processus spécifiques à Hybryde
    for process in nautilus tint2 metacity marco openbox lxpanel; do
        pid=$(pidof "$process")
        if [ -n "$pid" ]; then
            kill -9 "$pid" 2>/dev/null
        fi
    done

    # Tuer les services lancés par l'autostart Hybryde
    # xfce-polkit est tué ici pour laisser le DE cible gérer son propre agent polkit
    echo "Nettoyage services autostart..."
    killall xfce-polkit \
            polkit-mate-authentication-agent-1 \
            polkit-gnome-authentication-agent-1 \
            dunst xfce4-power-manager mate-power-manager \
            nm-applet clipit parcellite 2>/dev/null

    # Tuer picom avec -9 et attendre sa mort effective avant de libérer le slot X
    killall -9 picom compton xcompmgr 2>/dev/null
    local picom_die=0
    while pgrep -x picom > /dev/null 2>&1 && [ $picom_die -lt 5 ]; do
        sleep 1
        picom_die=$((picom_die + 1))
    done
    # Libérer le slot compositor X11 (_NET_WM_CM_S0) que picom aurait pu laisser occupé
    xprop -root -remove _NET_WM_CM_S0 2>/dev/null
    echo "✓ Slot compositor X libéré"

    # Tuer les plugins gsd lancés par hybx-script.sh
    killall gsd-xsettings gsd-keyboard gsd-media-keys gsd-power 2>/dev/null

    # Masquer le fond d'écran Hybryde pendant la transition
    xsetroot -solid black 2>/dev/null

    sleep 2
}

wait_for_session_end()
{
    local session_process="$1"
    local timeout="${2:-30}"
    local max_wait=1800  # 30 minutes max
    local elapsed=0
    
    echo "Attente de la fin de $session_process (timeout démarrage: ${timeout}s)..."
    
    # Attendre que le processus démarre d'abord
    echo "Attente du démarrage de $session_process..."
    local start_wait=0
    while [ $start_wait -lt $timeout ]; do
        if pgrep -x "$session_process" > /dev/null 2>&1; then
            echo "✓ $session_process démarré après ${start_wait}s"
            break
        fi
        sleep 1
        start_wait=$((start_wait + 1))
        
        # Log tous les 10 secondes
        if [ $((start_wait % 10)) -eq 0 ] && [ $start_wait -gt 0 ]; then
            echo "  ... attente ${start_wait}s/${timeout}s ..."
        fi
    done
    
    if [ $start_wait -ge $timeout ]; then
        echo "⚠️  $session_process n'a pas démarré dans les ${timeout} secondes"
        echo "  Vérifiez les logs pour plus d'informations"
        return 1
    fi
    
    # Maintenant attendre qu'il se termine
    while [ $elapsed -lt $max_wait ]; do
        if ! pgrep -x "$session_process" > /dev/null 2>&1; then
            echo "$session_process terminé"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    echo "Timeout - Forçage de la fermeture de $session_process"
    killall "$session_process" 2>/dev/null
    sleep 2
    return 1
}

return_to_hybryde()
{
    echo "Retour à Hybryde..."

    export DISPLAY="$SAVED_DISPLAY"
    export XAUTHORITY="$SAVED_XAUTHORITY"

    # Poser FLAG_RETURN pour que hybryde-session.sh relance hybx-script.sh
    touch "$FLAG_RETURN"
    # Supprimer SWITCHING_FLAG pour débloquer wait_for_cairo() dans hybx-script.sh
    rm -f "$SWITCHING_FLAG"

    # Sortir proprement — c'est hybryde-session.sh qui fait le relancement
    exit 0
}

#========================================================================
# FONCTIONS D'ENVIRONNEMENTS DE BUREAU
#========================================================================

# GNOME Panel (GNOME Classique)
gnome_panel()
{
    killprocess
    
    echo "Lancement GNOME Classique..."
    echo "Pour revenir à Hybryde : lancez 'retour-hybryde' ou tuez gnome-panel"
    
    export DISPLAY="$SAVED_DISPLAY"
    export XAUTHORITY="$SAVED_XAUTHORITY"
    
    export GNOME_SHELL_SESSION_MODE=classic
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=GNOME-Classic
    
    if command -v gnome-panel &> /dev/null; then
        echo "Lancement Metacity + GNOME Panel..."
        metacity --replace > /tmp/gnome-classic-metacity.log 2>&1 &
        sleep 2
        
        gnome-panel > /tmp/gnome-classic-panel.log 2>&1 &
        
        wait_for_session_end "gnome-panel" 30
    else
        yad --error --title="Hybryde — Erreur" \
            --text="GNOME Panel n'est pas installé.\nPaquets requis : <b>gnome-panel</b>" \
            --button="OK:0" --width=360 2>/dev/null
        rm -f "$SWITCHING_FLAG"
        return 1
    fi
    
    killall gnome-panel metacity 2>/dev/null
    return_to_hybryde
}

# GNOME 3 / GNOME Shell
gnome3()
{
    killprocess

    echo "Lancement GNOME Shell..."
    echo "Pour revenir à Hybryde : lancez 'retour-hybryde' ou tuez gnome-session"

    export DISPLAY="$SAVED_DISPLAY"
    export XAUTHORITY="$SAVED_XAUTHORITY"

    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=GNOME
    export XDG_SESSION_DESKTOP=gnome
    export GNOME_SHELL_SESSION_MODE=user

    unset GNOME_SETUP_DISPLAY
    unset GDM_SESSION

    if ! command -v gnome-session &> /dev/null; then
        yad --error --title="Hybryde — Erreur" \
            --text="gnome-session n'est pas installé.\n<b>sudo apt install gnome-session</b>" \
            --button="OK:0" --width=360 2>/dev/null
        return 1
    fi
    if ! command -v gnome-shell &> /dev/null; then
        yad --error --title="Hybryde — Erreur" \
            --text="gnome-shell n'est pas installé.\n<b>sudo apt install gnome-shell</b>" \
            --button="OK:0" --width=360 2>/dev/null
        return 1
    fi

    # Libérer le GPU : tuer tout compositeur/WM encore actif
    killall metacity marco openbox lxpanel mutter compton picom xcompmgr 2>/dev/null
    sleep 2

    echo "Démarrage gnome-session --session=gnome-flashback-metacity..."
    gnome-session --session=gnome-flashback-metacity > /tmp/gnome-session.log 2>&1 &

    wait_for_session_end "gnome-flashback" 60

    killall gnome-flashback gnome-session-ctl gnome-session-service \
            gnome-session-init-worker gnome-shell mutter gnome-panel metacity 2>/dev/null
    sleep 2
    return_to_hybryde
}

# KDE Plasma
kde()
{
    cd "$HOME" || exit
    killprocess
    
    echo "Lancement KDE Plasma..."
    echo "Pour revenir à Hybryde : lancez 'retour-hybryde' ou tuez plasmashell"
    echo ""
    
    export DISPLAY="$SAVED_DISPLAY"
    export XAUTHORITY="$SAVED_XAUTHORITY"
    
    if command -v startplasma-x11 &> /dev/null; then
        echo "Démarrage de KDE Plasma (mode sans systemd)..."
        echo "Ceci peut prendre 30-60 secondes..."
        
        startplasma-x11 --no-systemd > /tmp/kde-plasma.log 2>&1 &
        
        wait_for_session_end "plasmashell" 60
        
    elif command -v startkde &> /dev/null; then
        echo "Démarrage de KDE 4..."
        startkde > /tmp/kde-plasma.log 2>&1 &
        wait_for_session_end "plasma-desktop" 60
        
    else
        yad --error --title="Hybryde — Erreur" \
            --text="KDE Plasma n'est pas installé." \
            --button="OK:0" --width=300 2>/dev/null
        rm -f "$SWITCHING_FLAG"
        return 1
    fi
    
    echo "Nettoyage processus KDE..."
    killall plasmashell kwin_x11 kded5 kded4 kdeinit5 kdeinit4 \
            klauncher knotify4 knotify5 kuiserver 2>/dev/null
    
    sleep 3
    
    return_to_hybryde
}

# XFCE
kill_naut()
{
    while :; do
        sleep 5
        if pidof nautilus > /dev/null; then
            pid=$(pidof nautilus)
            kill -9 "$pid" 2>/dev/null
        else
            break
        fi
    done
}

xfce()
{
    kill_naut &
    killprocess
    
    echo "Lancement XFCE..."
    echo "Pour revenir à Hybryde : lancez 'retour-hybryde.sh' ou tuez xfce4-session"
    
    xfce4-session &
    
    wait_for_session_end "xfce4-session"
    
    killall xfsettingsd xfconfd nautilus 2>/dev/null
    
    return_to_hybryde
}

# LXDE
lxde()
{
    cd "$HOME" || exit
    kill_naut &

    echo "Lancement LXDE..."
    echo "Pour revenir à Hybryde : lancez 'retour-hybryde' ou tuez lxsession"

    export DISPLAY="$SAVED_DISPLAY"
    export XAUTHORITY="$SAVED_XAUTHORITY"
    export XDG_CURRENT_DESKTOP=LXDE
    export XDG_SESSION_DESKTOP=LXDE

    # Tuer Cairo-Dock et services Hybryde SANS tuer Openbox
    # lxsession a besoin d'Openbox comme WM — il le récupère avec --replace
    echo "switching" > "$SWITCHING_FLAG"
    killall -9 cairo-dock 2>/dev/null
    sleep 1
    if [ -f /tmp/hybryde-pid.txt ]; then
        for i in $(cat /tmp/hybryde-pid.txt); do
            kill -9 "$i" 2>/dev/null
        done
    fi
    killall xfce-polkit \
            polkit-mate-authentication-agent-1 \
            polkit-gnome-authentication-agent-1 \
            dunst xfce4-power-manager mate-power-manager \
            picom compton xcompmgr \
            nm-applet clipit parcellite 2>/dev/null
    killall gsd-xsettings gsd-keyboard gsd-media-keys gsd-power 2>/dev/null
    xsetroot -solid black 2>/dev/null
    sleep 2

    lxsession &

    wait_for_session_end "lxsession"

    killall lxpanel pcmanfm openbox 2>/dev/null

    return_to_hybryde
}

# LXQt
lxqt()
{
    cd "$HOME" || exit
    killprocess
    
    echo "Lancement LXQt..."
    startlxqt &
    
    wait_for_session_end "lxqt-session"
    
    killall lxqt-panel 2>/dev/null
    
    return_to_hybryde
}

# Enlightenment
enlightenment()
{
    killprocess
    
    echo "Lancement Enlightenment..."
    echo "Pour revenir à Hybryde : lancez 'retour-hybryde' ou tuez enlightenment"
    
    if command -v enlightenment_start &> /dev/null; then
        echo "Vérification finale Cairo-Dock..."
        killall -9 cairo-dock 2>/dev/null
        sleep 2
        
        enlightenment_start > /tmp/enlightenment.log 2>&1 &
        wait_for_session_end "enlightenment"
    else
        yad --error --title="Hybryde — Erreur" \
            --text="Enlightenment n'est pas installé." \
            --button="OK:0" --width=300 2>/dev/null
        rm -f "$SWITCHING_FLAG"
        return 1
    fi
    
    return_to_hybryde
}

# Openbox
openbox()
{
    killprocess
    
    echo "Lancement Openbox..."
    openbox-session &
    
    wait_for_session_end "openbox"
    
    return_to_hybryde
}

# Mate Desktop
mate()
{
    killprocess
    
    echo "Lancement MATE..."
    mate-session &
    
    wait_for_session_end "mate-session"
    
    return_to_hybryde
}

# Cinnamon
cinnamon()
{
    killprocess

    echo "Lancement Cinnamon..."
    echo "Pour revenir à Hybryde : lancez 'retour-hybryde' ou tuez cinnamon-session"

    export DISPLAY="$SAVED_DISPLAY"
    export XAUTHORITY="$SAVED_XAUTHORITY"
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=X-Cinnamon
    export XDG_SESSION_DESKTOP=cinnamon
    export GNOME_SHELL_SESSION_MODE=user

    if ! command -v cinnamon-session &> /dev/null; then
        yad --error --title="Hybryde — Erreur" \
            --text="Cinnamon n'est pas installé.\n<b>sudo apt install cinnamon</b>" \
            --button="OK:0" --width=360 2>/dev/null
        return 1
    fi

    # killprocess() a déjà tué picom et libéré _NET_WM_CM_S0
    sleep 1

    cinnamon-session > /tmp/cinnamon-session.log 2>&1 &

    # Cinnamon relaнce picom via /etc/xdg/autostart pendant ses 10 premières
    # secondes — on surveille et on le tue en boucle pour laisser muffin
    # prendre le slot compositor _NET_WM_CM_S0
    (
        for i in $(seq 1 15); do
            sleep 1
            if pgrep -x picom > /dev/null 2>&1; then
                echo "[anti-picom] picom relancé par Cinnamon — forçage arrêt (${i}s)"
                killall -9 picom 2>/dev/null
                xprop -root -remove _NET_WM_CM_S0 2>/dev/null
            fi
        done
        echo "[anti-picom] Surveillance terminée"
    ) &

    # Surveiller "cinnamon" (le shell JS, 8 chars) plutôt que "muffin"
    # car muffin peut rater son démarrage si picom reprend le slot en premier.
    # Cinnamon fonctionne quand même (animations désactivées), et "cinnamon"
    # reste vivant pour toute la durée de la session.
    wait_for_session_end "cinnamon" 60

    killall cinnamon cinnamon-session muffin nemo 2>/dev/null
    sleep 2
    return_to_hybryde
}

#========================================================================
# MENU DE SÉLECTION
#========================================================================

show_menu()
{
    CHOICE=$(yad \
        --center \
        --borders=14 \
        --title="Hybryde — Sélection d'environnement" \
        --window-icon="preferences-desktop" \
        --list \
        --text="<big><b>Choisissez un environnement de bureau</b></big>\n\nPour revenir à Hybryde : utilisez <b>retour-hybryde</b>\n\n<small>KDE et GNOME peuvent prendre 30–60 secondes à démarrer</small>" \
        --column="ID" \
        --column="Icône:IMG" \
        --column="Environnement" \
        --column="Description" \
        "gnome_panel"   "gnome-panel"             "GNOME Classique"  "Interface traditionnelle GNOME" \
        "gnome3"        "user-desktop"             "GNOME Shell"      "Interface moderne GNOME" \
        "kde"           "kde"                      "KDE Plasma"       "Bureau KDE complet" \
        "xfce"          "xfce4-logo"               "XFCE"             "Bureau léger et rapide" \
        "lxqt"          "lxqt"                     "LXQt"             "LXDE modernisé" \
        "mate"          "mate"                     "MATE"             "Fork de GNOME 2" \
        "cinnamon"      "cinnamon"                 "Cinnamon"         "Bureau Linux Mint" \
        "openbox"       "openbox"                  "Openbox"          "Gestionnaire de fenêtres minimal" \
        "enlightenment" "enlightenment"            "Enlightenment"    "Bureau élégant" \
        --print-column=1 \
        --hide-column=1 \
        --separator="" \
        --width=680 --height=460 \
        --button="Annuler:1" \
        --button="Lancer:0")

    [ $? -ne 0 ] || [ -z "$CHOICE" ] && return
    CHOICE="${CHOICE//|/}"
    $CHOICE
}

#========================================================================
# POINT D'ENTRÉE PRINCIPAL
#========================================================================

if [ -z "$1" ]; then
    show_menu
else
    $1
fi
