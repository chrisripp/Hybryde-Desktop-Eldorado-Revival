#!/bin/bash

#========================================================================
# hybryde-sysinfo.sh — Informations système multi-onglets (V5)
# Corrections V5 :
#   - inxi     : généré dans un tmpfile (timeout 30s) — plus de pipe direct
#                → supprime l'accumulation de processus inxi et le freeze
#   - Modules  : même pattern, lancé en parallèle pour ne pas bloquer launch_tabs
#   - TMPFILES : liste globale, nettoyée via trap EXIT
#   - Refresh  : kill + sleep + kill -9 sans wait bloquant
#========================================================================

#----------------------------------------------------
# Nettoyage global des fichiers temporaires
#----------------------------------------------------
TMPFILES=()

cleanup_tmpfiles() {
    rm -f "${TMPFILES[@]}" 2>/dev/null
}
trap cleanup_tmpfiles EXIT

new_tmpfile() {
    local f
    f=$(mktemp)
    TMPFILES+=("$f")
    echo "$f"
}

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
HEAVEN_PATH="$HOME/PS4/BENCH/Unigine_Heaven-4.0/heaven"

#----------------------------------------------------
# Création des scripts temporaires pour le benchmark
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
cat > /tmp/hyb-bench-run.sh << RUNEOF
#!/bin/bash
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
esac
RUNEOF
chmod +x /tmp/hyb-bench-run.sh

#----------------------------------------------------
# Killer propre des onglets plug (sans wait bloquant)
#----------------------------------------------------
kill_tabs() {
    local pids=("$@")
    [ "${#pids[@]}" -eq 0 ] && return

    # SIGTERM d'abord
    kill "${pids[@]}" 2>/dev/null

    # Attendre max 2s que les processus meurent
    local deadline=$(( $(date +%s) + 2 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        local alive=0
        for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && { alive=1; break; }
        done
        [ "$alive" -eq 0 ] && break
        sleep 0.2
    done

    # Forcer la mort des récalcitrants
    kill -9 "${pids[@]}" 2>/dev/null

    # Récolter les zombies éventuels (non bloquant)
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null &
    done
}

#----------------------------------------------------
# Lancement de tous les onglets plugs
# $1 = KEY yad courant
# Remplit le tableau global TAB_PIDS
#----------------------------------------------------
launch_tabs() {
    local KEY="$1"
    TAB_PIDS=()

    #-----------------------------------------------------------------
    # FIX FREEZE : générer les contenus lents dans des tmpfiles
    # EN PARALLÈLE dès le début, avant de lancer les yad onglets.
    # On attend leurs PIDs juste avant de lancer les onglets concernés.
    #-----------------------------------------------------------------

    # inxi -F — lancé en arrière-plan avec timeout strict
    local INXI_TMP
    INXI_TMP=$(new_tmpfile)
    local INXI_GEN_PID=0
    if command -v inxi >/dev/null 2>&1; then
        timeout 30 inxi -F > "$INXI_TMP" 2>/dev/null &
        INXI_GEN_PID=$!
    else
        echo "inxi non disponible (sudo apt install inxi)" > "$INXI_TMP"
    fi

    # Modules — lancé en arrière-plan (peut être lent sur certains systèmes)
    local MOD_TMP
    MOD_TMP=$(new_tmpfile)
    local MOD_GEN_PID
    (
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

        local FOUND_INIT=0
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
                zcat "$img" 2>/dev/null | cpio -t 2>/dev/null | grep '\.ko' \
                    || echo "Impossible de lire ou aucun module"
                echo ""
            fi
        done
        [[ $FOUND_INIT -eq 0 ]] && echo "Aucun initramfs trouvé"

        echo ""
        echo "====================================="
        echo "=== Kernel détecté (bzImage) ==="
        echo "====================================="
        echo ""
        for k in /system/boot/bzImage /mnt/sda1/bzImage /boot/vmlinuz*; do
            [[ -f "$k" ]] && echo "Kernel trouvé : $k"
        done

        echo ""
        echo "====================================="
        echo "=== Modules disponibles (/lib/modules) ==="
        echo "====================================="
        echo ""
        if [[ -d /lib/modules/$(uname -r) ]]; then
            find "/lib/modules/$(uname -r)" -name "*.ko" | head -n 80
            echo ""
            echo "(limité à 80 modules)"
        else
            echo "Aucun dossier /lib/modules/$(uname -r)"
        fi

        echo ""
        echo "====================================="
        echo "=== Drivers actifs (lspci -k) ==="
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
    ) > "$MOD_TMP" 2>/dev/null &
    MOD_GEN_PID=$!

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
    # timeout sur glxinfo qui peut bloquer sur certains configs
    {
        safe_cmd lspci | grep -i vga
        timeout 10 glxinfo 2>/dev/null | grep "OpenGL renderer" || true
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

    #### Onglet 11 — Modules ####
    # Attendre la fin de la génération (déjà lancée en parallèle ci-dessus)
    wait "$MOD_GEN_PID" 2>/dev/null
    yad --plug="$KEY" --tabnum=11 \
        --text-info --scroll \
        --width=900 --height=550 \
        --filename="$MOD_TMP" &
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
    # FIX FREEZE : attendre la fin de la génération inxi (lancée en parallèle),
    # puis passer le fichier résultant à yad via --filename.
    # Plus de pipe direct → plus d'accumulation de processus inxi orphelins.
    wait "$INXI_GEN_PID" 2>/dev/null
    yad --plug="$KEY" --tabnum=13 \
        --text="<b>inxi -F</b> — utilisez ⟳ Rafraîchir inxi (bas de fenêtre) pour recharger" \
        --text-info --scroll \
        --width=800 --height=500 \
        --filename="$INXI_TMP" &
    TAB_PIDS+=($!)

    #### Onglet 14 — Benchmark ####
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
# Exit code 10 = rafraîchir
# Tout autre code  = fermer
#----------------------------------------------------
while true; do
    KEY=$RANDOM
    TAB_PIDS=()

    launch_tabs "$KEY"

    TXT="<b>Informations matériel — Hybryde System Info V5</b>\n\n"
    TXT+="OS : $(safe_cmd lsb_release -ds) — $(hostname)\n"
    TXT+="Noyau : $(uname -sr)\n"
    TXT+="Disponibilité : $(uptime -p)\n"
    TXT+="Charge CPU :$(uptime | awk -F'load average:' '{print $2}')"

    yad --notebook \
        --window-icon="dialog-information" \
        --width=900 --height=600 \
        --title="Hybryde System Info (V5)" \
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

    # FIX FREEZE : tuer les onglets plug avec kill_tabs (timeout + kill -9)
    # au lieu de wait bloquant sur des processus potentiellement orphelins
    kill_tabs "${TAB_PIDS[@]}"

    # Code 10 = ⟳ Rafraîchir → reboucler
    [ "$EXIT" -eq 10 ] || break
done

# Nettoyage des scripts temporaires benchmark
rm -f /tmp/hyb-cpu-bench.sh \
      /tmp/hyb-sysbench-term.sh \
      /tmp/hyb-stress-term.sh \
      /tmp/hyb-bench-run.sh

# Les TMPFILES sont nettoyés par le trap EXIT
