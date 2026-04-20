#!/bin/bash

#========================================================================
# hybryde-config.sh — Configuration graphique de la session Hybryde
# Interface 100% YAD (Yet Another Dialog)
# Prérequis : yad, feh, picom
#========================================================================

CONF_DIR="$HOME/.config/hybryde"
CONF_FILE="$CONF_DIR/session.conf"
GTK_CONF="$CONF_DIR/gtk-settings.conf"

mkdir -p "$CONF_DIR"

# Charger la conf existante
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
fi

# Valeurs par défaut
COMPOSITOR_ENABLED="${COMPOSITOR_ENABLED:-true}"
POLKIT_AGENT="${POLKIT_AGENT:-auto}"
WALLPAPER_PATH="${WALLPAPER_PATH:-}"
WALLPAPER_MODE="${WALLPAPER_MODE:-fill}"

# Vérifier yad
if ! command -v yad &> /dev/null; then
    echo "✗ yad est requis : sudo apt install yad"
    exit 1
fi

#========================================================================
# STYLE COMMUN
#========================================================================

YAD_COMMON=(
    --center
    --borders=12
    --window-icon="preferences-system"
)

YAD_TITLE="Hybryde — Configuration"

#========================================================================
# FONCTIONS UTILITAIRES
#========================================================================

save_conf() {
    cat > "$CONF_FILE" <<EOF
# Hybryde session config — généré par hybryde-config.sh
COMPOSITOR_ENABLED=$COMPOSITOR_ENABLED
POLKIT_AGENT=$POLKIT_AGENT
WALLPAPER_PATH=$WALLPAPER_PATH
WALLPAPER_MODE=$WALLPAPER_MODE
EOF
}

save_gtk_conf() {
    local gtk_theme icon_theme cursor_theme font_name
    gtk_theme=$(gsettings   get org.gnome.desktop.interface gtk-theme    2>/dev/null | tr -d "'")
    icon_theme=$(gsettings  get org.gnome.desktop.interface icon-theme   2>/dev/null | tr -d "'")
    cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
    font_name=$(gsettings   get org.gnome.desktop.interface font-name    2>/dev/null | tr -d "'")
    {
        echo "HYB_GTK_THEME=$gtk_theme"
        echo "HYB_ICON_THEME=$icon_theme"
        echo "HYB_CURSOR_THEME=$cursor_theme"
        echo "HYB_FONT_NAME=$font_name"
    } > "$GTK_CONF"
}

notify_send() {
    local msg="$1"
    command -v notify-send &>/dev/null && \
        notify-send "Hybryde Config" "$msg" --icon=preferences-system 2>/dev/null
}

yad_info() {
    yad "${YAD_COMMON[@]}" \
        --title="$YAD_TITLE" \
        --image="dialog-information" \
        --text="$1" \
        --button="OK:0" \
        --width=320
}

yad_error() {
    yad "${YAD_COMMON[@]}" \
        --title="Erreur" \
        --image="dialog-error" \
        --text="$1" \
        --button="OK:0" \
        --width=320
}

# Trouve une icône représentative d'un thème
find_theme_icon() {
    local theme_dir="$1"
    local names=("folder" "applications-system" "preferences-system"
                 "user-home" "computer" "application-x-executable")
    local sizes=("48x48" "32x32" "64x64" "scalable")
    local cats=("places" "apps" "devices")

    for size in "${sizes[@]}"; do
        for cat in "${cats[@]}"; do
            for name in "${names[@]}"; do
                for ext in png svg; do
                    local p="$theme_dir/$size/$cat/$name.$ext"
                    [ -f "$p" ] && echo "$p" && return
                done
            done
        done
    done
    find "$theme_dir" -name "*.png" -size +1k 2>/dev/null | head -1
}

