#!/bin/bash

#========================================================================
# hyb-logout.sh - Version modernisée pour systemd
# Original: Olivier Larrieu 2011
# Modernisation: 2024 - Support systemd et lightdm
#========================================================================

# Fonction de dialogue de confirmation
message()
{
    zenity --question \
        --text="Vous êtes sur le point de quitter votre session" \
        --title="Hybryde - Confirmation" \
        --width=300 || exit 0
}

# Verrouiller la session
deconnect()
{
    # Méthode moderne avec loginctl (systemd)
    if command -v loginctl &> /dev/null; then
        loginctl lock-session
    # Fallback pour lightdm
    elif command -v dm-tool &> /dev/null; then
        dm-tool lock
    # Fallback pour gnome-screensaver (ancien)
    elif command -v gnome-screensaver-command &> /dev/null; then
        gnome-screensaver-command -l
    else
        zenity --error --text="Impossible de verrouiller la session"
    fi
}

# Mise en veille
veille()
{
    message
    
    # Utilisation de systemd (méthode moderne)
    if command -v systemctl &> /dev/null; then
        systemctl suspend
    # Fallback UPower (ancien système)
    elif command -v dbus-send &> /dev/null; then
        dbus-send --system --print-reply \
            --dest=org.freedesktop.UPower \
            /org/freedesktop/UPower \
            org.freedesktop.UPower.Suspend
    else
        zenity --error --text="Impossible de mettre en veille"
    fi
}

# Hibernation
hibernate()
{
    message
    
    if command -v systemctl &> /dev/null; then
        systemctl hibernate
    else
        zenity --error --text="Hibernation non supportée"
    fi
}

# Redémarrage
restart()
{
    message
    
    # Utilisation de systemd (méthode moderne)
    if command -v systemctl &> /dev/null; then
        systemctl reboot
    # Fallback loginctl
    elif command -v loginctl &> /dev/null; then
        loginctl reboot
    # Fallback ConsoleKit (très ancien, pour compatibilité)
    elif command -v dbus-send &> /dev/null; then
        dbus-send --system --print-reply \
            --dest=org.freedesktop.ConsoleKit \
            /org/freedesktop/ConsoleKit/Manager \
            org.freedesktop.ConsoleKit.Manager.Restart
    else
        zenity --error --text="Impossible de redémarrer"
    fi
}

# Extinction
eteindre()
{
    message
    
    # Utilisation de systemd (méthode moderne)
    if command -v systemctl &> /dev/null; then
        systemctl poweroff
    # Fallback loginctl
    elif command -v loginctl &> /dev/null; then
        loginctl poweroff
    # Fallback ConsoleKit (très ancien, pour compatibilité)
    elif command -v dbus-send &> /dev/null; then
        dbus-send --system --print-reply \
            --dest=org.freedesktop.ConsoleKit \
            /org/freedesktop/ConsoleKit/Manager \
            org.freedesktop.ConsoleKit.Manager.Stop
    else
        zenity --error --text="Impossible d'éteindre"
    fi
}

# Déconnexion (quitter la session)
logout()
{
    message
    
    # Détecter l'environnement et tuer la session appropriée
    if [ -n "$GNOME_DESKTOP_SESSION_ID" ]; then
        gnome-session-quit --logout --no-prompt
    elif [ -n "$KDE_SESSION_VERSION" ]; then
        qdbus org.kde.ksmserver /KSMServer logout 0 0 0
    else
        # Méthode générique : tuer la session X
        killall -u $USER
    fi
}

# Menu principal si aucun argument
show_menu()
{
    CHOICE=$(zenity --list \
        --title="Hybryde - Gestion de session" \
        --text="Que voulez-vous faire ?" \
        --column="Action" --column="Description" \
        "deconnect" "Verrouiller la session" \
        "logout" "Se déconnecter" \
        "veille" "Mettre en veille" \
        "hibernate" "Hiberner" \
        "restart" "Redémarrer" \
        "eteindre" "Éteindre" \
        --width=400 --height=350)
    
    if [ -n "$CHOICE" ]; then
        $CHOICE
    fi
}

# Point d'entrée principal
if [ -z "$1" ]; then
    show_menu
else
    # Appeler la fonction passée en argument
    $1
fi
