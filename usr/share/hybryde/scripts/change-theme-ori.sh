#!/bin/bash

#========================================================================
# change-theme.sh - Sélection de thème GTK pour Hybryde
#========================================================================

echo "========================================="
echo "  Sélecteur de thème GTK - Hybryde"
echo "========================================="
echo ""

# Thème actuel
CURRENT=$(gsettings get org.gnome.desktop.interface gtk-theme)
echo "Thème actuel : $CURRENT"
echo ""

# Lister les thèmes disponibles (uniquement ceux avec gtk-3.0 ou gtk-2.0)
echo "Thèmes disponibles :"
echo "-----------------------------------------"

THEMES=()
i=1
for d in /usr/share/themes/*/; do
    theme=$(basename "$d")
    if [ -d "$d/gtk-3.0" ] || [ -d "$d/gtk-2.0" ]; then
        echo "  $i) $theme"
        THEMES+=("$theme")
        i=$((i + 1))
    fi
done

# Thèmes utilisateur (~/.themes/)
if [ -d "$HOME/.themes" ]; then
    for d in "$HOME/.themes/"/*/; do
        theme=$(basename "$d")
        if [ -d "$d/gtk-3.0" ] || [ -d "$d/gtk-2.0" ]; then
            echo "  $i) $theme (~/.themes)"
            THEMES+=("$theme")
            i=$((i + 1))
        fi
    done
fi

echo "-----------------------------------------"
echo ""

if [ ${#THEMES[@]} -eq 0 ]; then
    echo "Aucun thème valide trouvé."
    echo "Installez des thèmes : sudo apt install arc-theme materia-gtk-theme"
    echo ""
    read -p "Appuyez sur Entrée pour quitter..."
    exit 1
fi

# Saisie du choix
read -p "Entrez le numéro du thème à appliquer (ou q pour quitter) : " CHOICE

if [ "$CHOICE" = "q" ] || [ -z "$CHOICE" ]; then
    echo "Annulé."
    read -p "Appuyez sur Entrée pour quitter..."
    exit 0
fi

# Validation
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#THEMES[@]} ]; then
    echo "Choix invalide."
    read -p "Appuyez sur Entrée pour quitter..."
    exit 1
fi

# Appliquer le thème
SELECTED="${THEMES[$((CHOICE - 1))]}"
echo ""
echo "Application du thème : $SELECTED"
gsettings set org.gnome.desktop.interface gtk-theme "$SELECTED"

# Vérification
APPLIED=$(gsettings get org.gnome.desktop.interface gtk-theme)
echo "✓ Thème appliqué : $APPLIED"
echo ""

# Persister dans l'autostart
AUTOSTART="$HOME/.hybryde/autostart/autostart.sh"
if [ -f "$AUTOSTART" ]; then
    # Supprimer l'ancienne ligne gsettings gtk-theme si elle existe
    sed -i '/gsettings set org.gnome.desktop.interface gtk-theme/d' "$AUTOSTART"
    # Ajouter la nouvelle ligne avant "exit 0"
    sed -i "s|^exit 0|gsettings set org.gnome.desktop.interface gtk-theme \"$SELECTED\"\nexit 0|" "$AUTOSTART"
    echo "✓ Thème sauvegardé dans l'autostart"
fi

echo ""
read -p "Appuyez sur Entrée pour quitter..."
