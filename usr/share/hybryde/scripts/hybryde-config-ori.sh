#!/bin/bash

#========================================================================
# hybryde-config.sh — Configuration graphique de la session Hybryde
# Interface zenity/yad pour : fond d'écran, icônes, compositeur, polkit
# Prérequis : zenity, feh ou nitrogen, picom
#========================================================================

CONF_DIR="$HOME/.config/hybryde"
CONF_FILE="$CONF_DIR/session.conf"
GTK_CONF="$CONF_DIR/gtk-settings.conf"
AUTOSTART="$HOME/.hybryde/autostart/autostart.sh"

mkdir -p "$CONF_DIR"

# Charger la conf existante
if [ -f "$CONF_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi

# Valeurs par défaut
COMPOSITOR_ENABLED="${COMPOSITOR_ENABLED:-true}"
POLKIT_AGENT="${POLKIT_AGENT:-auto}"
WALLPAPER_PATH="${WALLPAPER_PATH:-}"
WALLPAPER_MODE="${WALLPAPER_MODE:-fill}"

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
    echo "✓ Configuration sauvegardée dans $CONF_FILE"
}

save_gtk_conf() {
    local gtk_theme icon_theme cursor_theme font_name
    gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme    2>/dev/null | tr -d "'")
    icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme  2>/dev/null | tr -d "'")
    cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
    font_name=$(gsettings get org.gnome.desktop.interface font-name    2>/dev/null | tr -d "'")
    {
        echo "HYB_GTK_THEME=$gtk_theme"
        echo "HYB_ICON_THEME=$icon_theme"
        echo "HYB_CURSOR_THEME=$cursor_theme"
        echo "HYB_FONT_NAME=$font_name"
    } > "$GTK_CONF"
    echo "✓ Thèmes GTK sauvegardés dans $GTK_CONF"
}

notify() {
    local msg="$1"
    if command -v notify-send &> /dev/null; then
        notify-send "Hybryde Config" "$msg" --icon=preferences-system
    fi
}

# Trouve l'icône représentative d'un thème (dossier ou apps-system)
find_theme_icon() {
    local theme_dir="$1"
    local icon_names=("folder" "applications-system" "preferences-system" "user-home" "computer")
    local sizes=("48x48" "32x32" "64x64" "128x128" "scalable")
    local cats=("places" "apps" "devices")

    for size in "${sizes[@]}"; do
        for cat in "${cats[@]}"; do
            for name in "${icon_names[@]}"; do
                for ext in png svg; do
                    local p="$theme_dir/$size/$cat/$name.$ext"
                    [ -f "$p" ] && echo "$p" && return
                done
            done
        done
    done

    # Fallback : premier PNG trouvé dans le thème
    find "$theme_dir" -name "*.png" -size +1k 2>/dev/null | head -1
}

# Collecte jusqu'à N icônes d'un thème pour la mosaïque de prévisualisation
collect_theme_icons() {
    local theme_dir="$1"
    local max="${2:-24}"
    local found=()

    for size in 128x128 64x64 48x48 scalable; do
        for cat in apps places devices actions status; do
            local dir="$theme_dir/$size/$cat"
            [ -d "$dir" ] || continue

            while IFS= read -r -d '' f; do
                found+=("$f")
                [ "${#found[@]}" -ge "$max" ] && break 3
            done < <(find "$dir" \
                \( -name "*.png" -o -name "*.svg" \) \
                -type f -print0 2>/dev/null)
        done
    done

    echo "${found[@]}"
}

#========================================================================
# FOND D'ÉCRAN — avec aperçu live via feh
#========================================================================

