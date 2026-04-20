#!/bin/bash
#========================================================================
# generate-menu.sh - Générateur de menu Openbox pour Debian
# Scanne les fichiers .desktop et génère ~/.config/openbox/menu.xml
#========================================================================

MENU_FILE="${1:-$HOME/.config/openbox/menu.xml}"
DESKTOP_DIRS="/usr/share/applications /usr/local/share/applications $HOME/.local/share/applications"

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
        NAME=$(grep -m1 "^Name=" "$desktop" | cut -d= -f2-)
        EXEC=$(grep -m1 "^Exec=" "$desktop" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g')
        CATEGORIES=$(grep -m1 "^Categories=" "$desktop" | cut -d= -f2-)
        NODISPLAY=$(grep -m1 "^NoDisplay=" "$desktop" | cut -d= -f2-)
        HIDDEN=$(grep -m1 "^Hidden=" "$desktop" | cut -d= -f2-)
        TYPE=$(grep -m1 "^Type=" "$desktop" | cut -d= -f2-)

        # Ignorer les entrées cachées ou non-applications
        [ "$NODISPLAY" = "true" ] && continue
        [ "$HIDDEN" = "true" ] && continue
        [ "$TYPE" != "Application" ] && continue
        [ -z "$NAME" ] && continue
        [ -z "$EXEC" ] && continue

        # Échapper les caractères spéciaux XML
        NAME=$(echo "$NAME" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        EXEC=$(echo "$EXEC" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

        # Déterminer la catégorie
        ASSIGNED_CAT="Other"
        for cat in "${CAT_ORDER[@]}"; do
            if echo "$CATEGORIES" | grep -q "$cat"; then
                # Fusionner Audio/Video dans AudioVideo
                if [ "$cat" = "Audio" ] || [ "$cat" = "Video" ]; then
                    ASSIGNED_CAT="AudioVideo"
                else
                    ASSIGNED_CAT="$cat"
                fi
                break
            fi
        done

        # Construire l'entrée XML
        ENTRY="        <item label=\"$NAME\">\n            <action name=\"Execute\">\n                <execute>$EXEC</execute>\n            </action>\n        </item>"

        # Ajouter à la catégorie (éviter les doublons sur le nom)
        if ! echo "${CAT_ENTRIES[$ASSIGNED_CAT]}" | grep -q "label=\"$NAME\""; then
            CAT_ENTRIES[$ASSIGNED_CAT]+="$ENTRY\n"
        fi
    done
done

# Générer le XML
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
echo '        <item label="Terminal">'
echo '            <action name="Execute"><execute>xfce4-terminal</execute></action>'
echo '        </item>'
echo '        <item label="Navigateur web">'
echo '            <action name="Execute"><execute>firefox</execute></action>'
echo '        </item>'
echo '        <item label="Gestionnaire de fichiers">'
echo '            <action name="Execute"><execute>thunar</execute></action>'
echo '        </item>'
echo '        <separator />'
echo ''
echo '        <!-- Applications par catégorie -->'

for cat in "${CAT_ORDER[@]}"; do
    [ -z "${CAT_ENTRIES[$cat]}" ] && continue
    label="${CAT_LABELS[$cat]}"
    echo "        <menu id=\"menu-$cat\" label=\"$label\">"
    echo -e "${CAT_ENTRIES[$cat]}" | grep -v '^$'
    echo "        </menu>"
    echo ""
done

echo '        <menu id="client-list-menu" />'
echo '        <separator />'
echo ''
echo '        <!-- Retour à Hybryde -->'
echo '        <item label="Retour à Hybryde">'
echo '            <action name="Execute">'
echo '                <execute>/usr/share/hybryde/scripts/session-x/retour-hybryde.sh</execute>'
echo '            </action>'
echo '        </item>'
echo '        <separator />'
echo ''
echo '        <!-- Openbox -->'
echo '        <item label="Reconfigurer Openbox">'
echo '            <action name="Reconfigure" />'
echo '        </item>'
echo '        <separator />'
echo ''
echo '        <!-- Session -->'
echo '        <menu id="exit" label="Session">'
echo '            <item label="Déconnexion">'
echo '                <action name="Exit" />'
echo '            </item>'
echo '            <item label="Verrouiller">'
echo '                <action name="Execute"><execute>slock</execute></action>'
echo '            </item>'
echo '            <item label="Veille">'
echo '                <action name="Execute"><execute>systemctl suspend</execute></action>'
echo '            </item>'
echo '            <item label="Hibernation">'
echo '                <action name="Execute"><execute>systemctl hibernate</execute></action>'
echo '            </item>'
echo '            <item label="Redémarrer">'
echo '                <action name="Execute"><execute>systemctl reboot</execute></action>'
echo '            </item>'
echo '            <item label="Éteindre">'
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