# Collecte des icônes pour la mosaïque d'aperçu
collect_theme_icons() {
    local theme_dir="$1"
    local max="${2:-32}"
    local found=()

    for size in 48x48 32x32 64x64; do
        for cat in apps places devices; do
            local dir="$theme_dir/$size/$cat"
            [ -d "$dir" ] || continue
            while IFS= read -r -d '' f; do
                found+=("$f")
                [ "${#found[@]}" -ge "$max" ] && break 3
            done < <(find "$dir" -name "*.png" -size +500c -print0 2>/dev/null)
        done
    done
    echo "${found[@]}"
}

#========================================================================
# FOND D'ÉCRAN — sélecteur avec aperçu intégré yad
#========================================================================

config_wallpaper() {
    local new_wp
    new_wp=$(yad "${YAD_COMMON[@]}" \
        --title="Choisir un fond d'écran" \
        --file \
        --filename="${WALLPAPER_PATH:-$HOME/}" \
        --file-filter="Images (jpg png bmp webp) | *.jpg *.jpeg *.png *.bmp *.webp" \
        --add-preview \
        --width=960 --height=620 \
        --button="Annuler:1" \
        --button="Choisir:0")

    [ $? -ne 0 ] || [ -z "$new_wp" ] && return
    [ ! -f "$new_wp" ] && yad_error "Fichier introuvable." && return

    # Choix du mode d'affichage
    local mode
    mode=$(yad "${YAD_COMMON[@]}" \
        --title="Mode d'affichage" \
        --list \
        --text="Choisissez le mode d'affichage pour :\n<b>$(basename "$new_wp")</b>" \
        --column="Mode" \
        --column="Description" \
        "fill"   "Remplir (peut rogner les bords)" \
        "center" "Centré (bandes noires si nécessaire)" \
        "max"    "Maximiser sans rogner" \
        "scale"  "Étirer (peut déformer)" \
        "tile"   "Mosaïque" \
        --print-column=1 \
        --separator="" \
        --width=440 --height=300 \
        --button="Annuler:1" \
        --button="Appliquer:0")

    [ $? -ne 0 ] || [ -z "$mode" ] && return
    mode="${mode//|/}"

    WALLPAPER_PATH="$new_wp"
    WALLPAPER_MODE="$mode"

    if command -v feh &>/dev/null; then
        feh "--bg-${mode}" "$new_wp"
        cp ~/.fehbg ~/.fehbg-hybryde 2>/dev/null
    elif command -v nitrogen &>/dev/null; then
        nitrogen "--set-${mode}" "$new_wp"
    else
        yad_error "Ni feh ni nitrogen n'est installé.\n<b>sudo apt install feh</b>"
        return
    fi

    save_conf
    notify_send "Fond d'écran mis à jour"
    yad_info "✓ Fond d'écran appliqué."
}

#========================================================================
# THÈME D'ICÔNES — liste avec aperçu icône représentative par thème
#========================================================================

