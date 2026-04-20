#!/bin/bash

#========================================================================
# eggs-produce.sh — Nettoyage & Production ISO Hybryde
# Utilise penguins-eggs + BleachBit (root et utilisateur)
#========================================================================

set -e

BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

step() {
    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
    echo -e "${CYAN}${BOLD}  $1${RESET}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
}

ok()   { echo -e "${GREEN}✓ $1${RESET}"; }
warn() { echo -e "${YELLOW}⚠  $1${RESET}"; }
fail() { echo -e "${RED}✗ $1${RESET}"; exit 1; }

# ── Vérifications préliminaires ────────────────────────────────────────

if [ "$EUID" -ne 0 ]; then
    fail "Ce script doit être exécuté en root (sudo $0)"
fi

CURRENT_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
if [ -z "$CURRENT_USER" ]; then
    warn "Impossible de détecter l'utilisateur courant — BleachBit utilisateur sera ignoré"
fi

command -v eggs   >/dev/null 2>&1 || fail "penguins-eggs introuvable. Installez-le d'abord."
command -v bleachbit >/dev/null 2>&1 || warn "BleachBit introuvable — les étapes BleachBit seront ignorées"

echo ""
echo -e "${BOLD}  Production ISO Hybryde avec penguins-eggs${RESET}"
echo -e "  Utilisateur détecté : ${YELLOW}${CURRENT_USER:-inconnu}${RESET}"
echo ""

# ── Étape 1 : Nettoyage eggs ──────────────────────────────────────────

step "1/5 — eggs tools clean"
eggs tools clean
ok "Nettoyage eggs terminé"

# ── Étape 2 : BleachBit en root ───────────────────────────────────────

step "2/5 — BleachBit (mode root)"
if command -v bleachbit >/dev/null 2>&1; then
    echo "Lancement BleachBit en mode graphique (root)..."
    echo "Fermez BleachBit quand le nettoyage est terminé."
    bleachbit
    ok "BleachBit root terminé"
else
    warn "BleachBit absent — étape ignorée"
fi

# ── Étape 3 : BleachBit en utilisateur normal ─────────────────────────

step "3/5 — BleachBit (utilisateur : ${CURRENT_USER:-ignoré})"
if command -v bleachbit >/dev/null 2>&1 && [ -n "$CURRENT_USER" ]; then
    echo "Lancement BleachBit pour l'utilisateur $CURRENT_USER..."
    echo "Fermez BleachBit quand le nettoyage est terminé."
    sudo -u "$CURRENT_USER" DISPLAY="${DISPLAY:-:0}" \
         XAUTHORITY="/home/$CURRENT_USER/.Xauthority" \
         bleachbit
    ok "BleachBit utilisateur terminé"
else
    warn "BleachBit utilisateur — étape ignorée"
fi

# ── Étape 4 : Mise à jour du squelette ───────────────────────────────

step "4/5 — eggs tools skel --user hybryde"
eggs tools skel --user hybryde
ok "Squelette mis à jour"

# ── Étape 5 : Configuration par défaut ───────────────────────────────

step "5/5a — eggs dad --default"
eggs dad --default
ok "Configuration eggs appliquée"

# ── Étape 6 : Production de l'ISO ────────────────────────────────────

step "5/5b — eggs produce --clone"
echo "Démarrage de la production ISO (cela peut prendre plusieurs minutes)..."
eggs produce --clone
ok "ISO produite avec succès !"

# ── Résumé ────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Production terminée !${RESET}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo ""
echo "Vérifiez le résultat dans /home/eggs/ (ou le répertoire configuré par eggs dad)."
echo ""
