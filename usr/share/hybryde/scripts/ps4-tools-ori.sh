#!/bin/bash

#========================================================================
# hybryde-ps4-tools.sh — Hybryde PS4 Tools
# Interface YAD multi-onglets pour outils PS4 Linux
# Version : 1.1 — 2025
# Corrections v1.1 :
#   - Onglet Aide : --list + dclick-action remplacé par --form + BTN
#     (évite l'ouverture parasite de Thunar/sélecteur de fichiers)
#========================================================================

preview_pdf() {
    local FILE="${1/#\~/$HOME}"

    if [ ! -f "$FILE" ]; then
        yad_err "Fichier introuvable :\n<tt>$FILE</tt>"
        return
    fi

    local TMPTXT TMPIMG IMG_FILE
    TMPTXT=$(mktemp)
    TMPIMG=$(mktemp --suffix=.png)

    # Extraire texte (rapide, page 1 seulement)
    if command -v pdftotext >/dev/null 2>&1; then
        pdftotext -l 1 "$FILE" "$TMPTXT" 2>/dev/null
    else
        echo "pdftotext non installé (sudo apt install poppler-utils)" > "$TMPTXT"
    fi

    # Générer aperçu image (page 1)
    if command -v pdftoppm >/dev/null 2>&1; then
        pdftoppm -f 1 -l 1 -png "$FILE" "${TMPIMG%.png}" 2>/dev/null
        IMG_FILE="${TMPIMG%.png}-1.png"
    fi

    yad --title="Aperçu PDF — $(basename "$FILE")" \
        --width=640 --height=480 \
        --center \
        --text-info --scroll \
        --filename="$TMPTXT" \
        ${IMG_FILE:+--image="$IMG_FILE" --image-on-top} \
        --button="📂 Ouvrir dans le lecteur:0" \
        --button="Fermer:1"

    local ret=$?
    rm -f "$TMPTXT" "$TMPIMG"* 2>/dev/null

    # Bouton "Ouvrir" → lancer le lecteur PDF par défaut
    [ $ret -eq 0 ] && xdg-open "$FILE" >/dev/null 2>&1 &
}
export -f preview_pdf


KEY=$RANDOM
LOGO="/usr/share/hybryde/logos/hybryde-sm.png"
CONF_DIR="$HOME/.config/hybryde/ps4tools"
mkdir -p "$CONF_DIR"

#--- Git / Orbis ---
PROJECT_DIR="$HOME/PROJECT-PS4"
KERNELS_DIR="$PROJECT_DIR/kernels"
ORBIS_DIR="$PROJECT_DIR/orbis"
export PROJECT_DIR KERNELS_DIR ORBIS_DIR
mkdir -p "$KERNELS_DIR" "$ORBIS_DIR"
# ── Fichiers d'état inter-dialogs ──────────────────────────────────────
TAR_EXCLUDES_FILE="$CONF_DIR/tar-excludes.txt"
TAR_NAME_FILE="$CONF_DIR/tar-name.txt"
TAR_CMD_FILE="$CONF_DIR/tar-cmd.txt"
IMG_PATH_FILE="$CONF_DIR/img-path.txt"
EXT_SRC_FILE="$CONF_DIR/extract-src.txt"
EXT_DST_FILE="$CONF_DIR/extract-dst.txt"
BUILD_CMD_FILE="$CONF_DIR/build-cmd.txt"

# ── Valeurs par défaut ─────────────────────────────────────────────────
[ ! -f "$TAR_NAME_FILE" ]     && echo "ps4linux.tar.xz" > "$TAR_NAME_FILE"
[ ! -f "$TAR_EXCLUDES_FILE" ] && printf "/var/cache\n"   > "$TAR_EXCLUDES_FILE"
[ ! -f "$BUILD_CMD_FILE" ]    && echo "./mesa-build.py --apt-auto 1 --incremental 0 --git-pull 1 --llvm=off --gallium-drivers=radeonsi,r600 --vulkan-drivers=amd --buildopencl 0" > "$BUILD_CMD_FILE"

# ── Détection du terminal ──────────────────────────────────────────────
TERM_BIN="xterm"
for t in xfce4-terminal gnome-terminal mate-terminal xterm; do
    command -v "$t" &>/dev/null && TERM_BIN="$t" && break
done

#========================================================================
# UTILITAIRES
#========================================================================

run_in_term() {
    local title="$1" cmd="$2"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="$title" -e "bash -c '$cmd; echo; read -rp \"[Entrée pour fermer]\"; exit'" ;;
        gnome-terminal) gnome-terminal --title="$title" -- bash -c "$cmd; echo; read -rp '[Entrée pour fermer]'; exit" ;;
        mate-terminal)  mate-terminal  --title="$title" -e "bash -c '$cmd; echo; read -rp \"[Entrée pour fermer]\"; exit'" ;;
        *)              xterm -title "$title" -e bash -c "$cmd; echo; read -rp '[Entrée pour fermer]'; exit" ;;
    esac
}
export -f run_in_term

run_sudo_in_term() {
    local title="$1" cmd="$2"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="$title" -e "bash -c 'sudo bash -c \"$cmd\"; echo; read -rp \"[Entrée pour fermer]\"; exit'" ;;
        gnome-terminal) gnome-terminal --title="$title" -- bash -c "sudo bash -c \"$cmd\"; echo; read -rp '[Entrée pour fermer]'; exit" ;;
        mate-terminal)  mate-terminal  --title="$title" -e "bash -c 'sudo bash -c \"$cmd\"; echo; read -rp \"[Entrée pour fermer]\"; exit'" ;;
        *)              xterm -title "$title" -e bash -c "sudo bash -c \"$cmd\"; echo; read -rp '[Entrée pour fermer]'; exit" ;;
    esac
}
export -f run_sudo_in_term

yad_err() {
    yad --center --borders=10 --window-icon="dialog-error" \
        --title="Erreur" --image="dialog-error" \
        --text="$1" --button="OK:0" --width=420
}
export -f yad_err

yad_info() {
    yad --center --borders=10 --window-icon="dialog-information" \
        --title="Information" --image="dialog-information" \
        --text="$1" --button="OK:0" --width=500
}
export -f yad_info

yad_confirm() {
    yad --center --borders=10 --window-icon="dialog-question" \
        --title="Confirmation" --image="dialog-question" \
        --text="$1" --button="Non:1" --button="Oui:0" --width=500
}
export -f yad_confirm

export KEY LOGO TERM_BIN CONF_DIR
export TAR_EXCLUDES_FILE TAR_NAME_FILE TAR_CMD_FILE
export IMG_PATH_FILE EXT_SRC_FILE EXT_DST_FILE BUILD_CMD_FILE

#========================================================================
# ONGLET 1 — Compiler Mesa
#========================================================================

do_edit_script() {
    command -v geany &>/dev/null || {
        yad_err "Geany n'est pas installé.\n<b>sudo apt install geany</b>"
        return
    }
    local script
    script=$(yad --center --borders=10 \
        --title="Sélectionner un script à éditer" \
        --file --filename="$HOME/" \
        --file-filter="Scripts | *.sh *.py *.bash *.pl" \
        --button="Annuler:1" --button="Ouvrir dans Geany:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$script" ] && return
    [ ! -f "$script" ] && yad_err "Fichier introuvable." && return
    geany "$script" &
}
export -f do_edit_script

do_patch_mesa() {
    local mesa_dir="$HOME/mesa-git"
    [ ! -d "$mesa_dir" ] && yad_err "Dossier introuvable : <tt>$mesa_dir</tt>\nVérifiez que les sources Mesa sont clonées." && return

    local patch
    patch=$(yad --center --borders=10 \
        --title="Sélectionner le patch Mesa" \
        --file --filename="$mesa_dir/" \
        --file-filter="Patches | *.patch *.diff" \
        --button="Annuler:1" --button="Sélectionner:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$patch" ] && return
    [ ! -f "$patch" ] && yad_err "Fichier patch introuvable." && return

    local pname drylog
    pname=$(basename "$patch")
    drylog="$CONF_DIR/mesa-dryrun.log"

    run_in_term "Dry-run Mesa — $pname" \
        "cd '$mesa_dir' && patch -p1 --dry-run < '$patch' 2>&1 | tee '$drylog'; echo; echo '=== Dry-run terminé ==='; read -rp '[Entrée pour continuer]'"

    yad_confirm "Dry-run terminé.\nLog : <tt>$drylog</tt>\n\nAppliquer le patch <b>$pname</b> au dépôt Mesa ?" || return
    run_in_term "Appliquer patch Mesa — $pname" \
        "cd '$mesa_dir' && patch -p1 < '$patch'"
}
export -f do_patch_mesa

do_patch_libdrm() {
    local drm_dir="$HOME/libdrm-git"
    [ ! -d "$drm_dir" ] && yad_err "Dossier introuvable : <tt>$drm_dir</tt>\nVérifiez que les sources libdrm sont clonées." && return

    local patch
    patch=$(yad --center --borders=10 \
        --title="Sélectionner le patch libdrm" \
        --file --filename="$drm_dir/" \
        --file-filter="Patches | *.patch *.diff" \
        --button="Annuler:1" --button="Sélectionner:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$patch" ] && return
    [ ! -f "$patch" ] && yad_err "Fichier patch introuvable." && return

    local pname drylog
    pname=$(basename "$patch")
    drylog="$CONF_DIR/libdrm-dryrun.log"

    run_in_term "Dry-run libdrm — $pname" \
        "cd '$drm_dir' && patch -p1 --dry-run < '$patch' 2>&1 | tee '$drylog'; echo; echo '=== Dry-run terminé ==='; read -rp '[Entrée pour continuer]'"

    yad_confirm "Dry-run terminé.\nLog : <tt>$drylog</tt>\n\nAppliquer le patch <b>$pname</b> au dépôt libdrm ?" || return
    run_in_term "Appliquer patch libdrm — $pname" \
        "cd '$drm_dir' && patch -p1 < '$patch'"
}
export -f do_patch_libdrm

