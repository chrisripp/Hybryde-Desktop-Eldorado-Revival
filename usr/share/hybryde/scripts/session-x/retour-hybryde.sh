#!/bin/bash
#========================================================================
# retour-hybryde.sh — Retour vers Hybryde depuis n'importe quel DE
# Interface 100% YAD
#
# Pose le flag FLAG_RETURN pour que hybryde-session.sh relance Hybryde,
# puis tue proprement le DE actif.
# La session X reste vivante car hybryde-session.sh continue de tourner.
#========================================================================

FLAG_RETURN="/tmp/hybryde-return-flag"

YAD_COMMON=(
    --center
    --borders=14
    --window-icon="go-home"
    --image="/usr/share/hybryde/logos/hybryde-xs.png"
    --title="Retour à Hybryde"
)

#========================================================================
# DÉTECTION DU DE ACTIF
#========================================================================

detect_de() {
    if   pidof enlightenment     >/dev/null 2>&1; then echo "enlightenment"
    elif pidof xfce4-session     >/dev/null 2>&1; then echo "xfce"
    elif pidof ksmserver         >/dev/null 2>&1; then echo "kde"
    elif pidof lxsession         >/dev/null 2>&1; then echo "lxde"
    elif pidof mate-session      >/dev/null 2>&1; then echo "mate"
    elif pgrep -x cinnamon-sessio >/dev/null 2>&1; then echo "cinnamon"
    elif pidof gnome-flashback   >/dev/null 2>&1; then echo "gnome"
    elif pidof openbox           >/dev/null 2>&1; then echo "openbox"
    elif [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

#========================================================================
# CONFIRMATION — dialogue yad
#========================================================================

confirmer() {
    if ! command -v yad >/dev/null 2>&1; then
        # Fallback texte si yad absent
        echo "Retour à Hybryde ? (o/n)"
        read -r rep
        [[ "$rep" =~ ^[oOyY] ]] || exit 0
        return
    fi

    local de
    de=$(detect_de)
    local de_label="${de^^}"  # majuscules pour l'affichage

    yad "${YAD_COMMON[@]}" \
        --image="go-home" \
        --text="<big><b>Retour à Hybryde</b></big>\n\nEnvironnement détecté : <b>${de_label}</b>\n\nVoulez-vous quitter <b>${de_label}</b> et revenir à la session Hybryde ?" \
        --button="Annuler:1" \
        --button="Oui, retourner:0" \
        --width=380 \
        || exit 0
}

#========================================================================
# ARRÊT DU DE ACTIF
#========================================================================

tuer_de() {
    local de="$1"
    echo "[retour-hybryde] Arrêt du DE : $de"

    case "$de" in
        enlightenment*)
            enlightenment_remote -exit 2>/dev/null
            sleep 1
            for p in enlightenment enlightenment_start efreetd; do
                killall "$p" 2>/dev/null
            done ;;

        xfce*)
            for p in xfce4-session xfwm4 xfdesktop xfce4-panel xfsettingsd xfconfd; do
                killall "$p" 2>/dev/null
            done ;;

        kde*|plasma*)
            for p in ksmserver kwin_x11 kwin plasmashell; do
                killall "$p" 2>/dev/null
            done ;;

        lxde*|lxqt*)
            for p in lxsession lxpanel pcmanfm openbox; do
                killall "$p" 2>/dev/null
            done ;;

        mate*)
            for p in mate-session marco mate-panel; do
                killall "$p" 2>/dev/null
            done ;;

        cinnamon*)
            cinnamon-session-quit --logout --no-prompt 2>/dev/null
            sleep 2
            for p in cinnamon-session-binary cinnamon-session cinnamon muffin nemo; do
                killall "$p" 2>/dev/null
            done ;;

        gnome*|ubuntu*)
            gnome-session-quit --no-prompt 2>/dev/null
            sleep 2
            for p in gnome-flashback gnome-session-ctl gnome-session-service \
                     gnome-session-init-worker gnome-shell mutter gnome-panel metacity; do
                killall "$p" 2>/dev/null
            done ;;

        openbox*)
            # Tuer l'agent polkit lancé par Openbox AVANT de revenir à Hybryde
            killall xfce-polkit                     polkit-mate-authentication-agent-1                     polkit-gnome-authentication-agent-1 2>/dev/null
            # Attendre sa mort effective (évite le doublon dans autostart.sh)
            local polkit_die=0
            while { pgrep -x xfce-polkit > /dev/null 2>&1 || \
                    pgrep -f "polkit-mate-authentication-agent" > /dev/null 2>&1 || \
                    pgrep -f "polkit-gnome-authentication-agent" > /dev/null 2>&1; } && \
                  [ $polkit_die -lt 5 ]; do
                sleep 1
                polkit_die=$((polkit_die + 1))
            done
            killall openbox lxpanel dunst 2>/dev/null
            # Restaurer le fond d'écran Hybryde
            if [ -f ~/.fehbg-hybryde ]; then
                cp ~/.fehbg-hybryde ~/.fehbg
                ~/.fehbg &
            fi ;;
    esac

    killall nautilus 2>/dev/null
}

#========================================================================
# POINT D'ENTRÉE
#========================================================================

confirmer

# Vérifier que le wrapper de session tourne bien
if ! pgrep -f "hybryde-session.sh" >/dev/null 2>&1; then
    if command -v yad >/dev/null 2>&1; then
        yad "${YAD_COMMON[@]}" \
            --image="dialog-error" \
            --text="<b>Erreur : hybryde-session.sh ne tourne pas.</b>\n\nVérifiez que le fichier <tt>.desktop</tt> LightDM\npointe bien vers ce script." \
            --button="OK:0" \
            --width=420
    else
        echo "ERREUR : hybryde-session.sh ne tourne pas." >&2
    fi
    exit 1
fi

DE=$(detect_de)

# Poser le flag AVANT de tuer le DE
# hybryde-session.sh le détectera et relancera Hybryde
touch "$FLAG_RETURN"

tuer_de "$DE"
