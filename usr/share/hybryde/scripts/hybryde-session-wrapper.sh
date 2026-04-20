#!/bin/bash

#========================================================================
# hybryde-session-wrapper.sh
# Wrapper pour isoler complètement la session Hybryde de XFCE
#========================================================================

# IMPORTANT : Redéfinir les variables d'environnement pour ne PAS être XFCE
export XDG_CURRENT_DESKTOP=HYBRYDE
export DESKTOP_SESSION=hybryde
export XDG_SESSION_DESKTOP=hybryde
export GDMSESSION=hybryde

# Désactiver le démarrage automatique XFCE
export XDG_CONFIG_DIRS=/etc/xdg
export XDG_DATA_DIRS=/usr/local/share:/usr/share

# Tuer les processus XFCE qui ont pu démarrer
killall xfce4-session 2>/dev/null
killall xfce4-panel 2>/dev/null
killall xfdesktop 2>/dev/null

# Attendre un peu
sleep 1

# Lancer le vrai script Hybryde
exec /usr/share/hybryde/scripts/session-x/hybx-script.sh