do_build_mesa() {
    local build_script="$HOME/mesa-build.py"
    [ ! -f "$build_script" ] && yad_err "Script introuvable : <tt>$build_script</tt>" && return
    run_in_term "Build Mesa" "cd '$HOME/mesa-git' && ./mesa-build.py"
}
export -f do_build_mesa

do_manual_build() {
    local last_cmd
    last_cmd=$(cat "$BUILD_CMD_FILE" 2>/dev/null)
    [ -z "$last_cmd" ] && last_cmd="./mesa-build.py"

    local out
    out=$(yad --center --borders=10 \
        --title="Commande manuelle Mesa" \
        --form \
        --text="<b>Commande de build Mesa</b>\n\nLe répertoire de travail sera : <tt>~/mesa-git</tt>\nModifiez la commande puis cliquez sur Lancer.\n" \
        --field="Commande :":TEXT "$last_cmd" \
        --button="Annuler:1" --button="🚀 Lancer:0" \
        --width=840 --height=220)
    [ $? -ne 0 ] || [ -z "$out" ] && return

    local cmd
    cmd=$(echo "$out" | cut -d'|' -f1)
    echo "$cmd" > "$BUILD_CMD_FILE"
    run_in_term "Build Mesa (manuel)" "cd '$HOME/mesa-git' && $cmd"
}
export -f do_manual_build

