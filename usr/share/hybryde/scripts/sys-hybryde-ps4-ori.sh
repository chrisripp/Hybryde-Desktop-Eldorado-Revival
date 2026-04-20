#!/bin/bash

#========================================================================
# hybryde-sysinfo.sh — Informations système multi-onglets (V4 corrigé)
# Corrections :
#   - Benchmark : dclick-action via script lanceur (pipe cassé supprimé)
#   - Heaven    : $HOME/PS4/benchmark/Heaven/heaven
#   - inxi      : bouton ⟳ Rafraîchir dans la fenêtre principale
#========================================================================

#----------------------------------------------------
# Fonctions utilitaires
#----------------------------------------------------
function show_mod_info {
    TXT="$(modinfo "$1" 2>/dev/null | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g')"
    yad --title="Module information" \
        --window-icon="application-x-addon" \
        --button="Fermer:0" \
        --width=500 \
        --image="application-x-addon" --text="$TXT"
}
export -f show_mod_info

function safe_cmd {
    "$@" 2>/dev/null || echo "N/A"
}
export -f safe_cmd

#----------------------------------------------------
# Chemin Unigine Heaven
#----------------------------------------------------
HEAVEN_PATH="$HOME/PS4/benchmark/Heaven/heaven"

#----------------------------------------------------
# Création des scripts temporaires pour le benchmark
# (Les scripts .sh évitent les problèmes de quotes dans dclick-action)
#----------------------------------------------------

# CPU Benchmark — fenêtre yad dédiée
cat > /tmp/hyb-cpu-bench.sh << 'BENCH_EOF'
#!/bin/bash
TMPFILE=$(mktemp)
{
    echo "=== CPU Benchmark Hybryde ==="
    echo "Date : $(date)"
    echo ""
    if command -v sysbench >/dev/null 2>&1; then
        echo "--- Sysbench CPU (max-prime=20000) ---"
        sysbench cpu --cpu-max-prime=20000 run 2>&1
    else
        echo "⚠  sysbench non installé (sudo apt install sysbench)"
    fi
    echo ""
    echo "--- Throughput gzip (200 Mo) ---"
    GZIP_SCORE=$(dd if=/dev/zero bs=1M count=200 2>/dev/null | gzip -c | wc -c)
    echo "Score gzip : $GZIP_SCORE octets compressés"
    echo ""
    echo "--- Hash SHA1 (200 Mo) ---"
    SHA_RESULT=$(dd if=/dev/zero bs=1M count=200 2>/dev/null | sha1sum)
    echo "SHA1 : $SHA_RESULT"
} > "$TMPFILE" 2>&1
yad --title="CPU Benchmark" \
    --width=650 --height=480 \
    --text-info --scroll \
    --filename="$TMPFILE" \
    --button="Fermer:0"
rm -f "$TMPFILE"
BENCH_EOF
chmod +x /tmp/hyb-cpu-bench.sh

# Sysbench en terminal
cat > /tmp/hyb-sysbench-term.sh << 'SYS_EOF'
#!/bin/bash
echo "=== Sysbench CPU (max-prime=20000) ==="
echo ""
if command -v sysbench >/dev/null 2>&1; then
    sysbench cpu --cpu-max-prime=20000 run
else
    echo "⚠  sysbench non installé : sudo apt install sysbench"
fi
echo ""
read -r -p "Terminé — Entrée pour fermer..."
SYS_EOF
chmod +x /tmp/hyb-sysbench-term.sh

# Stress-ng en terminal
cat > /tmp/hyb-stress-term.sh << 'STRESS_EOF'
#!/bin/bash
echo "=== Stress CPU — stress-ng --cpu 4 (60s) ==="
echo "Ctrl+C pour arrêter prématurément"
echo ""
if command -v stress-ng >/dev/null 2>&1; then
    stress-ng --cpu 4 --timeout 60 --metrics-brief
else
    echo "⚠  stress-ng non installé : sudo apt install stress-ng"
fi
echo ""
read -r -p "Terminé — Entrée pour fermer..."
STRESS_EOF
chmod +x /tmp/hyb-stress-term.sh

