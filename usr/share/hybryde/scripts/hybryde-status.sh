#!/bin/bash

#========================================================================
# hybryde-status.sh — Diagnostic rapide de la session Hybryde
# Usage : terminal, Cairo-Dock launcher, ou appelé par d'autres scripts
# Modes : --text (défaut), --zenity (fenêtre popup), --json
#========================================================================

SWITCHING_FLAG="/tmp/hybryde-switching"
RETURN_FLAG="/tmp/hybryde-return-flag"
PID_FILE="/tmp/hybryde-pid.txt"

#========================================================================
# FONCTIONS DE VÉRIFICATION
#========================================================================

check_process() {
    local name="$1"
    local label="${2:-$1}"
    if pgrep -x "$name" > /dev/null 2>&1; then
        echo "ok:$label"
    else
        echo "ko:$label"
    fi
}

check_process_f() {
    # pgrep -f pour les processus dont le nom dépasse 15 chars
    local pattern="$1"
    local label="$2"
    if pgrep -f "$pattern" > /dev/null 2>&1; then
        echo "ok:$label"
    else
        echo "ko:$label"
    fi
}

cairo_count() {
    pgrep -x cairo-dock | wc -l
}

detect_active_de() {
    if   pgrep -x "xfce4-session"       > /dev/null 2>&1; then echo "XFCE"
    elif pgrep -x "plasmashell"          > /dev/null 2>&1; then echo "KDE Plasma"
    elif pgrep -x "mate-session"         > /dev/null 2>&1; then echo "MATE"
    elif pgrep -f "cinnamon-session"     > /dev/null 2>&1; then echo "Cinnamon"
    elif pgrep -x "gnome-flashback"      > /dev/null 2>&1; then echo "GNOME"
    elif pgrep -x "lxsession"            > /dev/null 2>&1; then echo "LXDE"
    elif pgrep -x "lxqt-session"         > /dev/null 2>&1; then echo "LXQt"
    elif pgrep -x "enlightenment"        > /dev/null 2>&1; then echo "Enlightenment"
    elif pgrep -x "openbox"              > /dev/null 2>&1; then echo "Hybryde (Openbox)"
    else echo "Inconnu"
    fi
}

check_switching() {
    if [ -f "$SWITCHING_FLAG" ]; then
        echo "OUI ⚠️"
    else
        echo "non"
    fi
}

check_return_flag() {
    if [ -f "$RETURN_FLAG" ]; then
        echo "présent ⚠️"
    else
        echo "absent"
    fi
}

check_keyring() {
    if pgrep -x "gnome-keyring-d" > /dev/null 2>&1; then
        echo "ok:keyring"
    else
        echo "ko:keyring"
    fi
}

check_audio() {
    if pactl info > /dev/null 2>&1; then
        local server
        server=$(pactl info 2>/dev/null | grep "Nom du serveur\|Server Name" | cut -d: -f2- | xargs)
        echo "ok:audio ($server)"
    else
        echo "ko:audio"
    fi
}

#========================================================================
# COLLECTE DES DONNÉES
#========================================================================

collect() {
    WM=""
    for wm in openbox metacity marco; do
        if pgrep -x "$wm" > /dev/null 2>&1; then
            WM="$wm"
            break
        fi
    done

    CAIRO=$(cairo_count)
    DE=$(detect_active_de)
    SWITCHING=$(check_switching)
    RETURN_F=$(check_return_flag)

    # Composants core
    R_SESSION=$(check_process_f "hybryde-session" "session-wrapper")
    R_PICOM=$(check_process "picom" "picom")
    R_NM=$(check_process "nm-applet" "nm-applet")
    R_DUNST=$(check_process "dunst" "dunst")
    R_LOCKER=$(check_process "light-locker" "light-locker")
    R_KEYRING=$(check_keyring)
    R_AUDIO=$(check_audio)
    R_PASYS=$(check_process "pasystray" "pasystray")
    R_POLKIT=""
    if pgrep -x "xfce-polkit" > /dev/null 2>&1; then
        R_POLKIT="ok:polkit (xfce)"
    elif pgrep -f "polkit-mate" > /dev/null 2>&1; then
        R_POLKIT="ok:polkit (mate)"
    else
        R_POLKIT="ko:polkit"
    fi
}

#========================================================================
# FORMATAGE — MODE TEXTE
#========================================================================

fmt_status() {
    local result="$1"
    local label="${result#*:}"
    local state="${result%%:*}"
    if [ "$state" = "ok" ]; then
        printf "  \033[32m✓\033[0m %-22s\n" "$label"
    else
        printf "  \033[31m✗\033[0m %-22s  ← absent\n" "$label"
    fi
}

