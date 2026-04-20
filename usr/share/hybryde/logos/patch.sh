#!/bin/bash
#========================================================================
# patch-yad-logo.sh — Injecte le logo Hybryde dans les fenêtres yad
# Logo source : /usr/share/hybryde/logos/hybryde.png (716x219)
# Cible : hyb-logout.sh, retour-hybryde.sh
#========================================================================

LOGO_SRC="/usr/share/hybryde/logos/hybryde.png"
LOGO_DIR="/usr/share/hybryde/logos"
LOGO_SM="$LOGO_DIR/hybryde-sm.png"   # 240x73  — hyb-logout (fenêtre large)
LOGO_XS="$LOGO_DIR/hybryde-xs.png"   # 160x49  — retour-hybryde (fenêtre compacte)

LOGOUT="/usr/share/hybryde/scripts/hyb-logout.sh"
RETOUR="/usr/share/hybryde/scripts/session-x/retour-hybryde.sh"

GREEN="\e[32m"; RED="\e[31m"; CYAN="\e[1;36m"; RESET="\e[0m"
ok()   { echo -e "${GREEN}✓ $1${RESET}"; }
fail() { echo -e "${RED}✗ $1${RESET}"; exit 1; }
step() { echo -e "\n${CYAN}── $1${RESET}"; }

#── 1. Vérifications ────────────────────────────────────────────────────
step "Vérifications"

command -v convert &>/dev/null || fail "ImageMagick requis : sudo apt install imagemagick"
[ -f "$LOGO_SRC" ]             || fail "Logo introuvable : $LOGO_SRC"
[ -f "$LOGOUT" ]               || fail "Script introuvable : $LOGOUT"
[ -f "$RETOUR" ]               || fail "Script introuvable : $RETOUR"

ok "Dépendances OK"

#── 2. Créer les logos redimensionnés ───────────────────────────────────
step "Création des logos redimensionnés"

convert "$LOGO_SRC" -resize 240x73 "$LOGO_SM" \
    && ok "Logo SM : $LOGO_SM (240x73)" \
    || fail "Impossible de créer $LOGO_SM"

convert "$LOGO_SRC" -resize 160x49 "$LOGO_XS" \
    && ok "Logo XS : $LOGO_XS (160x49)" \
    || fail "Impossible de créer $LOGO_XS"

#── 3. Patcher hyb-logout.sh ────────────────────────────────────────────
step "Patch hyb-logout.sh"

if grep -q "hybryde-sm.png" "$LOGOUT"; then
    ok "Déjà patché — ignoré"
else
    cp "$LOGOUT" "${LOGOUT}.bak"
    # Remplacer la ligne --window-icon dans YAD_COMMON pour ajouter --image dessous
    sed -i "s|--window-icon=\"system-log-out\"|--window-icon=\"system-log-out\"\n    --image=\"$LOGO_SM\"|" "$LOGOUT"
    ok "hyb-logout.sh patché (backup : ${LOGOUT}.bak)"
fi

#── 4. Patcher retour-hybryde.sh ────────────────────────────────────────
step "Patch retour-hybryde.sh"

if grep -q "hybryde-xs.png" "$RETOUR"; then
    ok "Déjà patché — ignoré"
else
    cp "$RETOUR" "${RETOUR}.bak"
    # Même principe sur --window-icon de YAD_COMMON
    sed -i "s|--window-icon=\"go-home\"|--window-icon=\"go-home\"\n    --image=\"$LOGO_XS\"|" "$RETOUR"
    ok "retour-hybryde.sh patché (backup : ${RETOUR}.bak)"
fi

#── 5. Résumé ────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}✓ Patch terminé !${RESET}"
echo "  Logo SM 240x73 → menus hyb-logout"
echo "  Logo XS 160x49 → dialogues retour-hybryde"
echo ""
echo "Pour annuler :"
echo "  cp ${LOGOUT}.bak $LOGOUT"
echo "  cp ${RETOUR}.bak $RETOUR"