# Script lanceur principal benchmark
# IMPORTANT : yad --dclick-action passe TOUTE la ligne (label + cmd) dans %s,
# pas uniquement print-column=2. On filtre donc par mots-clés du label.
cat > /tmp/hyb-bench-run.sh << RUNEOF
#!/bin/bash
# Lanceur benchmark — généré par hybryde-sysinfo.sh
# \$* contient : label yad + éventuellement la valeur de la colonne cachée
HEAVEN_PATH="$HEAVEN_PATH"
case "\$*" in
    *"CPU Benchmark"*)  /tmp/hyb-cpu-bench.sh ;;
    *"Sysbench CPU"*)   xfce4-terminal -e /tmp/hyb-sysbench-term.sh ;;
    *"Stress CPU"*)     xfce4-terminal -e /tmp/hyb-stress-term.sh ;;
    *"vkcube"*)         vkcube & ;;
    *"vkmark"*)         vkmark & ;;
    *"glxgears"*)       glxgears & ;;
    *"glmark2"*)        glmark2 & ;;
    *"es2gears"*)       es2gears_x11 & ;;
    *"Heaven"*)         "\$HEAVEN_PATH" & ;;
    # séparateurs et lignes vides → rien
esac
RUNEOF
chmod +x /tmp/hyb-bench-run.sh

