#!/bin/bash
#========================================================================
# generate-menu.sh - Générateur de menu Openbox pour Debian
# Scanne les fichiers .desktop et génère ~/.config/openbox/menu.xml
# v2 : support icônes (attribut icon= sur chaque <item>)
#========================================================================

MENU_FILE="${1:-$HOME/.config/openbox/menu.xml}"
DESKTOP_DIRS="/usr/share/applications /usr/local/share/applications $HOME/.local/share/applications"

# Répertoires d'icônes, par ordre de priorité (PNG 48px en premier)
ICON_DIRS=(
    "/usr/share/icons/hicolor/48x48/apps"
    "/usr/share/icons/hicolor/32x32/apps"
    "/usr/share/icons/hicolor/24x24/apps"
    "/usr/share/icons/Adwaita/48x48/apps"
    "/usr/share/icons/gnome/48x48/apps"
    "/usr/share/icons/hicolor/scalable/apps"
    "/usr/share/pixmaps"
    "$HOME/.local/share/icons/hicolor/48x48/apps"
    "$HOME/.local/share/icons"
)

#========================================================================
# Résoudre un nom d'icône vers un chemin absolu
# Si déjà un chemin absolu → vérifier existence
# Sinon → chercher PNG puis SVG dans ICON_DIRS
# Retourne le chemin trouvé, ou le nom brut en fallback (Openbox GTK)
#========================================================================
resolve_icon() {
    local icon_name="$1"
    [ -z "$icon_name" ] && return

    # Chemin absolu
    if [[ "$icon_name" == /* ]]; then
        [ -f "$icon_name" ] && echo "$icon_name"
        return
    fi

    # Supprimer extension éventuelle (ex: firefox.png → firefox)
    local base="${icon_name%.*}"

    for dir in "${ICON_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for ext in png svg xpm; do
            local path="$dir/${base}.${ext}"
            if [ -f "$path" ]; then
                echo "$path"
                return
            fi
        done
    done

    # Fallback : nom brut, Openbox essaiera via le thème GTK courant
    echo "$icon_name"
}

# Catégories Openbox → labels français
declare -A CAT_LABELS=(
    ["AudioVideo"]="Son et Vidéo"
    ["Audio"]="Son et Vidéo"
    ["Video"]="Son et Vidéo"
    ["Development"]="Développement"
    ["Education"]="Éducation"
    ["Game"]="Jeux"
    ["Graphics"]="Graphisme"
    ["Network"]="Internet"
    ["Office"]="Bureautique"
    ["Science"]="Science"
    ["Settings"]="Paramètres"
    ["System"]="Système"
    ["Utility"]="Utilitaires"
    ["Accessories"]="Accessoires"
    ["Other"]="Autres"
)

# Icônes des sous-menus de catégorie
declare -A CAT_ICONS=(
    ["AudioVideo"]="applications-multimedia"
    ["Development"]="applications-development"
    ["Education"]="applications-education"
    ["Game"]="applications-games"
    ["Graphics"]="applications-graphics"
    ["Network"]="applications-internet"
    ["Office"]="applications-office"
    ["Science"]="applications-science"
    ["System"]="applications-system"
    ["Settings"]="preferences-system"
    ["Utility"]="applications-utilities"
    ["Other"]="applications-other"
)

# Ordre d'affichage des catégories
CAT_ORDER=(
    "Network"
    "AudioVideo"
    "Graphics"
    "Office"
    "Development"
    "Game"
    "Education"
    "Science"
    "System"
    "Settings"
    "Utility"
    "Other"
)

# Tableau associatif : catégorie → liste d'entrées XML
declare -A CAT_ENTRIES

# Parcourir tous les fichiers .desktop
for dir in $DESKTOP_DIRS; do
    [ -d "$dir" ] || continue
    for desktop in "$dir"/*.desktop; do
        [ -f "$desktop" ] || continue

        # Lire les champs nécessaires
        # Nom français en priorité
        NAME=$(grep -m1 "^Name\[fr\]=" "$desktop" | cut -d= -f2-)
        [ -z "$NAME" ] && NAME=$(grep -m1 "^Name=" "$desktop" | cut -d= -f2-)
        EXEC=$(grep -m1 "^Exec=" "$desktop" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g')
        ICON_RAW=$(grep -m1 "^Icon=" "$desktop" | cut -d= -f2-)
        CATEGORIES=$(grep -m1 "^Categories=" "$desktop" | cut -d= -f2-)
        NODISPLAY=$(grep -m1 "^NoDisplay=" "$desktop" | cut -d= -f2-)
        HIDDEN=$(grep -m1 "^Hidden=" "$desktop" | cut -d= -f2-)
        TYPE=$(grep -m1 "^Type=" "$desktop" | cut -d= -f2-)

        # Ignorer les entrées cachées ou non-applications
        [ "$NODISPLAY" = "true" ] && continue
        [ "$HIDDEN"    = "true" ] && continue
        [ "$TYPE"      != "Application" ] && continue
        [ -z "$NAME" ] && continue
        [ -z "$EXEC" ] && continue

        # Échapper les caractères spéciaux XML
        NAME=$(echo "$NAME" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        EXEC=$(echo "$EXEC" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

        # Résoudre l'icône
        ICON_PATH=$(resolve_icon "$ICON_RAW")
        if [ -n "$ICON_PATH" ]; then
            ICON_ATTR=" icon=\"$ICON_PATH\""
        else
            ICON_ATTR=""
        fi

        # Déterminer la catégorie
        ASSIGNED_CAT="Other"
        for cat in "${CAT_ORDER[@]}"; do
            if echo "$CATEGORIES" | grep -q "$cat"; then
                if [ "$cat" = "Audio" ] || [ "$cat" = "Video" ]; then
                    ASSIGNED_CAT="AudioVideo"
                else
                    ASSIGNED_CAT="$cat"
                fi
                break
            fi
        done

        # Construire l'entrée XML avec icône
        ENTRY="        <item label=\"$NAME\"${ICON_ATTR}>\n            <action name=\"Execute\">\n                <execute>$EXEC</execute>\n            </action>\n        </item>"

        # Ajouter à la catégorie (éviter les doublons sur le nom)
        if ! echo "${CAT_ENTRIES[$ASSIGNED_CAT]}" | grep -q "label=\"$NAME\""; then
            CAT_ENTRIES[$ASSIGNED_CAT]+="$ENTRY\n"
        fi
    done
done

#========================================================================
# Icônes des entrées fixes du menu
#========================================================================
ICON_TERMINAL=$(resolve_icon "utilities-terminal")
ICON_BROWSER=$(resolve_icon "firefox")
[ -z "$ICON_BROWSER" ] && ICON_BROWSER=$(resolve_icon "web-browser")
ICON_FILES=$(resolve_icon "system-file-manager")
ICON_HYBRYDE=$(resolve_icon "user-home")
ICON_RECONFIG=$(resolve_icon "openbox")
[ -z "$ICON_RECONFIG" ] && ICON_RECONFIG=$(resolve_icon "preferences-system")
ICON_SESSION=$(resolve_icon "system-log-out")
ICON_LOCK=$(resolve_icon "system-lock-screen")
ICON_SLEEP=$(resolve_icon "system-suspend")
ICON_HIBERNATE=$(resolve_icon "system-hibernate")
ICON_REBOOT=$(resolve_icon "system-reboot")
ICON_SHUTDOWN=$(resolve_icon "system-shutdown")

# Retourne l'attribut icon="..." ou vide
icon_attr() {
    local path="$1"
    [ -n "$path" ] && echo " icon=\"$path\""
}

#========================================================================
# Générer le XML
#========================================================================
{
echo '<?xml version="1.0" encoding="UTF-8"?>'
echo '<openbox_menu'
echo '    xmlns="http://openbox.org/"'
echo '    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
echo '    xsi:schemaLocation="http://openbox.org/'
echo '    file:///usr/share/openbox/menu.xsd">'
echo ''
echo '    <menu id="root-menu" label="Openbox">'
echo ''
echo '        <!-- Applications favorites -->'
echo "        <item label=\"Terminal\"$(icon_attr "$ICON_TERMINAL")>"
echo '            <action name="Execute"><execute>xfce4-terminal</execute></action>'
echo '        </item>'
echo "        <item label=\"Navigateur web\"$(icon_attr "$ICON_BROWSER")>"
echo '            <action name="Execute"><execute>firefox</execute></action>'
echo '        </item>'
echo "        <item label=\"Gestionnaire de fichiers\"$(icon_attr "$ICON_FILES")>"
echo '            <action name="Execute"><execute>thunar</execute></action>'
echo '        </item>'
echo '        <separator />'
echo ''
echo '        <!-- Applications par catégorie -->'

for cat in "${CAT_ORDER[@]}"; do
    [ -z "${CAT_ENTRIES[$cat]}" ] && continue
    label="${CAT_LABELS[$cat]}"
    cat_icon=$(resolve_icon "${CAT_ICONS[$cat]}")
    if [ -n "$cat_icon" ]; then
        echo "        <menu id=\"menu-$cat\" label=\"$label\" icon=\"$cat_icon\">"
    else
        echo "        <menu id=\"menu-$cat\" label=\"$label\">"
    fi
    echo -e "${CAT_ENTRIES[$cat]}" | grep -v '^$'
    echo "        </menu>"
    echo ""
done

echo '        <menu id="client-list-menu" />'
echo '        <separator />'
echo ''
echo '        <!-- Retour à Hybryde -->'
echo "        <item label=\"Retour à Hybryde\"$(icon_attr "$ICON_HYBRYDE")>"
echo '            <action name="Execute">'
echo '                <execute>/usr/share/hybryde/scripts/session-x/retour-hybryde.sh</execute>'
echo '            </action>'
echo '        </item>'
echo '        <separator />'
echo ''
echo '        <!-- Openbox -->'
echo "        <item label=\"Reconfigurer Openbox\"$(icon_attr "$ICON_RECONFIG")>"
echo '            <action name="Reconfigure" />'
echo '        </item>'
echo '        <separator />'
echo ''
echo '        <!-- Session -->'
echo "        <menu id=\"exit\" label=\"Session\"$(icon_attr "$ICON_SESSION")>"
echo '            <item label="Déconnexion">'
echo '                <action name="Exit" />'
echo '            </item>'
echo "            <item label=\"Verrouiller\"$(icon_attr "$ICON_LOCK")>"
echo '                <action name="Execute"><execute>slock</execute></action>'
echo '            </item>'
echo "            <item label=\"Veille\"$(icon_attr "$ICON_SLEEP")>"
echo '                <action name="Execute"><execute>systemctl suspend</execute></action>'
echo '            </item>'
echo "            <item label=\"Hibernation\"$(icon_attr "$ICON_HIBERNATE")>"
echo '                <action name="Execute"><execute>systemctl hibernate</execute></action>'
echo '            </item>'
echo "            <item label=\"Redémarrer\"$(icon_attr "$ICON_REBOOT")>"
echo '                <action name="Execute"><execute>systemctl reboot</execute></action>'
echo '            </item>'
echo "            <item label=\"Éteindre\"$(icon_attr "$ICON_SHUTDOWN")>"
echo '                <action name="Execute"><execute>systemctl poweroff</execute></action>'
echo '            </item>'
echo '        </menu>'
echo ''
echo '    </menu>'
echo '</openbox_menu>'
} > "$MENU_FILE"

echo "✓ Menu généré : $MENU_FILE"
echo "  Catégories :"
for cat in "${CAT_ORDER[@]}"; do
    [ -z "${CAT_ENTRIES[$cat]}" ] && continue
    count=$(echo -e "${CAT_ENTRIES[$cat]}" | grep -c "item label" || true)
    echo "    - ${CAT_LABELS[$cat]} : $count applications"
done
openbox --reconfigure