config_icon_theme() {
    local themes=()
    local theme_dirs=()

    for d in /usr/share/icons/*/; do
        [ -f "$d/index.theme" ] || continue
        find "$d" \( -name "*.png" -o -name "*.svg" \) 2>/dev/null | grep -q . || continue
        themes+=("$(basename "$d")")
        theme_dirs+=("$d")
    done

    [ "${#themes[@]}" -eq 0 ] && yad_error "Aucun thème d'icônes trouvé." && return

    local current_icon
    current_icon=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")

    # Construire les lignes yad : icône représentative + nom
    local yad_rows=()
    for i in "${!themes[@]}"; do
        local icon
        icon=$(find_theme_icon "${theme_dirs[$i]}")
        [ -z "$icon" ] && icon="applications-other"
        yad_rows+=("$icon" "${themes[$i]}")
    done

    local selected
    selected=$(yad "${YAD_COMMON[@]}" \
        --title="Thème d'icônes" \
        --list \
        --text="Thème actuel : <b>${current_icon:-?}</b>\n\nChoisissez un thème d'icônes :" \
        --column="Aperçu:IMG" \
        --column="Thème" \
        "${yad_rows[@]}" \
        --print-column=2 \
        --separator="" \
        --width=560 --height=600 \
        --button="Annuler:1" \
        --button="Aperçu mosaïque:2" \
        --button="Appliquer:0")

    local ret=$?

    # Bouton Aperçu mosaïque (code 2)
    if [ $ret -eq 2 ]; then
        local sel_preview
        sel_preview="${selected//|/}"
        if [ -n "$sel_preview" ]; then
            _preview_icon_mosaic "$sel_preview"
        else
            yad_info "Sélectionnez d'abord un thème dans la liste."
        fi
        config_icon_theme
        return
    fi

    [ $ret -ne 0 ] || [ -z "$selected" ] && return
    selected="${selected//|/}"

    # Appliquer le thème
    gsettings set org.gnome.desktop.interface icon-theme "$selected"

    # Mettre à jour le cache d'icônes
    command -v gtk-update-icon-cache &>/dev/null && \
        gtk-update-icon-cache -f -t "/usr/share/icons/$selected" 2>/dev/null

    # Signal au settings daemon pour forcer le rechargement
    local cur_gtk
    cur_gtk=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    gsettings set org.gnome.desktop.interface gtk-theme "$cur_gtk" 2>/dev/null

    save_gtk_conf
    notify_send "Thème d'icônes : $selected"
    yad_info "✓ Thème d'icônes appliqué : <b>$selected</b>"
}

# Mosaïque feh pour prévisualiser un thème d'icônes
_preview_icon_mosaic() {
    local theme_name="$1"
    local theme_dir="/usr/share/icons/$theme_name"
    [ -d "$theme_dir" ] || return

    if ! command -v feh &>/dev/null; then
        yad_info "feh est requis pour l'aperçu mosaïque.\n<b>sudo apt install feh</b>"
        return
    fi

    local icons=()
    read -ra icons <<< "$(collect_theme_icons "$theme_dir" 32)"

    if [ "${#icons[@]}" -eq 0 ]; then
        yad_info "Aucune icône PNG trouvée pour ce thème."
        return
    fi

    feh --title "Aperçu : $theme_name" \
        --geometry 720x500 \
        --montage \
        --thumb-width 48 --thumb-height 48 \
        --limit-width 700 \
        --bg "#1e1e2e" \
        "${icons[@]}" &
    local feh_pid=$!

    yad "${YAD_COMMON[@]}" \
        --title="Aperçu : $theme_name" \
        --image="applications-other" \
        --text="Aperçu du thème <b>$theme_name</b>\n\nFermez cette fenêtre pour revenir à la sélection." \
        --button="Fermer:0" \
        --width=360

    kill "$feh_pid" 2>/dev/null
}

#========================================================================
# THÈME GTK
#========================================================================

config_gtk_theme() {
    local themes=()
    for d in /usr/share/themes/*/; do
        local name; name=$(basename "$d")
        { [ -d "$d/gtk-3.0" ] || [ -d "$d/gtk-2.0" ]; } && themes+=("$name")
    done
    if [ -d "$HOME/.themes" ]; then
        for d in "$HOME/.themes/"/*/; do
            local name; name=$(basename "$d")
            { [ -d "$d/gtk-3.0" ] || [ -d "$d/gtk-2.0" ]; } && themes+=("$name")
        done
    fi

    [ "${#themes[@]}" -eq 0 ] && yad_error "Aucun thème GTK trouvé." && return

    local current_gtk
    current_gtk=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")

    local selected
    selected=$(yad "${YAD_COMMON[@]}" \
        --title="Thème GTK" \
        --list \
        --text="Thème actuel : <b>${current_gtk:-?}</b>\n\nChoisissez un thème GTK :" \
        --column="Thème" \
        "${themes[@]}" \
        --print-column=1 \
        --separator="" \
        --width=440 --height=540 \
        --button="Annuler:1" \
        --button="Appliquer:0")

    [ $? -ne 0 ] || [ -z "$selected" ] && return
    selected="${selected//|/}"

    gsettings set org.gnome.desktop.interface gtk-theme "$selected"
    save_gtk_conf
    notify_send "Thème GTK : $selected"
    yad_info "✓ Thème GTK appliqué : <b>$selected</b>"
}

#========================================================================
# COMPOSITEUR PICOM
#========================================================================

config_compositor() {
    local current_state
    pgrep -x "picom" > /dev/null 2>&1 \
        && current_state="🟢 actif" \
        || current_state="🔴 inactif"

    local choice
    choice=$(yad "${YAD_COMMON[@]}" \
        --title="Compositeur Picom" \
        --list \
        --text="Compositeur actuellement : <b>$current_state</b>\n\n<small>Backend xrender obligatoire sous VirtualBox</small>" \
        --column="Action" \
        --column="Description" \
        "Activer"    "Lance picom --backend xrender --no-vsync" \
        "Désactiver" "Tue picom (pas de transparence ni ombres)" \
        "Redémarrer" "Relance picom (utile si plantage)" \
        --print-column=1 \
        --separator="" \
        --width=460 --height=280 \
        --button="Annuler:1" \
        --button="OK:0")

    [ $? -ne 0 ] || [ -z "$choice" ] && return
    choice="${choice//|/}"

    case "$choice" in
        "Activer")
            if pgrep -x "picom" > /dev/null 2>&1; then
                yad_info "Picom est déjà actif."
            else
                picom --backend xrender --no-vsync -b
                sleep 1
                if pgrep -x "picom" > /dev/null 2>&1; then
                    COMPOSITOR_ENABLED=true; save_conf
                    notify_send "Compositeur activé"
                    yad_info "✓ Picom démarré."
                else
                    yad_error "Picom n'a pas démarré.\nConsultez : /tmp/hybryde-session.log"
                fi
            fi ;;
        "Désactiver")
            killall picom 2>/dev/null
            COMPOSITOR_ENABLED=false; save_conf
            notify_send "Compositeur désactivé"
            yad_info "✓ Picom arrêté." ;;
        "Redémarrer")
            killall picom 2>/dev/null; sleep 1
            picom --backend xrender --no-vsync -b; sleep 1
            if pgrep -x "picom" > /dev/null 2>&1; then
                notify_send "Compositeur redémarré"
                yad_info "✓ Picom redémarré."
            else
                yad_error "Picom n'a pas redémarré."
            fi ;;
    esac
}

#========================================================================
# AGENT POLKIT
#========================================================================

config_polkit() {
    local current="aucun"
    pgrep -x "xfce-polkit" > /dev/null 2>&1 && current="xfce-polkit"
    pgrep -f "polkit-mate"  > /dev/null 2>&1 && current="polkit-mate"

    local choice
    choice=$(yad "${YAD_COMMON[@]}" \
        --title="Agent PolicyKit" \
        --list \
        --text="Agent actif : <b>$current</b>\n\nL'agent polkit gère les demandes d'authentification\n(sudo graphique, montage de disques, etc.)" \
        --column="Agent" \
        --column="Description" \
        "auto"        "Détection automatique au démarrage" \
        "xfce-polkit" "xfce-polkit  (GTK, léger)" \
        "polkit-mate" "polkit-mate  (GTK, MATE)" \
        "Redémarrer"  "Relancer l'agent actuel" \
        --print-column=1 \
        --separator="" \
        --width=480 --height=300 \
        --button="Annuler:1" \
        --button="OK:0")

    [ $? -ne 0 ] || [ -z "$choice" ] && return
    choice="${choice//|/}"

    if [ "$choice" = "Redémarrer" ]; then
        killall xfce-polkit polkit-mate-authentication-agent-1 2>/dev/null
        sleep 0.5
        if   [ "$current" = "xfce-polkit" ] && [ -x /usr/libexec/xfce-polkit ]; then
            /usr/libexec/xfce-polkit &
        elif [ "$current" = "polkit-mate"  ] && [ -x /usr/libexec/polkit-mate-authentication-agent-1 ]; then
            /usr/libexec/polkit-mate-authentication-agent-1 &
        fi
        notify_send "Agent polkit redémarré"
        return
    fi

    POLKIT_AGENT="$choice"; save_conf

    if [ "$choice" != "auto" ]; then
        killall xfce-polkit polkit-mate-authentication-agent-1 2>/dev/null
        sleep 0.5
        case "$choice" in
            "xfce-polkit")
                if [ -x /usr/libexec/xfce-polkit ]; then
                    /usr/libexec/xfce-polkit &
                    notify_send "Agent polkit : xfce-polkit"
                else
                    yad_error "xfce-polkit absent.\n<b>sudo apt install xfce-polkit</b>"
                fi ;;
            "polkit-mate")
                if [ -x /usr/libexec/polkit-mate-authentication-agent-1 ]; then
                    /usr/libexec/polkit-mate-authentication-agent-1 &
                    notify_send "Agent polkit : polkit-mate"
                else
                    yad_error "polkit-mate absent.\n<b>sudo apt install mate-polkit</b>"
                fi ;;
        esac
    fi
}

#========================================================================
# MENU PRINCIPAL — avec icônes système et état en temps réel
#========================================================================

show_menu() {
    while true; do
        # Lire l'état en temps réel
        local wp_short="${WALLPAPER_PATH##*/}"
        [ -z "$wp_short" ] && wp_short="non défini"

        local comp_state
        pgrep -x picom > /dev/null 2>&1 \
            && comp_state="🟢 actif" \
            || comp_state="🔴 inactif"

        local polkit_state="auto"
        pgrep -x "xfce-polkit" > /dev/null 2>&1 && polkit_state="xfce-polkit"
        pgrep -f "polkit-mate"  > /dev/null 2>&1 && polkit_state="polkit-mate"

        local cur_icon cur_gtk
        cur_icon=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
        cur_gtk=$(gsettings  get org.gnome.desktop.interface gtk-theme  2>/dev/null | tr -d "'")

        local choice
        choice=$(yad \
            --center \
            --borders=16 \
            --title="$YAD_TITLE" \
            --window-icon="preferences-system" \
            --list \
            --text="<big><b>⚙  Hybryde — Configuration</b></big>\n\nSélectionnez une section à configurer :" \
            --column="Icône:IMG" \
            --column="Section" \
            --column="État actuel" \
            "image-x-generic"            "🖼  Fond d'écran"    "$wp_short  ($WALLPAPER_MODE)" \
            "applications-other"         "🎨 Thèmes d'icônes"  "${cur_icon:-?}" \
            "preferences-desktop-theme"  "🖌  Thème GTK"        "${cur_gtk:-?}" \
            "preferences-system"         "✨ Compositeur"       "$comp_state" \
            "dialog-password"            "🔐 Agent Polkit"      "$polkit_state" \
            "utilities-system-monitor"   "📊 État session"      "Diagnostic" \
            --print-column=2 \
            --separator="" \
            --width=640 --height=420 \
            --button="Fermer:1" \
            --button="Ouvrir:0")

        [ $? -ne 0 ] && break

        choice="${choice//|/}"

        case "$choice" in
            *"Fond d'écran"*)   config_wallpaper   ;;
            *"icônes"*)         config_icon_theme  ;;
            *"GTK"*)            config_gtk_theme   ;;
            *"Compositeur"*)    config_compositor  ;;
            *"Polkit"*)         config_polkit      ;;
            *"session"*)
                local status_bin="/usr/share/hybryde/scripts/session-x/hybryde-status.sh"
                if [ -x "$status_bin" ]; then
                    "$status_bin" --zenity &
                else
                    yad_info "hybryde-status.sh introuvable."
                fi ;;
            *) break ;;
        esac
    done
}

#========================================================================
# POINT D'ENTRÉE
#========================================================================

case "${1:-}" in
    wallpaper)        config_wallpaper  ;;
    icons|icon)       config_icon_theme ;;
    gtk|theme)        config_gtk_theme  ;;
    compositor|picom) config_compositor ;;
    polkit)           config_polkit     ;;
    "")               show_menu         ;;
    *)
        echo "Usage: $0 [wallpaper | icons | gtk | compositor | polkit]"
        echo "  Sans argument : menu graphique complet"
        exit 1 ;;
esac
