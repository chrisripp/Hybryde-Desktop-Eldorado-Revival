#!/bin/bash
# Récupère la fenêtre sous le curseur
eval $(xdotool getmouselocation --shell 2>/dev/null)

# Récupère l'ID du bureau nautilus
DESKTOP=$(xdotool search --name "x-nautilus-desktop" 2>/dev/null | head -1)

# Lance jgmenu SEULEMENT si clic sur le bureau (root ou nautilus desktop)
if [ -z "$WINDOW" ] || [ "$WINDOW" = "0" ] || [ "$WINDOW" = "$DESKTOP" ]; then
    jgmenu_run
fi