output_text() {
    collect

    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║         HYBRYDE — État de la session         ║"
    echo "╠══════════════════════════════════════════════╣"
    printf "║  DE actif    : %-29s ║\n" "$DE"
    printf "║  WM          : %-29s ║\n" "${WM:-aucun}"
    printf "║  Cairo-Dock  : %-29s ║\n" "$CAIRO instance(s)"
    printf "║  Switch       : %-29s ║\n" "$SWITCHING"
    printf "║  Flag retour  : %-29s ║\n" "$RETURN_F"
    echo "╠══════════════════════════════════════════════╣"
    echo "║  Composants                                  ║"
    echo "╚══════════════════════════════════════════════╝"

    fmt_status "$R_SESSION"
    fmt_status "$R_PICOM"
    fmt_status "$R_NM"
    fmt_status "$R_DUNST"
    fmt_status "$R_LOCKER"
    fmt_status "$R_KEYRING"
    fmt_status "$R_AUDIO"
    fmt_status "$R_PASYS"
    fmt_status "$R_POLKIT"

    echo ""
    echo "  Flags   : $SWITCHING_FLAG → $SWITCHING"
    echo "  PID file: $PID_FILE → $([ -f "$PID_FILE" ] && echo "présent ($(wc -l < "$PID_FILE") PIDs)" || echo "absent")"
    echo "  Log     : /tmp/hybryde-session.log"
    echo ""
}

#========================================================================
# FORMATAGE — MODE ZENITY (popup)
#========================================================================

status_icon() {
    [ "${1%%:*}" = "ok" ] && echo "✓" || echo "✗"
}

status_label() {
    echo "${1#*:}"
}

output_zenity() {
    collect

    local msg
    msg="<b>DE actif :</b> $DE\n"
    msg+="<b>WM :</b> ${WM:-aucun}    <b>Cairo-Dock :</b> $CAIRO instance(s)\n"
    msg+="<b>Switch en cours :</b> $SWITCHING\n\n"
    msg+="<b>Composants :</b>\n"

    for r in "$R_SESSION" "$R_PICOM" "$R_NM" "$R_DUNST" \
             "$R_LOCKER" "$R_KEYRING" "$R_AUDIO" "$R_PASYS" "$R_POLKIT"; do
        local icon
        icon=$(status_icon "$r")
        local lbl
        lbl=$(status_label "$r")
        msg+="  $icon  $lbl\n"
    done

    msg+="\n<small>Log : /tmp/hybryde-session.log</small>"

    yad --info \
        --center \
        --borders=12 \
        --title="Hybryde — État de la session" \
        --window-icon="utilities-system-monitor" \
        --text="$msg" \
        --button="OK:0" \
        --width=440 --height=340 \
        --no-wrap
}

#========================================================================
# FORMATAGE — MODE JSON (pour scripts externes)
#========================================================================

output_json() {
    collect

    local wm_ok=false
    [ -n "$WM" ] && wm_ok=true

    cat <<EOF
{
  "de": "$DE",
  "wm": "${WM:-null}",
  "cairo_dock_instances": $CAIRO,
  "switching": $([ "$SWITCHING" = "non" ] && echo false || echo true),
  "components": {
    "session_wrapper": $([ "${R_SESSION%%:*}" = "ok" ] && echo true || echo false),
    "picom":           $([ "${R_PICOM%%:*}"   = "ok" ] && echo true || echo false),
    "nm_applet":       $([ "${R_NM%%:*}"      = "ok" ] && echo true || echo false),
    "dunst":           $([ "${R_DUNST%%:*}"   = "ok" ] && echo true || echo false),
    "light_locker":    $([ "${R_LOCKER%%:*}"  = "ok" ] && echo true || echo false),
    "keyring":         $([ "${R_KEYRING%%:*}" = "ok" ] && echo true || echo false),
    "pasystray":       $([ "${R_PASYS%%:*}"   = "ok" ] && echo true || echo false),
    "polkit":          $([ "${R_POLKIT%%:*}"  = "ok" ] && echo true || echo false)
  }
}
EOF
}

#========================================================================
# POINT D'ENTRÉE
#========================================================================

case "${1:-}" in
    --zenity|-z)  output_zenity ;;
    --json|-j)    output_json   ;;
    --text|-t|"") output_text   ;;
    *)
        echo "Usage: $0 [--text | --zenity | --json]"
        echo "  --text    Sortie terminal (défaut)"
        echo "  --zenity  Fenêtre popup GTK"
        echo "  --json    Sortie JSON pour scripts"
        exit 1
        ;;
esac