config_wallpaper() {
    # Choisir le fichier image
    local new_wp
    new_wp=$(zenity --file-selection \
        --title="Choisir un fond d'écran" \
        --filename="${WALLPAPER_PATH:-$HOME/}" \
        --file-filter="Images | *.jpg *.jpeg *.png *.bmp *.webp" \
        --width=900 --height=600)

    [ -z "$new_wp" ] && return
    [ ! -f "$new_wp" ] && zenity --error --text="Fichier introuvable." --width=250 && return

    # ── Aperçu live ──────────────────────────────────────────────────────
    local feh_pid=""
    if command -v feh &> /dev/null; then
        # Ouvrir une fenêtre feh de prévisualisation
        feh --title "Hybryde — Aperçu fond d'écran" \
            --geometry 900x540 \
            --scale-down \
            --zoom fill \
            "$new_wp" &
        feh_pid=$!
        sleep 0.4  # laisser le temps à feh de s'ouvrir
    fi

    # Choisir le mode d'affichage (feh reste ouvert pendant ce choix)
    local mode
    mode=$(zenity --list \
        --title="Mode d'affichage" \
        --text="$([ -n "$feh_pid" ] && echo "Aperçu ouvert — " )Choisissez le mode d'affichage :" \
        --column="Mode" --column="Description" \
        "fill"    "Remplir (peut rogner)" \
        "center"  "Centré (bandes si nécessaire)" \
        "max"     "Maximiser sans rogner" \
        "scale"   "Étirer (peut déformer)" \
        "tile"    "Mosaïque" \
        --width=420 --height=320)

    # Fermer la fenêtre d'aperçu
    [ -n "$feh_pid" ] && kill "$feh_pid" 2>/dev/null

    [ -z "$mode" ] && return

    WALLPAPER_PATH="$new_wp"
    WALLPAPER_MODE="$mode"

    # Appliquer immédiatement comme fond d'écran réel
    if command -v feh &> /dev/null; then
        feh "--bg-${mode}" "$new_wp"
        cp ~/.fehbg ~/.fehbg-hybryde 2>/dev/null
        echo "✓ Fond d'écran appliqué (feh, mode: $mode)"
    elif command -v nitrogen &> /dev/null; then
        nitrogen "--set-${mode}" "$new_wp"
        echo "✓ Fond d'écran appliqué (nitrogen)"
    else
        zenity --error --text="Ni feh ni nitrogen n'est installé.\nsudo apt install feh" --width=300
        return
    fi

    save_conf
    notify "Fond d'écran mis à jour"
    zenity --info --text="✓ Fond d'écran appliqué." --width=250
}

#========================================================================
# THÈME D'ICÔNES — avec aperçu mosaïque
#========================================================================