#----------------------------------------------------
# Lancement de tous les onglets plugs
# $1 = KEY yad courant
# Remplit le tableau global TAB_PIDS
#----------------------------------------------------
launch_tabs() {
    local KEY="$1"
    TAB_PIDS=()

    #### Onglet 1 — CPU ####
    safe_cmd lscpu | sed -r "s/:[ ]*/\n/" \
    | yad --plug="$KEY" --tabnum=1 \
          --list --no-selection \
          --column="Paramètre" --column="Valeur" &
    TAB_PIDS+=($!)

    #### Onglet 2 — Mémoire ####
    safe_cmd free -h | awk 'NR==1{next} {printf "%s\n%s\n%s\n", $1,$2,$3}' \
    | yad --plug="$KEY" --tabnum=2 \
          --list --no-selection \
          --column="Type" --column="Total" --column="Utilisé" &
    TAB_PIDS+=($!)

    #### Onglet 3 — Disques ####
    safe_cmd df -T | tail -n +2 \
        | awk '{printf "%s\n%s\n%s\n%s\n%s\n%s\n", $1,$7,$2,$3,$4,$6}' \
    | yad --plug="$KEY" --tabnum=3 \
          --list --no-selection \
          --column="Périphérique" --column="Point de montage" --column="Type" \
          --column="Total:sz" --column="Libre:sz" --column="Utilisation:bar" &
    TAB_PIDS+=($!)

    #### Onglet 4 — I/O ####
    safe_cmd iostat -x 1 1 | tail -n +4 \
        | awk '{printf "%s\n%s\n%s\n%s\n%s\n", $1,$2,$3,$4,$10}' \
    | yad --plug="$KEY" --tabnum=4 \
          --list --no-selection \
          --column="Périphérique" --column="tps" --column="KB lect/s" \
          --column="KB écrit/s" --column="%Util" &
    TAB_PIDS+=($!)

    #### Onglet 5 — Processus ####
    ps aux --sort=-%mem | head -n 10 \
        | awk '{printf "%s\n%s\n%s\n%s\n", $1,$3,$4,$11}' \
    | yad --plug="$KEY" --tabnum=5 \
          --list --no-selection \
          --column="Utilisateur" --column="CPU%" --column="MEM%" --column="Commande" &
    TAB_PIDS+=($!)

    #### Onglet 6 — Charge ####
    echo -e "Charge\n$(uptime | awk -F'load average:' '{print $2}')" \
        | sed 's/,/\n/g' \
    | yad --plug="$KEY" --tabnum=6 \
          --list --no-selection \
          --column="Métrique" --column="Valeur" &
    TAB_PIDS+=($!)

    #### Onglet 7 — GPU ####
    {
        safe_cmd lspci | grep -i vga
        safe_cmd glxinfo 2>/dev/null | grep "OpenGL renderer"
    } | sed -r "s/: /\n/" \
    | yad --plug="$KEY" --tabnum=7 \
          --list --no-selection \
          --column="Type" --column="Valeur" &
    TAB_PIDS+=($!)

    #### Onglet 8 — USB ####
    safe_cmd lsusb \
    | yad --plug="$KEY" --tabnum=8 \
          --list --no-selection \
          --column="Périphériques USB" &
    TAB_PIDS+=($!)

    #### Onglet 9 — Réseau ####
    safe_cmd hostname -I | tr ' ' '\n' \
    | yad --plug="$KEY" --tabnum=9 \
          --list --no-selection \
          --column="Adresse IP" &
    TAB_PIDS+=($!)

    #### Onglet 10 — PCI ####
    if command -v lspci >/dev/null 2>&1; then
        lspci -vmm | grep -E "^(Slot|Class|Vendor|Device|Rev):" | cut -f2 \
        | yad --plug="$KEY" --tabnum=10 \
              --list --no-selection \
              --column="ID" --column="Classe" \
              --column="Fabricant" --column="Périphérique" \
              --column="Rév." &
    else
        yad --plug="$KEY" --tabnum=10 \
            --text="lspci non disponible" &
    fi
    TAB_PIDS+=($!)

   #### Onglet 11 — Modules (PS4 / PC / USB aware) ####

TMPFILE=$(mktemp)

{
    echo "=== Modules chargés (kernel live) ==="
    echo ""

    if [[ -s /proc/modules ]]; then
        cat /proc/modules
    else
        echo "Aucun module chargé actuellement"
    fi

    echo ""
    echo "====================================="
    echo "=== Modules dans initramfs détectés ==="
    echo "====================================="
    echo ""

    FOUND_INIT=0

    for img in \
        /system/boot/initramfs.cpio.gz \
        /system/boot/initramfs.gz \
        /mnt/sda1/initramfs.cpio.gz \
        /mnt/sda1/initramfs.gz \
        /mnt/sda1/initrd.img \
        /boot/initrd.img*; do

        if [[ -f "$img" ]]; then
            FOUND_INIT=1
            echo "--- $img ---"
            zcat "$img" 2>/dev/null \
                | cpio -t 2>/dev/null \
                | grep '\.ko' \
                || echo "Impossible de lire ou aucun module"
            echo ""
        fi
    done

    if [[ $FOUND_INIT -eq 0 ]]; then
        echo "Aucun initramfs trouvé"
    fi

    echo ""
    echo "====================================="
    echo "=== Kernel détecté (bzImage) ==="
    echo "====================================="
    echo ""

    for k in \
        /system/boot/bzImage \
        /mnt/sda1/bzImage \
        /boot/vmlinuz*; do

        if [[ -f "$k" ]]; then
            echo "Kernel trouvé : $k"
        fi
    done

    echo ""
    echo "====================================="
    echo "=== Modules disponibles (/lib/modules) ==="
    echo "====================================="
    echo ""

    if [[ -d /lib/modules/$(uname -r) ]]; then
        find /lib/modules/$(uname -r) -name "*.ko" | head -n 80
        echo ""
        echo "(limité à 80 modules)"
    else
        echo "Aucun dossier /lib/modules/$(uname -r)"
    fi

    echo ""
    echo "====================================="
    echo "=== Drivers actifs (fallback PS4) ==="
    echo "====================================="
    echo ""

    if command -v lspci >/dev/null 2>&1; then
        lspci -k
    else
        echo "lspci non disponible"
    fi

    echo ""
    echo "====================================="
    echo "=== Info kernel modules config ==="
    echo "====================================="
    echo ""

    if [[ -f /proc/config.gz ]]; then
        zcat /proc/config.gz | grep CONFIG_MODULES
    else
        echo "config.gz non disponible"
    fi

} > "$TMPFILE"

yad --plug="$KEY" --tabnum=11 \
    --text-info --scroll \
    --width=900 --height=550 \
    --filename="$TMPFILE" &

TAB_PIDS+=($!)

    #### Onglet 12 — Capteurs ####
    if command -v sensors >/dev/null 2>&1; then
        sensors | sed -r "s/: /\n/" \
        | yad --plug="$KEY" --tabnum=12 \
              --list --no-selection \
              --column="Capteur" --column="Valeur" &
    else
        yad --plug="$KEY" --tabnum=12 \
            --text="sensors non disponible (sudo apt install lm-sensors)" &
    fi
    TAB_PIDS+=($!)

    #### Onglet 13 — inxi -F ####
    if command -v inxi >/dev/null 2>&1; then
        inxi -F 2>/dev/null \
        | yad --plug="$KEY" --tabnum=13 \
              --text="<b>inxi -F</b> — utilisez ⟳ Rafraîchir inxi (bas de fenêtre) pour recharger" \
              --text-info --scroll \
              --width=800 --height=500 &
    else
        yad --plug="$KEY" --tabnum=13 \
            --text="inxi non disponible (sudo apt install inxi)" &
    fi
    TAB_PIDS+=($!)

    #### Onglet 14 — Benchmark ####
    # CORRIGÉ : dclick-action via script lanceur /tmp/hyb-bench-run.sh
    # print-column=2 passe la colonne CMD (cachée) au lanceur
    # Chaque entrée de benchmark est un script ou une commande simple
    yad --plug="$KEY" --tabnum=14 \
        --list \
        --dclick-action='/tmp/hyb-bench-run.sh %s' \
        --print-column=2 \
        --no-headers \
        --column="🚀  Double-clic pour lancer" \
        --column="CMD":HD \
        "── CPU ──────────────────────────────────"   "" \
        "🔲  CPU Benchmark (fenêtre dédiée)"          "/tmp/hyb-cpu-bench.sh" \
        "⚡  Sysbench CPU (terminal)"                 "xfce4-terminal -e /tmp/hyb-sysbench-term.sh" \
        "💪  Stress CPU — stress-ng (terminal)"       "xfce4-terminal -e /tmp/hyb-stress-term.sh" \
        "── GPU / OpenGL / Vulkan ────────────────"   "" \
        "🔵  vkcube — Vulkan rotating cube"           "vkcube" \
        "🔷  vkmark — Vulkan benchmark"               "vkmark" \
        "🟢  glxgears — Test OpenGL rapide"           "glxgears" \
        "🟡  glmark2 — OpenGL benchmark"              "glmark2" \
        "🔶  es2gears — OpenGL ES"                    "es2gears_x11" \
        "⛪  Unigine Heaven"                          "$HEAVEN_PATH" \
        &
    TAB_PIDS+=($!)
}