tab_mesa() {
    yad --plug="$KEY" --tabnum=1 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Download Manager.png" --image-on-top \
        --text="<big><b>🔧 Compiler Mesa</b></big>
Outils pour patcher et compiler Mesa / libdrm pour PS4 Linux.
Sources attendues dans <tt>~/mesa-git</tt>  et  <tt>~/libdrm-git</tt>.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Édition de script —</b>":LBL "" \
        --field="  Ouvrir un script dans Geany":BTN 'bash -c "do_edit_script"' \
        \
        --field="":LBL "" \
        --field="<b>— Patch Mesa  (~/mesa-git) —</b>":LBL "" \
        --field="  Rechercher et appliquer un .patch Mesa":BTN 'bash -c "do_patch_mesa"' \
        \
        --field="":LBL "" \
        --field="<b>— Patch libdrm  (~/libdrm-git) —</b>":LBL "" \
        --field="  Rechercher et appliquer un .patch libdrm":BTN 'bash -c "do_patch_libdrm"' \
        \
        --field="":LBL "" \
        --field="<b>— Compilation —</b>":LBL "" \
        --field="  Build Mesa  (./mesa-build.py)":BTN 'bash -c "do_build_mesa"' \
        --field="  Commande manuelle (éditable avant lancement)":BTN 'bash -c "do_manual_build"' \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# ONGLET 2 — Créer un tar.xz
#========================================================================

do_tar_set_name() {
    local cur
    cur=$(cat "$TAR_NAME_FILE" 2>/dev/null || echo "ps4linux.tar.xz")
    local out
    out=$(yad --center --borders=10 \
        --title="Nom du tar.xz" \
        --form \
        --text="Entrez le nom du fichier tar.xz :" \
        --field="Nom du fichier :":TEXT "$cur" \
        --button="Annuler:1" --button="Valider:0" \
        --width=520)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local name
    name=$(echo "$out" | cut -d'|' -f1)
    echo "$name" > "$TAR_NAME_FILE"
    yad_info "✓ Nom défini : <b>$name</b>\nEmplacement final : <tt>/$name</tt>"
}
export -f do_tar_set_name

do_tar_add_exclude() {
    local out
    out=$(yad --center --borders=10 \
        --title="Ajouter une exclusion" \
        --form \
        --text="Entrez un chemin à exclure du tar.xz :\n(ex: <tt>/var/cache</tt>  <tt>/proc</tt>  <tt>/tmp</tt>)" \
        --field="Chemin à exclure :":TEXT "/var/cache" \
        --button="Annuler:1" --button="Ajouter:0" \
        --width=540)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local entry
    entry=$(echo "$out" | cut -d'|' -f1)
    [ -z "$entry" ] && return
    echo "$entry" >> "$TAR_EXCLUDES_FILE"
    yad_info "✓ Exclusion ajoutée : <tt>$entry</tt>"
}
export -f do_tar_add_exclude

do_tar_del_exclude() {
    [ ! -f "$TAR_EXCLUDES_FILE" ] && yad_info "La liste d'exclusions est vide." && return
    local items=()
    while IFS= read -r line; do
        [ -n "$line" ] && items+=("$line")
    done < "$TAR_EXCLUDES_FILE"
    [ "${#items[@]}" -eq 0 ] && yad_info "La liste d'exclusions est vide." && return

    local sel
    sel=$(yad --center --borders=10 \
        --title="Supprimer une exclusion" \
        --list \
        --text="Sélectionnez l'entrée à supprimer :" \
        --column="Chemin à exclure" \
        "${items[@]}" \
        --print-column=1 --separator="" \
        --button="Annuler:1" --button="Supprimer:0" \
        --width=520 --height=360)
    [ $? -ne 0 ] || [ -z "$sel" ] && return
    local escaped="${sel//\//\\/}"
    sed -i "/^${escaped}$/d" "$TAR_EXCLUDES_FILE"
    yad_info "✓ Supprimé : <tt>$sel</tt>"
}
export -f do_tar_del_exclude

do_tar_show_excludes() {
    local content
    content=$(cat "$TAR_EXCLUDES_FILE" 2>/dev/null || echo "(liste vide)")
    yad --center --borders=10 \
        --title="Exclusions actuelles" \
        --text-info \
        --width=540 --height=340 \
        --button="Fermer:0" \
        <<< "$content"
}
export -f do_tar_show_excludes

do_tar_generate() {
    local tarname
    tarname=$(cat "$TAR_NAME_FILE" 2>/dev/null || echo "ps4linux.tar.xz")

    local excludes="--exclude=/$tarname"
    if [ -f "$TAR_EXCLUDES_FILE" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && excludes+=" --exclude=$line"
        done < "$TAR_EXCLUDES_FILE"
    fi

    local cmd="sudo tar -cvf /$tarname $excludes --one-file-system / -I \"xz -9\""
    echo "$cmd" > "$TAR_CMD_FILE"

    yad_info "<b>Commande générée :</b>\n\n<tt>$cmd</tt>\n\n📦 Fichier final : <tt>/$tarname</tt>\n\nCliquez sur <b>🚀 Lancer la création</b> pour exécuter."
}
export -f do_tar_generate

do_tar_run() {
    [ ! -f "$TAR_CMD_FILE" ] && yad_err "Aucune commande générée.\nCliquez d'abord sur <b>Générer la commande</b>." && return
    local cmd tarname
    cmd=$(cat "$TAR_CMD_FILE")
    tarname=$(cat "$TAR_NAME_FILE" 2>/dev/null || echo "ps4linux.tar.xz")

    yad_confirm "Lancer la création de l'archive ?\n\n<tt>$cmd</tt>\n\n📦 Résultat : <tt>/$tarname</tt>\n\n⚠️  Cette opération peut prendre <b>plusieurs heures</b>." || return
    run_in_term "Création tar.xz PS4" "$cmd"
}
export -f do_tar_run

tab_tar_create() {
    yad --plug="$KEY" --tabnum=2 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/WinZip 1.png" --image-on-top \
        --text="<big><b>📦 Créer un tar.xz</b></big>
Commande : <tt>sudo tar -cvf /[nom] --exclude=... --one-file-system / -I \"xz -9\"</tt>
Le tar.xz sera créé à la <b>racine /</b> du système.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Nom du fichier tar.xz —</b>":LBL "" \
        --field="  Nom actuel :  $(cat "$TAR_NAME_FILE" 2>/dev/null || echo "ps4linux.tar.xz")":LBL "" \
        --field="  Modifier le nom":BTN 'bash -c "do_tar_set_name"' \
        \
        --field="":LBL "" \
        --field="<b>— Exclusions (--exclude) —</b>":LBL "" \
        --field="  Ajouter un chemin à exclure":BTN 'bash -c "do_tar_add_exclude"' \
        --field="  Supprimer une exclusion":BTN 'bash -c "do_tar_del_exclude"' \
        --field="  Voir la liste des exclusions":BTN 'bash -c "do_tar_show_excludes"' \
        \
        --field="":LBL "" \
        --field="<b>— Génération et lancement —</b>":LBL "" \
        --field="  Générer la commande finale":BTN 'bash -c "do_tar_generate"' \
        --field="  🚀 Lancer la création du tar.xz":BTN 'bash -c "do_tar_run"' \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# ONGLET 3 — Créer un .img
#========================================================================

IMG_SRC_PART_FILE="$CONF_DIR/img-src-partition.txt"
IMG_DST_DIR_FILE="$CONF_DIR/img-dst-dir.txt"
IMG_NAME_FILE2="$CONF_DIR/img-name.txt"
export IMG_SRC_PART_FILE IMG_DST_DIR_FILE IMG_NAME_FILE2

do_img_select_partition() {
    local parts=()
    while IFS= read -r line; do
        local dev size fstype mountpoint
        dev=$(echo "$line"        | awk '{print $1}')
        size=$(echo "$line"       | awk '{print $2}')
        fstype=$(echo "$line"     | awk '{print $3}')
        mountpoint=$(echo "$line" | awk '{print $4}')
        [ -z "$dev" ] && continue
        parts+=("/dev/$dev" "${size}  |  ${fstype:-—}  |  ${mountpoint:-—}")
    done < <(lsblk -ln -o NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null \
             | awk 'NF>=1 {print}' \
             | grep -v "^loop")

    if [ "${#parts[@]}" -eq 0 ]; then
        yad_err "Aucune partition détectée.\nVérifiez que le disque est connecté (<tt>lsblk</tt>)."
        return
    fi

    local sel
    sel=$(yad --center --borders=10 \
        --title="Sélectionner la partition source" \
        --list \
        --text="<b>Sélectionnez la partition à sauvegarder en .img</b>\n\n⚠️  Idéalement, la partition ne doit <b>pas être montée</b> pour une image cohérente." \
        --column="Partition" \
        --column="Taille  |  FS  |  Point de montage" \
        "${parts[@]}" \
        --print-column=1 --separator="" \
        --button="Annuler:1" --button="Sélectionner:0" \
        --width=700 --height=440)
    [ $? -ne 0 ] || [ -z "$sel" ] && return
    sel="${sel//|/}"
    echo "$sel" > "$IMG_SRC_PART_FILE"
    yad_info "✓ Partition source sélectionnée :\n<tt>$sel</tt>"
}
export -f do_img_select_partition

do_img_select_dst() {
    local d
    d=$(yad --center --borders=10 \
        --title="Sélectionner le dossier de destination" \
        --file --directory --filename="$HOME/" \
        --button="Annuler:1" --button="Sélectionner:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$d" ] && return
    echo "$d" > "$IMG_DST_DIR_FILE"
    yad_info "✓ Dossier de destination :\n<tt>$d</tt>"
}
export -f do_img_select_dst

do_img_set_name() {
    local cur
    cur=$(cat "$IMG_NAME_FILE2" 2>/dev/null || echo "ps4linux-partition.img")
    local out
    out=$(yad --center --borders=10 \
        --title="Nom du fichier .img" \
        --form \
        --text="Entrez le nom du fichier image à créer :" \
        --field="Nom du fichier .img :":TEXT "$cur" \
        --button="Annuler:1" --button="Valider:0" \
        --width=520)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local name
    name=$(echo "$out" | cut -d'|' -f1)
    echo "$name" > "$IMG_NAME_FILE2"
    yad_info "✓ Nom défini : <b>$name</b>"
}
export -f do_img_set_name

do_img_show_sel() {
    local src dst name
    src=$(cat "$IMG_SRC_PART_FILE" 2>/dev/null || echo "— non sélectionné —")
    dst=$(cat "$IMG_DST_DIR_FILE"  2>/dev/null || echo "— non sélectionné —")
    name=$(cat "$IMG_NAME_FILE2"   2>/dev/null || echo "ps4linux-partition.img")
    yad_info "<b>Sélection actuelle :</b>\n\n  💽 Partition source : <tt>$src</tt>\n  📂 Dossier dest.    : <tt>$dst</tt>\n  📄 Nom du fichier   : <b>$name</b>\n\n🗂 Fichier final : <tt>$dst/$name</tt>"
}
export -f do_img_show_sel

do_img_create() {
    local src dst name
    src=$(cat "$IMG_SRC_PART_FILE" 2>/dev/null)
    dst=$(cat "$IMG_DST_DIR_FILE"  2>/dev/null)
    name=$(cat "$IMG_NAME_FILE2"   2>/dev/null || echo "ps4linux-partition.img")

    [ -z "$src" ] && yad_err "Aucune partition source sélectionnée.\nCliquez sur <b>① Sélectionner la partition</b>." && return
    [ ! -b "$src" ] && yad_err "Périphérique bloc introuvable :\n<tt>$src</tt>\nVérifiez que le disque est connecté." && return
    [ -z "$dst" ] && yad_err "Aucun dossier de destination sélectionné.\nCliquez sur <b>② Sélectionner le dossier</b>." && return
    [ ! -d "$dst" ] && yad_err "Dossier introuvable :\n<tt>$dst</tt>" && return

    local imgpath="$dst/$name"

    local part_size_human part_size_bytes avail_bytes space_warn=""
    part_size_human=$(lsblk -no SIZE "$src" 2>/dev/null | head -1 | tr -d ' ')
    part_size_bytes=$(lsblk -bno SIZE "$src" 2>/dev/null | head -1 | tr -d ' ')
    avail_bytes=$(df -B1 --output=avail "$dst" 2>/dev/null | tail -1 | tr -d ' ')

    if [ -n "$part_size_bytes" ] && [ -n "$avail_bytes" ]; then
        if [ "$avail_bytes" -lt "$part_size_bytes" ]; then
            local avail_human
            avail_human=$(df -h --output=avail "$dst" 2>/dev/null | tail -1 | tr -d ' ')
            space_warn="\n\n⚠️  <b>Espace insuffisant !</b>\n  Requis     : $part_size_human\n  Disponible : $avail_human"
        fi
    fi

    local cmd="sudo dd if='$src' of='$imgpath' bs=4M status=progress conv=fsync"

    yad_confirm "Créer l'image complète de la partition ?\n\n  💽 Source  : <tt>$src</tt>  ($part_size_human)\n  📄 Image   : <tt>$imgpath</tt>\n\nCommande :\n<tt>$cmd</tt>${space_warn}\n\n⏱  Cette opération peut prendre plusieurs minutes." || return

    echo "$imgpath" > "$IMG_PATH_FILE"
    run_sudo_in_term "Sauvegarde partition → .img" \
        "dd if='$src' of='$imgpath' bs=4M status=progress conv=fsync && echo '' && echo '✓ Image créée :' && ls -lh '$imgpath' || echo '✗ Erreur dd'"
}
export -f do_img_create

do_img_show_path() {
    local p
    p=$(cat "$IMG_PATH_FILE" 2>/dev/null)
    if [ -n "$p" ]; then
        local info
        info=$(ls -lh "$p" 2>/dev/null || echo "(fichier introuvable)")
        yad_info "Dernier .img créé :\n\n<tt>$p</tt>\n\n$info"
    else
        yad_info "Aucun .img créé pour l'instant."
    fi
}
export -f do_img_show_path

tab_img_create() {
    yad --plug="$KEY" --tabnum=3 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Zip.png" --image-on-top \
        --text="<big><b>💿 Créer une image .img</b></big>
Sauvegarde complète d'une partition via <tt>dd</tt>.
Commande : <tt>sudo dd if=[partition] of=[fichier.img] bs=4M status=progress conv=fsync</tt>\n" \
        \
        --field="":LBL "" \
        --field="<b>— Source et destination —</b>":LBL "" \
        --field="  ① Sélectionner la partition à sauvegarder":BTN 'bash -c "do_img_select_partition"' \
        --field="  ② Sélectionner le dossier de destination":BTN 'bash -c "do_img_select_dst"' \
        --field="  ③ Modifier le nom du fichier .img":BTN 'bash -c "do_img_set_name"' \
        --field="  Voir la sélection actuelle":BTN 'bash -c "do_img_show_sel"' \
        \
        --field="":LBL "" \
        --field="<b>— Sauvegarde —</b>":LBL "" \
        --field="  🚀 Créer l'image .img de la partition (dd)":BTN 'bash -c "do_img_create"' \
        \
        --field="":LBL "" \
        --field="<b>— Informations —</b>":LBL "" \
        --field="  Voir l'emplacement du dernier .img créé":BTN 'bash -c "do_img_show_path"' \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# ONGLET 4 — Décompresser un tar.xz
#========================================================================

do_ext_select_src() {
    local f
    f=$(yad --center --borders=10 \
        --title="Sélectionner l'archive tar.xz" \
        --file --filename="$HOME/" \
        --file-filter="Archives tar.xz | *.tar.xz *.tar" \
        --button="Annuler:1" --button="Sélectionner:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$f" ] && return
    echo "$f" > "$EXT_SRC_FILE"
    yad_info "✓ Archive sélectionnée :\n<tt>$f</tt>"
}
export -f do_ext_select_src

do_ext_select_dst() {
    local d
    d=$(yad --center --borders=10 \
        --title="Sélectionner la partition de destination" \
        --file --directory --filename="/media/$USER/" \
        --button="Annuler:1" --button="Sélectionner:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$d" ] && return
    echo "$d" > "$EXT_DST_FILE"
    yad_info "✓ Destination sélectionnée :\n<tt>$d</tt>"
}
export -f do_ext_select_dst

do_ext_show_sel() {
    local src dst
    src=$(cat "$EXT_SRC_FILE" 2>/dev/null || echo "— non sélectionné —")
    dst=$(cat "$EXT_DST_FILE" 2>/dev/null || echo "— non sélectionné —")
    yad_info "<b>Sélection actuelle :</b>\n\n  📁 Archive      : <tt>$src</tt>\n  📂 Destination  : <tt>$dst</tt>"
}
export -f do_ext_show_sel

do_ext_run() {
    local src dst
    src=$(cat "$EXT_SRC_FILE" 2>/dev/null)
    dst=$(cat "$EXT_DST_FILE" 2>/dev/null)

    [ -z "$src" ] && yad_err "Aucune archive sélectionnée.\nCliquez sur <b>① Sélectionner l'archive</b>." && return
    [ ! -f "$src" ] && yad_err "Fichier introuvable :\n<tt>$src</tt>" && return
    [ -z "$dst" ] && yad_err "Aucune destination sélectionnée.\nCliquez sur <b>② Sélectionner la partition</b>." && return

    local cmd="sudo tar -xvJpf '$src' -C '$dst' --numeric-owner"

    yad_confirm "Lancer l'extraction ?\n\n  📁 Archive     : <tt>$(basename "$src")</tt>\n  📂 Destination : <tt>$dst</tt>\n\n<tt>$cmd</tt>\n\n⚠️  Cette opération peut prendre un long moment." || return

    run_in_term "Décompression tar.xz PS4" "$cmd"
}
export -f do_ext_run

tab_tar_extract() {
    yad --plug="$KEY" --tabnum=4 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Downloads 2.png" --image-on-top \
        --text="<big><b>📂 Décompresser un tar.xz</b></big>
Commande : <tt>sudo tar -xvJpf [archive] -C [partition] --numeric-owner</tt>\n" \
        \
        --field="":LBL "" \
        --field="<b>— Sélection —</b>":LBL "" \
        --field="  ① Sélectionner l'archive tar.xz":BTN 'bash -c "do_ext_select_src"' \
        --field="  ② Sélectionner la partition de destination":BTN 'bash -c "do_ext_select_dst"' \
        --field="  Voir la sélection actuelle":BTN 'bash -c "do_ext_show_sel"' \
        \
        --field="":LBL "" \
        --field="<b>— Extraction —</b>":LBL "" \
        --field="  🚀 Lancer l'extraction":BTN 'bash -c "do_ext_run"' \
        \
        "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# ONGLET 5 — Monter le SSD PS4 (VERSION SIMPLE)
#========================================================================

PS4_KEY="/key/eap_hdd_key.bin"
PS4_DEV="/dev/sda27"
PS4_MNT="/ps4hdd"

# ── Montage Belize / Aeolia ───────────────────────────────────────────
do_mount_ps4_belize() {
    xterm -hold -e bash -c "
echo '--- Montage PS4 Belize / Aeolia ---'
echo ''
echo '--- cryptsetup ---'
sudo cryptsetup -d /key/eap_hdd_key.bin --cipher aes-xts-plain64 -s 256 --offset 0 --skip 111669149696 create ps4hdd /dev/sd?27
sudo mount -t ufs -o ufstype=ufs2 /dev/mapper/ps4hdd /ps4hdd
sudo chmod -R a+rwX /ps4hdd

echo ''
echo 'OK → SSD monté sur $PS4_MNT'
cd /ps4hdd
ls 
read -p 'Entrée... Vous pouvez fermer ce terminal, vous pouvez utiliser votre explorateur de fichier, dossier /ps4hdd'
"
}

# ── Montage Baikal ────────────────────────────────────────────────────
do_mount_ps4_baikal() {
    xterm -hold -e bash -c "
echo '--- Montage PS4 Baikal ---'
echo ''
echo '--- cryptsetup ---'
sudo cryptsetup -d $PS4_KEY --cipher aes-xts-plain64 -s 256 --offset 0 create ps4hdd $PS4_DEV
sudo mount -t ufs -o ufstype=ufs2 /dev/mapper/ps4hdd $PS4_MNT
sudo chmod -R a+rwX $PS4_MNT

echo ''
echo 'OK → SSD monté sur $PS4_MNT'
cd /ps4hdd
ls 
read -p 'Entrée... Vous pouvez fermer ce terminal, vous pouvez utiliser votre explorateur de fichier, dossier /ps4hdd'
"
}

# ── Démontage ─────────────────────────────────────────────────────────
do_unmount_ps4() {
    xterm -hold -e bash -c "
echo '--- Démontage SSD PS4 ---'
echo ''

sudo umount $PS4_MNT 2>/dev/null
sudo cryptsetup remove ps4hdd 2>/dev/null

echo 'OK → démonté'
read -p 'Entrée...'
"
}

# ── Interface YAD ─────────────────────────────────────────────────────
tab_mount_ps4() {
    yad --plug="$KEY" --tabnum=5 \
        --form \
        --text="<b>SSD PS4 — Montage rapide</b>

Clé : <tt>$PS4_KEY</tt>
Partition : <tt>$PS4_DEV</tt>
Montage : <tt>$PS4_MNT</tt>
" \
        --field="🚀 Monter SSD (Belize / Aeolia)":BTN 'bash -c do_mount_ps4_belize' \
        --field="🚀 Monter SSD (Baikal)":BTN 'bash -c do_mount_ps4_baikal' \
        --field="⏏ Démonter SSD":BTN 'bash -c do_unmount_ps4' \
        "" "" "" "" "" "" &
}

export -f do_mount_ps4_belize
export -f do_mount_ps4_baikal
export -f do_unmount_ps4
export -f tab_mount_ps4

#========================================================================
# ONGLET 6 — Aide (10 documents configurables)
#
# CORRECTION v1.1 : l'ancienne approche --list + --dclick-action ouvrait
# un sélecteur de fichiers yad (Thunar) au lieu du PDF.
# Nouvelle approche : --form avec BTN par document → appel direct à
# preview_pdf (aperçu) ou xdg-open (lecteur par défaut).
# Les chemins sont expansés à la génération du plug (pas dans un sous-shell)
# donc pas de problème de portée variable.
#
# ─── Modifiez les noms et chemins ici ──────────────────────────────────
#========================================================================

AIDE_LABELS=(
    "Create a Multiboot SSD"      # bouton 1
    "Active Zram"             # bouton 2
    "TRANSFORM YOUR PS4 INTO A WII" # bouton 3
    "A developer in your terminal" # bouton 4
    "CUSTOM BASH"             # bouton 5
    "Update mesa"             # bouton 6
    "Doc PS4 Linux 7"             # bouton 7
    "Doc PS4 Linux 8"             # bouton 8
    "Doc PS4 Linux 9"             # bouton 9
    "Doc PS4 Linux 10"            # bouton 10
)

AIDE_PATHS=(
    "$HOME/Documents/Create a Multiboot SSD2.pdf"   # 1
    "$HOME/Documents/zram-forky-trixie-kali-fat-2G.txt"   # 2
    "$HOME/Documents/TRANSFORM YOUR PS4 INTO A WII.pdf"   # 3
    "$HOME/Documents/A developer in your terminal.pdf"   # 4
    "$HOME/Documents/CUSTOM BASH.pdf"   # 5
    "$HOME/Documents/Mettre a jour Les Distributions TRIKI1.pdf"   # 6
    "$HOME/Documents/MOUNT-hdd-intern-ps4.pdf"   # 7
    "$HOME/Documents/MOUNT-hdd-intern-ps4.pdf"   # 8
    "$HOME/Documents/MOUNT-hdd-intern-ps4.pdf"   # 9
    "$HOME/Documents/MOUNT-hdd-intern-ps4.pdf"   # 10
)
# ────────────────────────────────────────────────────────────────────────

tab_aide() {
    # Construire les champs --form dynamiquement
    # Chaque document → un séparateur LBL + deux BTN (Aperçu / Ouvrir)
    # Les chemins sont expansés ICI (dans le shell principal) et passés
    # littéralement dans les actions BTN entre guillemets simples échappés.
    local fields=()

    for i in "${!AIDE_LABELS[@]}"; do
        local lbl="${AIDE_LABELS[$i]}"
        local fpath="${AIDE_PATHS[$i]}"
        # Expansion ~ → $HOME si présent
        fpath="${fpath/#\~/$HOME}"

        fields+=(
            --field="":LBL ""
            --field="<b>  📄 ${lbl}</b>":LBL ""
            # Bouton Aperçu : appelle preview_pdf avec le chemin littéral
            --field="     🔍 Aperçu":BTN "bash -c \"preview_pdf '${fpath}'\""
            # Bouton Ouvrir : appelle xdg-open directement, sans passer par yad --file
            --field="     📂 Ouvrir dans le lecteur PDF":BTN "bash -c \"xdg-open '${fpath}' >/dev/null 2>&1 &\""
        )
    done

    # Padding pour pousser les champs vers le haut dans la zone scrollable
    local pad=()
    for _ in $(seq 1 6); do pad+=("" "" "" ""); done

    yad --plug="$KEY" --tabnum=6 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Notepad 4.png" \
        --image-on-top \
        --text="<big><b>📖 Aide PS4 Linux</b></big>
<small>🔍 Aperçu = texte page 1 + bouton lecteur  •  📂 Ouvrir = lecteur PDF direct</small>\n" \
        "${fields[@]}" \
        "${pad[@]}" \
        &
}

#========================================================================
# ONGLET 7 — Réseau / Transfert
#========================================================================

do_net_scan() {
    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-netscan-XXXX.sh)
    cat > "$tmpscript" << 'EOF'
#!/bin/bash
echo "=== Scan réseau local (nmap -sn) ==="
echo ""
if ! command -v nmap >/dev/null 2>&1; then
    echo "ERREUR : nmap non installé"
    echo "  sudo apt install nmap"
    read -rp "[Entrée pour fermer]"
    exit 1
fi
SUBNET=$(ip route | awk '/scope link/ {print $1}' | head -1)
echo "Sous-réseau détecté : $SUBNET"
echo ""
nmap -sn "$SUBNET" 2>/dev/null | grep -E "Nmap scan|Host is up|report for"
echo ""
read -rp "[Entrée pour fermer]"
EOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="Scan réseau" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="Scan réseau" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="Scan réseau" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "Scan réseau" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_net_scan

do_rsync_to_ps4hdd() {
    local src
    src=$(yad --center --borders=10 \
        --title="Sélectionner le dossier source à copier" \
        --file --directory --filename="$HOME/" \
        --button="Annuler:1" --button="Sélectionner:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$src" ] && return

    local dst
    dst=$(yad --center --borders=10 \
        --title="Destination sur /ps4hdd" \
        --form \
        --text="Dossier destination sur /ps4hdd :" \
        --field="Chemin destination :":TEXT "/ps4hdd/game/" \
        --button="Annuler:1" --button="Valider:0" \
        --width=540)
    [ $? -ne 0 ] || [ -z "$dst" ] && return
    dst=$(echo "$dst" | cut -d'|' -f1)

    yad_confirm "Lancer le transfert rsync ?\n\n  Source : <tt>$src</tt>\n  Dest   : <tt>$dst</tt>\n\n⚠️  Peut prendre plusieurs minutes selon la taille." || return

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-rsync-XXXX.sh)
    printf '#!/bin/bash\nrsync -av --progress "%s" "%s"\necho ""\nread -rp "[Entrée pour fermer]"\n' "$src" "$dst" > "$tmpscript"
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="rsync vers ps4hdd" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="rsync vers ps4hdd" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="rsync vers ps4hdd" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "rsync vers ps4hdd" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_rsync_to_ps4hdd

do_ssh_ps4() {
    local out
    out=$(yad --center --borders=10 \
        --title="SSH vers PS4" \
        --form \
        --text="<b>Connexion SSH vers la PS4</b>" \
        --field="Adresse IP PS4 :":TEXT "192.168.1.xxx" \
        --field="Utilisateur :":TEXT "root" \
        --field="Port SSH :":NUM "22!1..65535!1" \
        --button="Annuler:1" --button="Connecter:0" \
        --width=460)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local ip user port
    ip=$(echo "$out"   | cut -d'|' -f1)
    user=$(echo "$out" | cut -d'|' -f2)
    port=$(echo "$out" | cut -d'|' -f3)

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-ssh-XXXX.sh)
    printf '#!/bin/bash\necho "Connexion SSH : %s@%s:%s"\nssh -p "%s" "%s@%s"\nread -rp "[Entrée pour fermer]"\n' \
        "$user" "$ip" "$port" "$port" "$user" "$ip" > "$tmpscript"
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="SSH PS4 — $ip" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="SSH PS4 — $ip" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="SSH PS4 — $ip" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "SSH PS4 — $ip" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_ssh_ps4

tab_reseau() {
    yad --plug="$KEY" --tabnum=7 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/My Network Places 7.png" --image-on-top \
        --text="<big><b>🌐 Réseau / Transfert</b></big>
Scan réseau, transfert de fichiers vers /ps4hdd, connexion SSH.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Réseau local —</b>":LBL "" \
        --field="  🔍 Scanner le réseau local (nmap)":BTN 'bash -c "do_net_scan"' \
        \
        --field="":LBL "" \
        --field="<b>— Transfert de fichiers —</b>":LBL "" \
        --field="  📁 Copier un dossier vers /ps4hdd (rsync)":BTN 'bash -c "do_rsync_to_ps4hdd"' \
        \
        --field="":LBL "" \
        --field="<b>— Accès distant —</b>":LBL "" \
        --field="  🖥  Connexion SSH vers la PS4":BTN 'bash -c "do_ssh_ps4"' \
        \
        "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# ONGLET 8 — Diagnostic / Logs
#========================================================================

do_diag_prereqs() {
    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-prereqs-XXXX.sh)
    cat > "$tmpscript" << 'EOF'
#!/bin/bash
ok()   { printf "  \e[32m✓\e[0m %-28s %s\n" "$1" "$2"; }
warn() { printf "  \e[33m⚠\e[0m  %-28s %s\n" "$1" "$2"; }
fail() { printf "  \e[31m✗\e[0m %-28s %s\n" "$1" "$2"; }

chk() {
    local pkg="$1" cmd="${2:-$1}" label="${3:-$1}"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$label" "($(command -v "$cmd"))"
    else
        fail "$label" "→ sudo apt install $pkg"
    fi
}

echo "=== Prérequis PS4 Linux ==="
echo ""
chk cryptsetup    cryptsetup    "cryptsetup"
chk ufsutils      ufs_util      "ufsutils (ufs_util)"
chk rsync         rsync         "rsync"
chk nmap          nmap          "nmap"
chk mesa-vulkan-drivers vulkaninfo "vulkan (vulkaninfo)"
chk git           git           "git"
chk python3       python3       "python3"
chk clang         clang         "clang (LTO kernel)"
chk lld           ld.lld        "lld (linker LTO)"
chk llvm          llvm-ar       "llvm-ar"
chk make          make          "make"

echo ""
echo "=== Vulkan ==="
if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverVersion|apiVersion" | head -6
else
    warn "vulkaninfo" "non disponible"
fi

echo ""
echo "=== Driver GPU actif ==="
lspci -k 2>/dev/null | grep -A2 "VGA" | head -6

echo ""
echo "=== Mesa version ==="
if command -v glxinfo >/dev/null 2>&1; then
    glxinfo 2>/dev/null | grep -i "OpenGL version\|renderer" | head -3
else
    warn "glxinfo" "non disponible (sudo apt install mesa-utils)"
fi

echo ""
read -rp "[Entrée pour fermer]"
EOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="Diagnostic Prérequis" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="Diagnostic Prérequis" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="Diagnostic Prérequis" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "Diagnostic Prérequis" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_diag_prereqs

do_dmesg_live() {
    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-dmesg-XXXX.sh)
    cat > "$tmpscript" << 'EOF'
#!/bin/bash
echo "=== dmesg temps réel — filtre USB/SCSI/DRM/amdgpu ==="
echo "Ctrl+C pour arrêter"
echo ""
sudo dmesg -w 2>/dev/null | grep --line-buffered -iE "usb|scsi|sd[a-z]|drm|amdgpu|radeon|cryptsetup|ufs|ps4"
EOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="dmesg live" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="dmesg live" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="dmesg live" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "dmesg live" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_dmesg_live

do_cryptsetup_status() {
    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-cstatus-XXXX.sh)
    cat > "$tmpscript" << 'EOF'
#!/bin/bash
echo "=== cryptsetup status ps4hdd ==="
echo ""
sudo cryptsetup status ps4hdd 2>/dev/null || echo "(mapping ps4hdd inactif)"
echo ""
echo "=== mount | grep ps4 ==="
mount 2>/dev/null | grep -E "ps4|ufs" || echo "(rien monté)"
echo ""
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null
echo ""
read -rp "[Entrée pour fermer]"
EOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="État SSD PS4" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="État SSD PS4" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="État SSD PS4" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "État SSD PS4" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_cryptsetup_status

tab_diagnostic() {
    yad --plug="$KEY" --tabnum=8 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Clock 3.png" --image-on-top \
        --text="<big><b>🔍 Diagnostic / Logs</b></big>
Vérification prérequis, logs kernel en temps réel, état du SSD PS4.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Prérequis système —</b>":LBL "" \
        --field="  ✅ Vérifier tous les prérequis PS4 Linux":BTN 'bash -c "do_diag_prereqs"' \
        \
        --field="":LBL "" \
        --field="<b>— Logs kernel —</b>":LBL "" \
        --field="  📋 dmesg temps réel (USB / DRM / amdgpu)":BTN 'bash -c "do_dmesg_live"' \
        \
        --field="":LBL "" \
        --field="<b>— État SSD PS4 —</b>":LBL "" \
        --field="  💽 cryptsetup status + mount + lsblk":BTN 'bash -c "do_cryptsetup_status"' \
        \
        "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# ONGLET 9 — Variables d'environnement Mesa
#========================================================================

MESA_ENV_FILE="$CONF_DIR/mesa-env.conf"
MESA_PROFILES_DIR="$CONF_DIR/mesa-profiles"
mkdir -p "$MESA_PROFILES_DIR"
export MESA_ENV_FILE MESA_PROFILES_DIR

# Profil par défaut si absent
[ ! -f "$MESA_ENV_FILE" ] && cat > "$MESA_ENV_FILE" << 'ENVEOF'
RADV_DEBUG=
MESA_DEBUG=
AMD_DEBUG=
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
mesa_glthread=true
RADV_PERFTEST=
ENVEOF

do_mesa_edit_env() {
    local out
    # Lire le fichier courant
    source "$MESA_ENV_FILE" 2>/dev/null

    out=$(yad --center --borders=10 \
        --title="Variables Mesa" \
        --form \
        --text="<b>Variables d'environnement Mesa/Vulkan</b>\n<small>Laisser vide = non exporté</small>\n" \
        --field="RADV_DEBUG :":TEXT "${RADV_DEBUG:-}" \
        --field="MESA_DEBUG :":TEXT "${MESA_DEBUG:-}" \
        --field="AMD_DEBUG :":TEXT "${AMD_DEBUG:-}" \
        --field="VK_ICD_FILENAMES :":TEXT "${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/radeon_icd.x86_64.json}" \
        --field="mesa_glthread :":CBX "true!false" \
        --field="RADV_PERFTEST :":TEXT "${RADV_PERFTEST:-}" \
        --button="Annuler:1" --button="Sauvegarder:0" \
        --width=660)
    [ $? -ne 0 ] || [ -z "$out" ] && return

    IFS='|' read -r v_radv v_mesa v_amd v_vk v_glthread v_perf <<< "$out"
    cat > "$MESA_ENV_FILE" << SAVEOF
RADV_DEBUG=$v_radv
MESA_DEBUG=$v_mesa
AMD_DEBUG=$v_amd
VK_ICD_FILENAMES=$v_vk
mesa_glthread=$v_glthread
RADV_PERFTEST=$v_perf
SAVEOF
    yad_info "✓ Variables sauvegardées dans :\n<tt>$MESA_ENV_FILE</tt>"
}
export -f do_mesa_edit_env

do_mesa_save_profile() {
    local out
    out=$(yad --center --borders=10 \
        --title="Sauvegarder un profil" \
        --form \
        --text="Nom du profil Mesa à sauvegarder :" \
        --field="Nom :":TEXT "profil-debug" \
        --button="Annuler:1" --button="Sauvegarder:0" \
        --width=400)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local name; name=$(echo "$out" | cut -d'|' -f1 | tr ' ' '-')
    cp "$MESA_ENV_FILE" "$MESA_PROFILES_DIR/$name.conf"
    yad_info "✓ Profil sauvegardé : <b>$name</b>\n<tt>$MESA_PROFILES_DIR/$name.conf</tt>"
}
export -f do_mesa_save_profile

do_mesa_load_profile() {
    local profiles=()
    for f in "$MESA_PROFILES_DIR"/*.conf; do
        [ -f "$f" ] && profiles+=("$(basename "$f" .conf)")
    done
    [ "${#profiles[@]}" -eq 0 ] && yad_info "Aucun profil sauvegardé." && return

    local sel
    sel=$(yad --center --borders=10 \
        --title="Charger un profil Mesa" \
        --list \
        --text="Sélectionnez le profil à charger :" \
        --column="Profil" \
        "${profiles[@]}" \
        --print-column=1 --separator="" \
        --button="Annuler:1" --button="Charger:0" \
        --width=400 --height=300)
    [ $? -ne 0 ] || [ -z "$sel" ] && return
    sel="${sel//|/}"
    cp "$MESA_PROFILES_DIR/$sel.conf" "$MESA_ENV_FILE"
    yad_info "✓ Profil chargé : <b>$sel</b>"
}
export -f do_mesa_load_profile

do_mesa_launch_app() {
    local app
    app=$(yad --center --borders=10 \
        --title="Lancer une application avec les variables Mesa" \
        --file --filename="$HOME/" \
        --button="Annuler:1" --button="Lancer:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$app" ] && return
    [ ! -f "$app" ] && yad_err "Fichier introuvable." && return

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-mesa-launch-XXXX.sh)
    {
        echo "#!/bin/bash"
        echo "echo '=== Variables Mesa actives ==='"
        # Exporter chaque variable non vide
        while IFS='=' read -r key val; do
            [[ "$key" =~ ^# ]] && continue
            [ -z "$key" ] && continue
            if [ -n "$val" ]; then
                echo "export ${key}=${val}"
                echo "echo \"  ${key}=${val}\""
            fi
        done < "$MESA_ENV_FILE"
        echo "echo ''"
        echo "echo '=== Lancement : $app ==='"
        echo "\"$app\""
        echo "read -rp '[Entrée pour fermer]'"
    } > "$tmpscript"
    chmod +x "$tmpscript"

    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="Mesa Launch" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="Mesa Launch" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="Mesa Launch" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "Mesa Launch" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_mesa_launch_app

do_mesa_show_current() {
    local content
    content=$(cat "$MESA_ENV_FILE" 2>/dev/null || echo "(aucune variable définie)")
    yad --center --borders=10 \
        --title="Variables Mesa actuelles" \
        --text-info --width=560 --height=300 \
        --button="Fermer:0" \
        <<< "$content"
}
export -f do_mesa_show_current

tab_mesa_env() {
    yad --plug="$KEY" --tabnum=9 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Control Panel 1.png" --image-on-top \
        --text="<big><b>⚙  Variables Mesa / Vulkan</b></big>
Définissez RADV_DEBUG, MESA_DEBUG, AMD_DEBUG… sauvegardez des profils
et lancez une application avec ces variables pré-exportées.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Édition —</b>":LBL "" \
        --field="  ✏  Éditer les variables Mesa/Vulkan":BTN 'bash -c "do_mesa_edit_env"' \
        --field="  📋 Afficher les variables actuelles":BTN 'bash -c "do_mesa_show_current"' \
        \
        --field="":LBL "" \
        --field="<b>— Profils —</b>":LBL "" \
        --field="  💾 Sauvegarder le profil actuel":BTN 'bash -c "do_mesa_save_profile"' \
        --field="  📂 Charger un profil":BTN 'bash -c "do_mesa_load_profile"' \
        \
        --field="":LBL "" \
        --field="<b>— Lancement —</b>":LBL "" \
        --field="  🚀 Lancer une application avec les variables actives":BTN 'bash -c "do_mesa_launch_app"' \
        \
        "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# ONGLET 10 — Compilation Kernel PS4 (Jaguar / LTO)
#========================================================================

# Documentation intégrée — texte affiché dans l'onglet
KERNEL_DOC="<b>Optimisation kernel pour PS4 (Jaguar / GCN 1.1)</b>

<b>Pourquoi kernel 5.15.x &gt; 6.x sur PS4 ?</b>
• GPU Sea Islands / GCN 1.1 (Liverpool) — aucun support officiel
• Kernel 5.15 : moins de régressions GCN 1.1, amdgpu plus léger,
  gestion clock/powerplay/fences plus stable
• Kernel 6.x : protections Spectre/Meltdown coûteuses sur Jaguar 1.6 GHz
  → <b>Heaven : 5.15.15 = 1200 pts | 6.15.4 = ~965 pts</b>

<b>menuconfig avec LTO visible :</b>  <tt>make LLVM=1 menuconfig</tt>
<b>Flags de compilation Jaguar :</b>
<tt>-march=btver2 -mtune=btver2 -O3 -fomit-frame-pointer -flto -pipe</tt>

<b>Bootargs PS4 recommandés :</b>
<small><tt>amdgpu.cik_support=1 amdgpu.si_support=1 amdgpu.dc=0
mitigations=off nopti spectre_v2=off noibpb noibrs
processor.max_cstate=1 idle=nomwait
amdgpu.lockup_timeout=10000</tt></small>

<b>CONFIG clés :</b>
<tt>CONFIG_LTO_CLANG_FULL=y
CONFIG_DRM_AMDGPU_CIK=y
CONFIG_DRM_AMDGPU_SI=y
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y</tt>

<b>Mesa Jaguar (ligne COMPILERFLAGS) :</b>
<small><tt>-march=btver2 -mtune=btver2 -O3 -flto={nproc} -g0 -fno-semantic-interposition</tt></small>"

export KERNEL_DOC

KERNEL_SRC_FILE="$CONF_DIR/kernel-src-dir.txt"
[ ! -f "$KERNEL_SRC_FILE" ] && echo "$HOME/linux-kernel" > "$KERNEL_SRC_FILE"
export KERNEL_SRC_FILE

do_kernel_select_src() {
    local d
    d=$(yad --center --borders=10 \
        --title="Dossier des sources kernel" \
        --file --directory --filename="$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/")" \
        --button="Annuler:1" --button="Sélectionner:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$d" ] && return
    echo "$d" > "$KERNEL_SRC_FILE"
    yad_info "✓ Sources kernel définies :\n<tt>$d</tt>"
}
export -f do_kernel_select_src

do_kernel_menuconfig_standard() {
    local src
    src=$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/linux-kernel")
    [ ! -d "$src" ] && yad_err "Dossier sources introuvable :\n<tt>$src</tt>\nCliquez sur <b>Sélectionner les sources</b>." && return

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-menuconfig-XXXX.sh)
    cat > "$tmpscript" << MEOF
#!/bin/bash
echo "=== menuconfig standard ==="
echo "Sources : $src"
echo ""
cd "$src" || exit 1
make menuconfig
echo ""
read -rp "[Entrée pour fermer]"
MEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="menuconfig" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="menuconfig" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="menuconfig" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "menuconfig" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_kernel_menuconfig_standard

do_kernel_menuconfig_lto() {
    local src
    src=$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/linux-kernel")
    [ ! -d "$src" ] && yad_err "Dossier sources introuvable :\n<tt>$src</tt>\nCliquez sur <b>Sélectionner les sources</b>." && return

    # Vérifier clang/lld
    if ! command -v clang >/dev/null 2>&1 || ! command -v ld.lld >/dev/null 2>&1; then
        yad_err "clang ou lld non installé.\n<b>sudo apt install clang lld llvm</b>"
        return
    fi

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-menuconfig-lto-XXXX.sh)
    cat > "$tmpscript" << MEOF
#!/bin/bash
echo "=== menuconfig LLVM=1 (options LTO visibles) ==="
echo "Sources : $src"
echo "Compilateur : clang $(clang --version 2>/dev/null | head -1)"
echo ""
cd "$src" || exit 1
make LLVM=1 menuconfig
echo ""
read -rp "[Entrée pour fermer]"
MEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="menuconfig LLVM/LTO" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="menuconfig LLVM/LTO" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="menuconfig LLVM/LTO" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "menuconfig LLVM/LTO" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_kernel_menuconfig_lto

do_kernel_compile_lto() {
    local src
    src=$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/linux-kernel")
    [ ! -d "$src" ] && yad_err "Dossier sources introuvable :\n<tt>$src</tt>" && return

    if ! command -v clang >/dev/null 2>&1; then
        yad_err "clang non installé.\n<b>sudo apt install clang lld llvm</b>"
        return
    fi

    local jobs
    jobs=$(nproc)

    # Permettre à l'utilisateur d'ajuster le nb de jobs
    local out
    out=$(yad --center --borders=10 \
        --title="Compilation kernel FULL LTO — Jaguar" \
        --form \
        --text="<b>Compilation Full LTO pour PS4 (Jaguar / btver2)</b>\n\n⚠️  <b>Consomme beaucoup de RAM</b> — prévoir 24 Go minimum pour Full LTO.\nAvec 16 Go, utiliser <b>-j2</b> ou <b>-j1</b> pour éviter le freeze.\n" \
        --field="Nb de jobs (-j) :":NUM "${jobs}!1..$(nproc)!1" \
        --field="Flags supplémentaires :":TEXT "" \
        --button="Annuler:1" --button="🚀 Compiler:0" \
        --width=600)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local njobs extra_flags
    njobs=$(echo "$out"      | cut -d'|' -f1)
    extra_flags=$(echo "$out" | cut -d'|' -f2)

    yad_confirm "Lancer la compilation Full LTO kernel ?\n\n  Sources : <tt>$src</tt>\n  Jobs    : <b>-j${njobs}</b>\n\n⚠️  Peut durer <b>plusieurs heures</b>.\nSurveiller la RAM avec <tt>monitor-compilation.sh</tt>." || return

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-compile-kernel-XXXX.sh)
    cat > "$tmpscript" << CEOF
#!/bin/bash
cd "$src" || exit 1
echo "=== Compilation kernel Full LTO Jaguar ==="
echo "Jobs    : $njobs"
echo "Sources : $src"
echo "Début   : \$(date)"
echo ""
make -j${njobs} \\
    LLVM=1 \\
    KCFLAGS="-march=btver2 -mtune=btver2 -O3 -fomit-frame-pointer -flto -mno-sse4a -mno-xop -mno-tbm -pipe ${extra_flags}" \\
    CC=clang \\
    LD=ld.lld \\
    AR=llvm-ar \\
    NM=llvm-nm \\
    STRIP=llvm-strip \\
    OBJCOPY=llvm-objcopy \\
    OBJDUMP=llvm-objdump \\
    READELF=llvm-readelf \\
    HOSTCC=clang \\
    HOSTCXX=clang++ \\
    HOSTAR=llvm-ar \\
    HOSTLD=ld.lld
echo ""
echo "=== Fin : \$(date) ==="
echo ""
if [ -f arch/x86/boot/bzImage ]; then
    echo "OK  bzImage produit : arch/x86/boot/bzImage"
    echo "  → Copiez-le dans /boot sur votre PS4"
else
    echo "ERREUR : bzImage introuvable"
fi
echo ""
read -rp "[Entrée pour fermer]"
CEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="Compilation Kernel LTO" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="Compilation Kernel LTO" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="Compilation Kernel LTO" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "Compilation Kernel LTO" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_kernel_compile_lto

do_kernel_copy_bzimage() {
    local src
    src=$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/linux-kernel")
    local bzimage="$src/arch/x86/boot/bzImage"
    [ ! -f "$bzimage" ] && yad_err "bzImage introuvable :\n<tt>$bzimage</tt>\nCompiler d'abord le kernel." && return

    local dst
    dst=$(yad --center --borders=10 \
        --title="Copier bzImage" \
        --form \
        --text="Destination de la copie de bzImage :" \
        --field="Destination :":TEXT "/boot/bzImage-ps4-lto" \
        --button="Annuler:1" --button="Copier:0" \
        --width=520)
    [ $? -ne 0 ] || [ -z "$dst" ] && return
    dst=$(echo "$dst" | cut -d'|' -f1)

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-cpbz-XXXX.sh)
    cat > "$tmpscript" << CPEOF
#!/bin/bash
echo "Copie de bzImage..."
sudo cp "$bzimage" "$dst" && echo "OK - bzImage copié : $dst" || echo "ERREUR copie"
echo ""
ls -lh "$dst" 2>/dev/null
echo ""
read -rp "[Entrée pour fermer]"
CPEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="Copie bzImage" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="Copie bzImage" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="Copie bzImage" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "Copie bzImage" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_kernel_copy_bzimage

do_kernel_show_doc() {
    # Afficher la documentation complète en texte brut dans yad --text-info
    local doc_text
    doc_text="Optimisation kernel 6.15.4 — PS4 Jaguar / GCN 1.1
=======================================================================

POURQUOI LE KERNEL 6.x EST PLUS LENT SUR PS4 ?
=======================================================================
La PS4 utilise un GPU Sea Islands / GCN 1.1 (Liverpool).
Aucun kernel Linux ne supporte officiellement ce matériel.

(1) Driver AMD (amdgpu) non adapté pour GCN1.1
    - Kernel 5.15.x : moins de régressions GCN1.1, amdgpu plus léger,
      gestion clock/powerplay/fences plus stable.
    - Kernel 6.x : modifications IRQ, memory barriers, power management,
      VM scheduler qui améliorent RDNA/Vega mais dégradent les vieux GCN.

(2) Protections sécurité (Spectre, Meltdown, Retpoline, IBPB, IBRS)
    - Coûtent des cycles sur Jaguar 1.6 GHz.
    - Kernel 5.15 en active moins → FPS plus élevés.
    - Heaven : 5.15.15 = 1200 pts | 6.15.4 = ~965 pts
    - Gain potentiel : +20 à +40 % sur certains benchmarks.

=======================================================================
MENUCONFIG AVEC OPTIONS LTO VISIBLES
=======================================================================
Sans LLVM=1, les options LTO n'apparaissent pas dans menuconfig.
Commande correcte : make LLVM=1 menuconfig

=======================================================================
CONFIG .config CLÉS POUR PS4 / JAGUAR
=======================================================================
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y
CONFIG_LTO=y
CONFIG_LTO_CLANG=y
CONFIG_LTO_CLANG_FULL=y
CONFIG_LTO_CLANG_THIN=n
CONFIG_DRM_AMDGPU=y
CONFIG_DRM_AMDGPU_CIK=y
CONFIG_DRM_AMDGPU_SI=y
CONFIG_DRM_AMDGPU_USERPTR=y
# CONFIG_PAGE_TABLE_ISOLATION is not set
# CONFIG_MITIGATION_RETPOLINE is not set
# CONFIG_MITIGATION_SPECTRE_V1 is not set
# CONFIG_MITIGATION_SPECTRE_V2 is not set
# CONFIG_MITIGATION_SSB is not set
# CONFIG_DEBUG_INFO is not set

=======================================================================
FLAGS DE COMPILATION JAGUAR (btver2)
=======================================================================
KCFLAGS='-march=btver2 -mtune=btver2 -O3 -fomit-frame-pointer
         -flto -mno-sse4a -mno-xop -mno-tbm -pipe'

Commande complète :
make -j\$JOBS LLVM=1
    CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
    STRIP=llvm-strip OBJCOPY=llvm-objcopy
    HOSTCC=clang HOSTCXX=clang++ HOSTAR=llvm-ar HOSTLD=ld.lld
    KCFLAGS='...'

=======================================================================
BOOTARGS PS4 RECOMMANDÉS
=======================================================================
amdgpu.gttsize=2048 amdgpu.vm_fragment_size=9 amdgpu.dc=0
amdgpu.pcie_gen2=1 amdgpu.aspm=0 amdgpu.dpm=1
amdgpu.deep_color=0 amdgpu.gpu_recovery=0
radeon.si_support=0 amdgpu.si_support=1 amdgpu.cik_support=1
mitigations=off nopti spectre_v2=off spec_store_bypass_disable=off
noibpb noibrs ibt=off processor.max_cstate=1 idle=nomwait
amdgpu.lockup_timeout=10000 drm.edid_firmware=edid/1920x1080.bin

=======================================================================
MESA JAGUAR — COMPILERFLAGS
=======================================================================
-pipe -march=btver2 -mtune=btver2 -O3 -mfpmath=sse
-ftree-vectorize -flto -flto={nproc} -g0 -fno-semantic-interposition

=======================================================================
MÉMOIRE RAM — FULL LTO
=======================================================================
Full LTO consomme beaucoup de RAM.
Avec i3 + 16 Go : utiliser -j2 ou -j1 pour éviter le freeze.
Scripts fournis : compile-i3-fulllto-v2.sh + monitor-compilation.sh
"

    echo "$doc_text" | yad --center --borders=10 \
        --title="Documentation Kernel PS4 Jaguar" \
        --text-info --scroll \
        --width=820 --height=620 \
        --button="Fermer:0"
}
export -f do_kernel_show_doc

tab_kernel() {
    local src
    src=$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/linux-kernel")

    yad --plug="$KEY" --tabnum=10 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Control Panel 1.png" --image-on-top \
        --text="<big><b>🐧 Compilation Kernel PS4 (Jaguar / LTO)</b></big>
Optimisation kernel pour GPU GCN 1.1 (Liverpool) de la PS4.
Sources actuelles : <tt>${src}</tt>\n" \
        \
        --field="":LBL "" \
        --field="<b>— Sources kernel —</b>":LBL "" \
        --field="  📂 Sélectionner le dossier des sources kernel":BTN 'bash -c "do_kernel_select_src"' \
        \
        --field="":LBL "" \
        --field="<b>— Configuration (menuconfig) —</b>":LBL "" \
        --field="  ⚙  menuconfig standard  (make menuconfig)":BTN 'bash -c "do_kernel_menuconfig_standard"' \
        --field="  ⚡ menuconfig LLVM/LTO   (make LLVM=1 menuconfig)":BTN 'bash -c "do_kernel_menuconfig_lto"' \
        --field="  <small><i>→ LLVM=1 obligatoire pour voir les options Full LTO / Thin LTO</i></small>":LBL "" \
        \
        --field="":LBL "" \
        --field="<b>— Compilation Full LTO Jaguar (btver2) —</b>":LBL "" \
        --field="  🚀 Compiler le kernel (Full LTO, -march=btver2)":BTN 'bash -c "do_kernel_compile_lto"' \
        --field="  <small><i>⚠ Nécessite clang/lld/llvm — RAM importante (24 Go idéal, 16 Go : -j2)</i></small>":LBL "" \
        \
        --field="":LBL "" \
        --field="<b>— Déploiement —</b>":LBL "" \
        --field="  💾 Copier bzImage dans /boot (sudo)":BTN 'bash -c "do_kernel_copy_bzimage"' \
        \
        --field="":LBL "" \
        --field="<b>— Documentation —</b>":LBL "" \
        --field="  📖 Guide complet : kernel Jaguar, LTO, bootargs, Mesa":BTN 'bash -c "do_kernel_show_doc"' \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# ONGLET 11 — GIT PS4 KERNELS + ORBIS
#========================================================================

do_git_ps4_kernel() {
    local branches=(
        "ps4-5.15.y"      # Stable PS4
        "ps4-6.1.y"       # Nouveau
        "ps4-6.6.y"       # Latest
        "master"          # Main
    )
    
    local branch
    branch=$(yad --center --borders=10 \
        --title="Télécharger Kernel PS4" \
        --list \
        --text="Sélectionne la branche PS4 :" \
        --column="Branche" \
        "${branches[@]}" \
        --print-column=1 \
        --button="Annuler:1" --button="🚀 Télécharger:0" \
        --width=400 --height=280)
    
    [ $? -ne 0 ] || [ -z "$branch" ] && return
    
    local dest="$KERNELS_DIR/linux-ps4-$branch"
    [ -d "$dest" ] && yad_confirm "Dossier existant :\n<tt>$dest</tt>\n\nSupprimer et re-télécharger ?" || rm -rf "$dest"
    
    run_in_term "🚀 Git PS4 Kernel — $branch" "
        cd '$PROJECT_DIR'
        git clone -b $branch --depth=1 https://github.com/crashniels/linux.git linux-ps4-$branch
        cd linux-ps4-$branch
        echo '=== Sources PS4 Kernel téléchargées ==='
        ls -la
        echo ''
        read -rp '[Entrée pour ouvrir le dossier]'
        xdg-open .
    "
    
    yad_info "✓ Kernel PS4 $branch\n📂 <tt>$dest</tt>"
}
export -f do_git_ps4_kernel
export -f do_git_ps4_kernel do_git_orbis do_open_project_dir tab_git_ps4
do_git_orbis() {
    run_in_term "🚀 Git Orbis + Dépendances" "
        cd '$PROJECT_DIR'
        
        # Check dépendances
        echo '=== Vérification dépendances Orbis ==='
        deps=(meson ninja-build pkg-config git python3 python3-pip cmake)
        missing=()
        for dep in \"\${deps[@]}\"; do
            if ! command -v \$dep >/dev/null 2>&1; then
                missing+=(\$dep)
            fi
        done
        
        if [ \${#missing[@]} -gt 0 ]; then
            echo 'INSTALLER : sudo apt install' \"\${missing[@]}\"
            read -rp 'Installer ? (y/N)'
            [ \"\$REPLY\" = 'y' ] && sudo apt update && sudo apt install -y \"\${missing[@]}\"
        fi
        
        # Clone Orbis
        echo ''
        echo '=== Téléchargement Orbis ==='
        rm -rf orbis
        git clone https://github.com/jpd0101/orbis.git
        cd orbis
        
        echo ''
        echo '=== Orbis installé ==='
        ls -la
        echo ''
        read -rp '[Entrée pour ouvrir]'
        xdg-open .
    "
    
    yad_info "✓ Orbis téléchargé\n📂 <tt>$ORBIS_DIR</tt>"
}
export -f do_git_orbis
export -f do_git_ps4_kernel do_git_orbis do_open_project_dir tab_git_ps4

do_git_payloads() {
    local dest="$PROJECT_DIR/ps4-linux-payloads"

    if [ -d "$dest" ]; then
        yad_confirm "Dossier existant :\n<tt>$dest</tt>\n\nRe-télécharger depuis zéro ?"
        if [ $? -eq 0 ]; then
            rm -rf "$dest"
        else
            # Dossier déjà là → juste recompiler
            run_in_term "🔧 Compiler PS4 Linux Payloads" "
                cd '$dest/linux'
                echo '=== Compilation payloads PS4 Linux ==='
                make
                echo ''
                echo '=== Compilation terminée ==='
                ls -la
                echo ''
                read -rp '[Entrée pour fermer]'
            "
            return
        fi
    fi

    run_in_term "🚀 Git + Compilation PS4 Linux Payloads" "
        cd '$PROJECT_DIR'
        echo '=== Téléchargement ps4-linux-payloads ==='
        git clone https://github.com/ps4boot/ps4-linux-payloads
        echo ''
        echo '=== Compilation make ==='
        cd ps4-linux-payloads/linux
        make
        echo ''
        echo '=== Terminé ==='
        ls -la
        echo ''
        read -rp '[Entrée pour ouvrir le dossier]'
        xdg-open '$dest'
    "
    yad_info "✓ PS4 Linux Payloads compilés\n📂 <tt>$dest</tt>"
}
export -f do_git_payloads

do_payloads_readme() {
    local readme_text="L'hôte avec des payloads Linux précompilés fonctionne uniquement avec GoldHEN v2.4b18.5/v2.4b18.6 BinLoader.
Ouvrez simplement votre navigateur web et mettez l'hôte en cache ; il fonctionnera également hors ligne.

▶️  https://ps4boot.github.io  (bouton ci-dessous pour ouvrir)

Vous trouverez des charges utiles Linux pour votre firmware, ainsi que des charges utiles supplémentaires.
Le reste est déjà inclus dans GoldHEN.

━━━  Placement automatique des fichiers de démarrage  ━━━
Le noyau (bzImage) et initramfs.cpio.gz sont désormais automatiquement copiés dans /data/linux/boot
sur le disque interne depuis la partition FAT32 externe.
→ Aucun disque externe n'est nécessaire pour l'interface de récupération, sauf lors du premier démarrage.

━━━  Heure RTC transmise à l'initramfs  ━━━
L'heure actuelle d'OrbisOS est ajoutée à la ligne de commande du noyau (time=CURRENTTIME),
garantissant que l'heure correcte est définie au démarrage au lieu de la valeur par défaut de 1970,
même si le matériel RTC ne peut pas être lu directement.
Un initramfs préparé est nécessaire pour lire l'heure depuis la ligne de commande et la définir.

━━━  Chemin interne par défaut  ━━━
  /data/linux/boot
Le reste provient de la configuration d'initialisation initramfs.cpio.gz.

Accès sans clé USB : transférez via FTP sur votre PS4 :
  /data/linux/boot/bzImage
  /data/linux/boot/initramfs.cpio.gz

Les périphériques USB sont prioritaires : si une clé est connectée, le système utilisera
bzImage et initramfs.cpio.gz depuis cette clé.

Vous pouvez ajouter un fichier texte (bootargs.txt) pour modifier la ligne de commande.
Le fichier vram.txt vous permet de modifier la VRAM via un fichier texte.

━━━  Notes importantes  ━━━
★  Avec GoldHEN v2.4b18.5/v2.4b18.6, utilisez les fichiers .elf au lieu des fichiers .bin ;
   cela fonctionne mieux et garantit un succès à 100%.

★  N'utilisez pas les charges utiles PRO pour les formats Phat ou Slim.

★  UART (si nécessaire) — actuellement désactivé, ne fonctionne pas sur noyaux récents :
     Éolie / Belize : console=uart8250,mmio32,0xd0340000
     Baïkal          : console=uart8250,mmio32,0xC890E000"

    echo "$readme_text" | yad --center --borders=12 \
        --title="📖 README — PS4 Linux Payloads" \
        --text-info --scroll \
        --width=800 --height=580 \
        --button="🌐 Ouvrir ps4boot.github.io:2" \
        --button="Fermer:0"

    local ret=$?
    [ $ret -eq 2 ] && xdg-open "https://ps4boot.github.io" >/dev/null 2>&1 &
}
export -f do_payloads_readme

do_open_project_dir() {
    xdg-open "$PROJECT_DIR" >/dev/null 2>&1 &
    yad_info "📂 Projet ouvert :\n<tt>$PROJECT_DIR</tt>"
}
export -f do_open_project_dir
export -f do_git_ps4_kernel do_git_orbis do_open_project_dir tab_git_ps4

tab_git_ps4() {
    yad --plug="$KEY" --tabnum=11 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Git.png" --image-on-top \
        --text="<big><b>🚀 GIT PS4 — Kernels + Orbis + Payloads</b></big>

<b>PROJET :</b> <tt>$PROJECT_DIR</tt>

Télécharge kernels PS4 optimisés + Orbis (SDK PS4) + Payloads Linux avec check dépendances auto.\n" \
        \
        --field="":LBL "" \
        --field="<b>— KERNELS PS4 (crashniels/linux) —</b>":LBL "" \
        --field="  🚀 ps4-5.15.y (stable/recommandé)":BTN 'bash -c "do_git_ps4_kernel"' \
        --field="  🚀 ps4-6.1.y / 6.6.y / master":BTN 'bash -c "do_git_ps4_kernel"' \
        \
        --field="":LBL "" \
        --field="<b>— ORBIS (SDK PS4) —</b>":LBL "" \
        --field="  🚀 Orbis + auto-install dépendances":BTN 'bash -c "do_git_orbis"' \
        \
        --field="":LBL "" \
        --field="<b>— PAYLOADS LINUX (ps4boot/ps4-linux-payloads) —</b>":LBL "" \
        --field="  🚀 Télécharger + compiler les payloads":BTN 'bash -c "do_git_payloads"' \
        --field="  📖 README — GoldHEN / bzImage / initramfs":BTN 'bash -c "do_payloads_readme"' \
        --field="  <small><i>→ Destination : $PROJECT_DIR/ps4-linux-payloads/linux</i></small>":LBL "" \
        \
        --field="":LBL "" \
        --field="<b>— Projet —</b>":LBL "" \
        --field="  📂 Ouvrir PROJECT-PS4/":BTN 'bash -c "do_open_project_dir"' \
        \
        --field="Kernels : <tt>$KERNELS_DIR</tt>":LBL "" \
        --field="Orbis   : <tt>$ORBIS_DIR</tt>":LBL "" \
        --field="Payloads: <tt>$PROJECT_DIR/ps4-linux-payloads</tt>":LBL "" \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# LANCEMENT DES ONGLETS EN ARRIÈRE-PLAN
#========================================================================

tab_mesa
tab_tar_create
tab_img_create
tab_tar_extract
tab_mount_ps4
tab_aide
tab_reseau
tab_diagnostic
tab_mesa_env
tab_kernel
tab_git_ps4
#========================================================================
# FENÊTRE PRINCIPALE
#========================================================================

yad --notebook \
    --window-icon="applications-system" \
    --title="Hybryde PS4 Tools" \
    --width=960 --height=720 \
    --image="$LOGO" \
    --image-on-top \
    --text="<span size='x-large'><b>Hybryde PS4 Tools</b></span>
<small>Mesa  •  Archivage  •  Image disque  •  SSD PS4  •  Réseau  •  Diagnostic  •  Mesa ENV  •  Kernel</small>" \
    --button="Fermer:0" \
    --key="$KEY" \
    --tab="🔧 Compiler Mesa" \
    --tab="📦 Créer un tar.xz" \
    --tab="💿 Créer un .img" \
    --tab="📂 Décompresser tar.xz" \
    --tab="🔌 Monter SSD PS4" \
    --tab="📖 Aide" \
    --tab="🌐 Réseau" \
    --tab="🔍 Diagnostic" \
    --tab="⚙ Mesa ENV" \
    --tab="🐧 Kernel LTO" \
    --tab="🐧 GIT DEV Kernel/Orbis..." \
    --active-tab=1