config_icon_theme() {
    # ── Construire la liste des thèmes disponibles ────────────────────
    local themes=()
    local theme_dirs=()

    for d in /usr/share/icons/*/; do
        [ -f "$d/index.theme" ] || continue
        local name
        name=$(basename "$d")

        # Ignorer les thèmes curseur-seulement (pas de sous-dossier apps/places)
        if ! find "$d" -name "*.png" -o -name "*.svg" 2>/dev/null | grep -q .; then
            continue
        fi

        themes+=("$name")
        theme_dirs+=("$d")
    done

    if [ "${#themes[@]}" -eq 0 ]; then
        zenity --error --text="Aucun thème d'icônes trouvé dans /usr/share/icons/" --width=300
        return
    fi

    local selected=""

    # ── Sélection avec yad (aperçu inline) si disponible ────────────
    if command -v yad &> /dev/null; then
        local yad_args=()
        for i in "${!themes[@]}"; do
            local icon
            icon=$(find_theme_icon "${theme_dirs[$i]}")
            [ -z "$icon" ] && icon="dialog-information"
            yad_args+=("$icon" "${themes[$i]}")
        done

        selected=$(yad --list \
            --title="Thème d'icônes" \
            --text="Choisissez un thème d'icônes :\n(double-clic pour sélectionner)" \
            --column="Aperçu:IMG" \
            --column="Thème" \
            "${yad_args[@]}" \
            --width=520 --height=550 \
            --print-column=2 \
            --separator="" \
            --button="Annuler:1" \
            --button="Aperçu:2" \
            --button="Appliquer:0" 2>/dev/null)
        local yad_ret=$?

        # Bouton Aperçu (code 2)
        if [ $yad_ret -eq 2 ] && [ -n "$selected" ]; then
            _preview_icon_theme "$selected"
            # Rouvrir yad après l'aperçu
            config_icon_theme
            return
        fi

        [ $yad_ret -ne 0 ] && return
        selected="${selected%|}"

    # ── Fallback : zenity + aperçu feh montage ───────────────────────
    else
        selected=$(zenity --list \
            --title="Thème d'icônes" \
            --text="Choisissez un thème d'icônes :" \
            --column="Thème" \
            "${themes[@]}" \
            --width=420 --height=500 \
            --print-column=1)

        [ -z "$selected" ] && return

        # Proposer un aperçu avant d'appliquer
        if command -v feh &> /dev/null; then
            zenity --question \
                --title="Aperçu" \
                --text="Voulez-vous voir un aperçu du thème <b>$selected</b> ?" \
                --ok-label="Voir l'aperçu" \
                --cancel-label="Appliquer directement" \
                --width=320
            if [ $? -eq 0 ]; then
                _preview_icon_theme "$selected"
                zenity --question \
                    --title="Appliquer ?" \
                    --text="Appliquer le thème <b>$selected</b> ?" \
                    --ok-label="Appliquer" \
                    --cancel-label="Annuler" \
                    --width=280 || return
            fi
        fi
    fi

    [ -z "$selected" ] && return

    # ── Appliquer ─────────────────────────────────────────────────────
    gsettings set org.gnome.desktop.interface icon-theme "$selected"

    # Rafraîchir le cache d'icônes (correction bug affichage)
    if command -v gtk-update-icon-cache &> /dev/null; then
        gtk-update-icon-cache -f -t "/usr/share/icons/$selected" 2>/dev/null
    fi

    # Forcer la prise en compte par le settings daemon
    # (toggle temporaire pour déclencher le signal de changement)
    local current_gtk
    current_gtk=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    gsettings set org.gnome.desktop.interface gtk-theme "$current_gtk" 2>/dev/null

    # Sauvegarder dans gtk-settings.conf
    save_gtk_conf

    notify "Thème d'icônes : $selected"
    zenity --info --text="✓ Thème d'icônes appliqué : <b>$selected</b>\n\nSi les icônes n'ont pas changé, déconnectez/reconnectez-vous." \
        --width=380
}

# Affiche une mosaïque d'aperçu d'un thème d'icônes via feh
_preview_icon_theme() {
    local theme_name="$1"
    local theme_dir="/usr/share/icons/$theme_name"

    [ -d "$theme_dir" ] || return

    # Collecter des icônes représentatives
    local icons=()
    read -ra icons <<< "$(collect_theme_icons "$theme_dir" 30)"

    if [ "${#icons[@]}" -eq 0 ]; then
        zenity --info --text="Impossible de trouver des icônes pour ce thème." --width=300
        return
    fi

    # Ouvrir une mosaïque feh — se ferme seul quand l'utilisateur appuie sur Q ou ferme
    feh --title "Aperçu thème : $theme_name" \
        --geometry 700x480 \
        --montage \
        --thumb-width 48 \
        --thumb-height 48 \
        --limit-width 680 \
        --bg "#2d2d2d" \
        --fontpath /usr/share/fonts \
        "${icons[@]}" &

    local feh_pid=$!

    zenity --info \
        --title="Aperçu : $theme_name" \
        --text="Aperçu du thème <b>$theme_name</b> ouvert.\n\nFermez la fenêtre d'aperçu ou cliquez OK pour continuer." \
        --width=320

    kill "$feh_pid" 2>/dev/null
}

#========================================================================
# THÈME GTK
#========================================================================

config_gtk_theme() {
    local themes=()

    for d in /usr/share/themes/*/; do
        local name
        name=$(basename "$d")
        { [ -d "$d/gtk-3.0" ] || [ -d "$d/gtk-2.0" ]; } && themes+=("$name")
    done
    if [ -d "$HOME/.themes" ]; then
        for d in "$HOME/.themes/"/*/; do
            local name
            name=$(basename "$d")
            { [ -d "$d/gtk-3.0" ] || [ -d "$d/gtk-2.0" ]; } && themes+=("$name")
        done
    fi

    if [ "${#themes[@]}" -eq 0 ]; then
        zenity --error --text="Aucun thème GTK trouvé." --width=250
        return
    fi

    local current
    current=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")

    local selected
    selected=$(zenity --list \
        --title="Thème GTK" \
        --text="Thème actuel : <b>$current</b>\nChoisissez un thème GTK :" \
        --column="Thème" \
        "${themes[@]}" \
        --width=420 --height=500)

    [ -z "$selected" ] && return

    gsettings set org.gnome.desktop.interface gtk-theme "$selected"
    save_gtk_conf
    notify "Thème GTK : $selected"
    zenity --info --text="✓ Thème GTK appliqué : $selected" --width=300
}

#========================================================================
# COMPOSITEUR
#========================================================================

config_compositor() {
    local current_state
    if pgrep -x "picom" > /dev/null 2>&1; then
        current_state="actif"
    else
        current_state="inactif"
    fi

    CHOICE=$(zenity --list \
        --title="Compositeur Picom" \
        --text="Compositeur actuellement : <b>$current_state</b>\n\nNote: backend xrender obligatoire sous VirtualBox" \
        --column="Action" --column="Effet" \
        "Activer"      "Lance picom --backend xrender --no-vsync" \
        "Désactiver"   "Tue picom (pas de transparence/ombres)" \
        "Redémarrer"   "Relance picom (si plantage)" \
        --width=420 --height=280)

    case "$CHOICE" in
        "Activer")
            if pgrep -x "picom" > /dev/null 2>&1; then
                zenity --info --text="Picom est déjà actif." --width=250
            else
                picom --backend xrender --no-vsync -b
                sleep 1
                if pgrep -x "picom" > /dev/null 2>&1; then
                    COMPOSITOR_ENABLED=true
                    save_conf
                    notify "Compositeur activé"
                    zenity --info --text="✓ Picom démarré." --width=250
                else
                    zenity --error --text="Picom n'a pas démarré.\nConsultez : /tmp/hybryde-session.log" --width=350
                fi
            fi
            ;;
        "Désactiver")
            killall picom 2>/dev/null
            COMPOSITOR_ENABLED=false
            save_conf
            notify "Compositeur désactivé"
            zenity --info --text="✓ Picom arrêté." --width=250
            ;;
        "Redémarrer")
            killall picom 2>/dev/null
            sleep 1
            picom --backend xrender --no-vsync -b
            sleep 1
            if pgrep -x "picom" > /dev/null 2>&1; then
                notify "Compositeur redémarré"
                zenity --info --text="✓ Picom redémarré." --width=250
            else
                zenity --error --text="Picom n'a pas redémarré." --width=300
            fi
            ;;
    esac
}

#========================================================================
# AGENT POLKIT
#========================================================================

config_polkit() {
    local current="aucun"
    if pgrep -x "xfce-polkit"    > /dev/null 2>&1; then current="xfce-polkit"; fi
    if pgrep -f "polkit-mate"     > /dev/null 2>&1; then current="polkit-mate"; fi

    CHOICE=$(zenity --list \
        --title="Agent PolicyKit" \
        --text="Agent actif : <b>$current</b>\n\nL'agent polkit gère les demandes d'authentification\n(sudo graphique, montage de disques, etc.)" \
        --column="Agent" --column="Description" \
        "auto"        "Détection automatique au démarrage" \
        "xfce-polkit" "xfce-polkit (GTK, léger)" \
        "polkit-mate" "polkit-mate (GTK, MATE)" \
        "Redémarrer"  "Relancer l'agent actuel" \
        --width=440 --height=300)

    [ -z "$CHOICE" ] && return

    if [ "$CHOICE" = "Redémarrer" ]; then
        killall xfce-polkit polkit-mate-authentication-agent-1 2>/dev/null
        sleep 0.5
        if [ "$current" = "xfce-polkit" ] && [ -x /usr/libexec/xfce-polkit ]; then
            /usr/libexec/xfce-polkit &
        elif [ "$current" = "polkit-mate" ] && [ -x /usr/libexec/polkit-mate-authentication-agent-1 ]; then
            /usr/libexec/polkit-mate-authentication-agent-1 &
        fi
        notify "Agent polkit redémarré"
        return
    fi

    POLKIT_AGENT="$CHOICE"
    save_conf

    if [ "$CHOICE" != "auto" ]; then
        killall xfce-polkit polkit-mate-authentication-agent-1 2>/dev/null
        sleep 0.5
        case "$CHOICE" in
            "xfce-polkit")
                if [ -x /usr/libexec/xfce-polkit ]; then
                    /usr/libexec/xfce-polkit &
                    notify "Agent polkit : xfce-polkit"
                else
                    zenity --error --text="xfce-polkit absent.\nsudo apt install xfce-polkit" --width=300
                fi
                ;;
            "polkit-mate")
                if [ -x /usr/libexec/polkit-mate-authentication-agent-1 ]; then
                    /usr/libexec/polkit-mate-authentication-agent-1 &
                    notify "Agent polkit : polkit-mate"
                else
                    zenity --error --text="polkit-mate absent.\nsudo apt install mate-polkit" --width=300
                fi
                ;;
        esac
    fi
}

#========================================================================
# MENU PRINCIPAL
#========================================================================

show_menu() {
    while true; do
        local wp_short="${WALLPAPER_PATH##*/}"
        [ -z "$wp_short" ] && wp_short="non défini"

        local comp_state
        pgrep -x picom > /dev/null 2>&1 && comp_state="actif" || comp_state="inactif"

        local polkit_state="auto"
        pgrep -x "xfce-polkit" > /dev/null 2>&1 && polkit_state="xfce-polkit"
        pgrep -f "polkit-mate"  > /dev/null 2>&1 && polkit_state="polkit-mate"

        local current_icon current_gtk
        current_icon=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
        current_gtk=$(gsettings get org.gnome.desktop.interface gtk-theme   2>/dev/null | tr -d "'")

        local yad_hint=""
        command -v yad &> /dev/null && yad_hint=" (yad)" || yad_hint=" (zenity)"

        CHOICE=$(zenity --list \
            --title="Hybryde — Configuration" \
            --text="Personnalisez votre session Hybryde" \
            --column="Section" --column="État actuel" \
            "🖼  Fond d'écran"    "$wp_short ($WALLPAPER_MODE)" \
            "🎨 Thème d'icônes"  "${current_icon:-?}${yad_hint}" \
            "🖌  Thème GTK"       "${current_gtk:-?}" \
            "✨ Compositeur"      "$comp_state" \
            "🔐 Agent Polkit"     "${polkit_state}" \
            "📊 État session"     "Ouvrir hybryde-status" \
            --width=520 --height=360)

        case "$CHOICE" in
            "🖼  Fond d'écran")   config_wallpaper    ;;
            "🎨 Thème d'icônes")  config_icon_theme   ;;
            "🖌  Thème GTK")      config_gtk_theme    ;;
            "✨ Compositeur")     config_compositor   ;;
            "🔐 Agent Polkit")    config_polkit       ;;
            "📊 État session")
                if [ -x /usr/share/hybryde/scripts/session-x/hybryde-status.sh ]; then
                    /usr/share/hybryde/scripts/session-x/hybryde-status.sh --zenity &
                elif command -v hybryde-status.sh &> /dev/null; then
                    hybryde-status.sh --zenity &
                else
                    zenity --info --text="hybryde-status.sh introuvable." --width=300
                fi
                ;;
            *)
                break
                ;;
        esac
    done
}

#========================================================================
# POINT D'ENTRÉE
#========================================================================

case "${1:-}" in
    wallpaper)   config_wallpaper  ;;
    icon|icons)  config_icon_theme ;;
    gtk|theme)   config_gtk_theme  ;;
    compositor)  config_compositor ;;
    polkit)      config_polkit     ;;
    "")          show_menu         ;;
    *)
        echo "Usage: $0 [wallpaper | icons | gtk | compositor | polkit]"
        echo "  Sans argument : menu graphique complet"
        exit 1
        ;;
esac