#----------------------------------------------------
# Boucle principale — supporte ⟳ Rafraîchir inxi
# Exit code 10 = rafraîchir (relance tous les onglets + inxi)
# Tout autre code  = fermer
#----------------------------------------------------
while true; do
    KEY=$RANDOM
    TAB_PIDS=()

    launch_tabs "$KEY"

    TXT="<b>Informations matériel — Hybryde System Info V4</b>\n\n"
    TXT+="OS : $(safe_cmd lsb_release -ds) — $(hostname)\n"
    TXT+="Noyau : $(uname -sr)\n"
    TXT+="Disponibilité : $(uptime -p)\n"
    TXT+="Charge CPU :$(uptime | awk -F'load average:' '{print $2}')"

    yad --notebook \
        --window-icon="dialog-information" \
        --width=900 --height=600 \
        --title="Hybryde System Info (V4)" \
        --image="/usr/share/hybryde/logos/hybryde-sm.png" \
        --image-on-top \
        --text="$TXT" \
        --key="$KEY" \
        --tab="CPU" \
        --tab="Mémoire" \
        --tab="Disques" \
        --tab="I/O" \
        --tab="Processus" \
        --tab="Charge" \
        --tab="GPU" \
        --tab="USB" \
        --tab="Réseau" \
        --tab="PCI" \
        --tab="Modules" \
        --tab="Capteurs" \
        --tab="inxi -F" \
        --tab="Benchmark" \
        --active-tab=1 \
        --button="⟳ Rafraîchir inxi:10" \
        --button="Fermer:1"
    EXIT=$?

    # Tuer tous les onglets plug avant de reboucler ou quitter
    for pid in "${TAB_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait "${TAB_PIDS[@]}" 2>/dev/null

    # Code 10 = ⟳ Rafraîchir → reboucler
    [ "$EXIT" -eq 10 ] || break
done

# Nettoyage des scripts temporaires
rm -f /tmp/hyb-cpu-bench.sh \
      /tmp/hyb-sysbench-term.sh \
      /tmp/hyb-stress-term.sh \
      /tmp/hyb-bench-run.sh
