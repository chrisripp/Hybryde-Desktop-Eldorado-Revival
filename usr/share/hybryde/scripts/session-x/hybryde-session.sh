#!/bin/bash
#========================================================================
# hybryde-session.sh  — Wrapper persistant de session pour LightDM
#========================================================================

HYBRYDE_SCRIPT="/usr/share/hybryde/scripts/session-x/hybx-script.sh"
FLAG_RETURN="/tmp/hybryde-return-flag"
FLAG_QUIT="/tmp/hybryde-quit-flag"

rm -f "$FLAG_RETURN" "$FLAG_QUIT"

restore_wallpaper() {
    # Attendre que les composants Hybryde soient chargés
    sleep 4
    # Toujours restaurer depuis ~/.fehbg-hybryde (référence Hybryde sauvegardée)
    # ~/.fehbg peut avoir été modifié par un DE invité
    if [ -f "$HOME/.fehbg-hybryde" ]; then
        cp "$HOME/.fehbg-hybryde" "$HOME/.fehbg"
        bash "$HOME/.fehbg"
    elif [ -f "$HOME/.fehbg" ]; then
        bash "$HOME/.fehbg"
    elif command -v nitrogen >/dev/null 2>&1; then
        nitrogen --restore
    elif command -v azote >/dev/null 2>&1; then
        azote --restore
    fi
}

while true; do
    # Restaurer le fond d'écran en arrière-plan pendant le démarrage
    restore_wallpaper &

    # Lancer la session Hybryde
    # hybx-script.sh (v4) bloque ici jusqu'à la mort de Cairo-Dock
    "$HYBRYDE_SCRIPT"

    # hybx-script.sh est sorti.
    # Deux cas possibles :
    #   - FLAG_RETURN posé par retour-hybryde.sh → on relance Hybryde
    #   - Pas de flag → fin de session normale → LightDM

    if [ -f "$FLAG_QUIT" ]; then
        rm -f "$FLAG_QUIT"
        exit 0
    fi

    if [ -f "$FLAG_RETURN" ]; then
        rm -f "$FLAG_RETURN"
        echo "[hybryde-session] Retour Hybryde demandé, redémarrage..."
        sleep 1
        # On reboucle → restore_wallpaper + hybx-script.sh relancés
        continue
    fi

    # Aucun flag → fin de session normale
    exit 0
done
