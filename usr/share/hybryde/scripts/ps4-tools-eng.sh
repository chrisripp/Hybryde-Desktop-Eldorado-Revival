#!/bin/bash

#========================================================================
# hybryde-ps4-tools.sh — Hybryde PS4 Tools
# YAD multi-tab interface for PS4 Linux tools
# Version : 1.1 — 2026
# By triki1
#========================================================================

preview_pdf() {
    local FILE="${1/#\~/$HOME}"

    if [ ! -f "$FILE" ]; then
        yad_err "File not found:\n<tt>$FILE</tt>"
        return
    fi

    local TMPTXT TMPIMG IMG_FILE
    TMPTXT=$(mktemp)
    TMPIMG=$(mktemp --suffix=.png)

    # Extract text (fast, page 1 only)
    if command -v pdftotext >/dev/null 2>&1; then
        pdftotext -l 1 "$FILE" "$TMPTXT" 2>/dev/null
    else
        echo "pdftotext not installed (sudo apt install poppler-utils)" > "$TMPTXT"
    fi

    # Generate image preview (page 1)
    if command -v pdftoppm >/dev/null 2>&1; then
        pdftoppm -f 1 -l 1 -png "$FILE" "${TMPIMG%.png}" 2>/dev/null
        IMG_FILE="${TMPIMG%.png}-1.png"
    fi

    yad --title="PDF Preview — $(basename "$FILE")" \
        --width=640 --height=480 \
        --center \
        --text-info --scroll \
        --filename="$TMPTXT" \
        ${IMG_FILE:+--image="$IMG_FILE" --image-on-top} \
        --button="📂 Open in reader:0" \
        --button="Close:1"

    local ret=$?
    rm -f "$TMPTXT" "$TMPIMG"* 2>/dev/null

    # "Open" button → launch default PDF reader
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
mkdir -p "$KERNELS_DIR"   # orbis created only during installation (do_git_orbis)
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
# UTILITIES
#========================================================================

run_in_term() {
    local title="$1" cmd="$2"
    # Tmpscript avoids any quoting issues in complex commands
    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-term-XXXX.sh)
    printf '#!/bin/bash\n%s\necho\nread -rp "[Press Enter to close]"\nrm -f "%s"\n' \
        "$cmd" "$tmpscript" > "$tmpscript"
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="$title" -e "bash $tmpscript" ;;
        gnome-terminal) gnome-terminal --title="$title" -- bash "$tmpscript" ;;
        mate-terminal)  mate-terminal  --title="$title" -e "bash $tmpscript" ;;
        *)              xterm -title "$title" -e bash "$tmpscript" ;;
    esac
}
export -f run_in_term

run_sudo_in_term() {
    local title="$1" cmd="$2"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="$title" -e "bash -c 'sudo bash -c \"$cmd\"; echo; read -rp \"[Press Enter to close]\"; exit'" ;;
        gnome-terminal) gnome-terminal --title="$title" -- bash -c "sudo bash -c \"$cmd\"; echo; read -rp '[Press Enter to close]'; exit" ;;
        mate-terminal)  mate-terminal  --title="$title" -e "bash -c 'sudo bash -c \"$cmd\"; echo; read -rp \"[Press Enter to close]\"; exit'" ;;
        *)              xterm -title "$title" -e bash -c "sudo bash -c \"$cmd\"; echo; read -rp '[Press Enter to close]'; exit" ;;
    esac
}
export -f run_sudo_in_term

yad_err() {
    yad --center --borders=10 --window-icon="dialog-error" \
        --title="Error" --image="dialog-error" \
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
        --text="$1" --button="No:1" --button="Yes:0" --width=500
}
export -f yad_confirm

export KEY LOGO TERM_BIN CONF_DIR
export TAR_EXCLUDES_FILE TAR_NAME_FILE TAR_CMD_FILE
export IMG_PATH_FILE EXT_SRC_FILE EXT_DST_FILE BUILD_CMD_FILE

#========================================================================
# TAB 1 — Compile Mesa
#========================================================================

do_edit_script() {
    command -v geany &>/dev/null || {
        yad_err "Geany is not installed.\n<b>sudo apt install geany</b>"
        return
    }
    local script
    script=$(yad --center --borders=10 \
        --title="Select a script to edit" \
        --file --filename="$HOME/" \
        --file-filter="Scripts | *.sh *.py *.bash *.pl" \
        --button="Cancel:1" --button="Open in Geany:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$script" ] && return
    [ ! -f "$script" ] && yad_err "File not found." && return
    geany "$script" &
}
export -f do_edit_script

do_patch_mesa() {
    local mesa_dir="$HOME/mesa-git"
    [ ! -d "$mesa_dir" ] && yad_err "Folder not found: <tt>$mesa_dir</tt>\nCheck that Mesa sources are cloned." && return

    local patch
    patch=$(yad --center --borders=10 \
        --title="Select Mesa patch" \
        --file --filename="$mesa_dir/" \
        --file-filter="Patches | *.patch *.diff" \
        --button="Cancel:1" --button="Select:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$patch" ] && return
    [ ! -f "$patch" ] && yad_err "Patch file not found." && return

    local pname drylog
    pname=$(basename "$patch")
    drylog="$CONF_DIR/mesa-dryrun.log"

    run_in_term "Dry-run Mesa — $pname" \
        "cd '$mesa_dir' && patch -p1 --dry-run < '$patch' 2>&1 | tee '$drylog'; echo; echo '=== Dry-run complete ==='; read -rp '[Press Enter to continue]'"

    yad_confirm "Dry-run complete.\nLog: <tt>$drylog</tt>\n\nApply patch <b>$pname</b> to Mesa repository?" || return
    run_in_term "Appliquer patch Mesa — $pname" \
        "cd '$mesa_dir' && patch -p1 < '$patch'"
}
export -f do_patch_mesa

do_patch_libdrm() {
    local drm_dir="$HOME/libdrm-git"
    [ ! -d "$drm_dir" ] && yad_err "Folder not found: <tt>$drm_dir</tt>\nCheck that libdrm sources are cloned." && return

    local patch
    patch=$(yad --center --borders=10 \
        --title="Select libdrm patch" \
        --file --filename="$drm_dir/" \
        --file-filter="Patches | *.patch *.diff" \
        --button="Cancel:1" --button="Select:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$patch" ] && return
    [ ! -f "$patch" ] && yad_err "Patch file not found." && return

    local pname drylog
    pname=$(basename "$patch")
    drylog="$CONF_DIR/libdrm-dryrun.log"

    run_in_term "Dry-run libdrm — $pname" \
        "cd '$drm_dir' && patch -p1 --dry-run < '$patch' 2>&1 | tee '$drylog'; echo; echo '=== Dry-run complete ==='; read -rp '[Press Enter to continue]'"

    yad_confirm "Dry-run complete.\nLog: <tt>$drylog</tt>\n\nApply patch <b>$pname</b> to libdrm repository?" || return
    run_in_term "Appliquer patch libdrm — $pname" \
        "cd '$drm_dir' && patch -p1 < '$patch'"
}
export -f do_patch_libdrm

do_build_mesa() {
    local build_script="$HOME/mesa-build.py"
    [ ! -f "$build_script" ] && yad_err "Script not found: <tt>$build_script</tt>" && return
    run_in_term "Build Mesa" "cd '$HOME/mesa-git' && ./mesa-build.py"
}
export -f do_build_mesa


do_get_mesa_build_baryluk() {
    local dest="$HOME/mesa-build.py"
    local gist_url="https://gist.github.com/baryluk/1041204eff4cc4fad6f1508afe67b562"
    local raw_url="https://gist.githubusercontent.com/baryluk/1041204eff4cc4fad6f1508afe67b562/raw/mesa-build.py"

    # Si le fichier existe déjà, proposer de mettre à jour ou d'annuler
    if [ -f "$dest" ]; then
        yad_confirm "mesa-build.py already exists:\n<tt>$dest</tt>\n\nUpdate from baryluk's gist?" || return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        yad_err "curl is required.\n<b>sudo apt install curl</b>"
        return
    fi

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-baryluk-XXXX.sh)
    cat > "$tmpscript" << BEOF
#!/bin/bash
echo '=== Downloading mesa-build.py (baryluk) ==='
echo "Source:  $raw_url"
echo "Target:  $dest"
echo ''

curl -L --progress-bar "$raw_url" -o "$dest"
if [ \$? -ne 0 ] || [ ! -s "$dest" ]; then
    echo ''
    echo '✗ Download failed'
    echo "  Check your connection or open manually:"
    echo "  $gist_url"
    rm -f "$dest"
    read -rp '[Press Enter to close]'
    exit 1
fi

chmod +x "$dest"
echo ''
echo "✓ mesa-build.py downloaded and made executable"
echo "  Location: $dest"
echo ''
echo '--- Script start (first 10 lines) ---'
head -10 "$dest"
echo '...'
echo ''
echo "Usage: cd ~/mesa-git && python3 $dest [options]"
echo ''
read -rp '[Press Enter to close]'
BEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="🔧 mesa-build.py (baryluk)" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="🔧 mesa-build.py (baryluk)" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="🔧 mesa-build.py (baryluk)" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "🔧 mesa-build.py (baryluk)" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac

    sleep 1
    [ -f "$dest" ] && \
        yad_info "✓ mesa-build.py installed:\n<tt>$dest</tt>\n\n<small>Original gist: $gist_url</small>"
}
export -f do_get_mesa_build_baryluk
do_manual_build() {
    local last_cmd
    last_cmd=$(cat "$BUILD_CMD_FILE" 2>/dev/null)
    [ -z "$last_cmd" ] && last_cmd="./mesa-build.py"

    local out
    out=$(yad --center --borders=10 \
        --title="Manual Mesa command" \
        --form \
        --text="<b>Mesa build command</b>\n\nWorking directory will be: <tt>~/mesa-git</tt>\nEdit the command then click Launch.\n" \
        --field="Command:":TEXT "$last_cmd" \
        --button="Cancel:1" --button="🚀 Launch:0" \
        --width=840 --height=220)
    [ $? -ne 0 ] || [ -z "$out" ] && return

    local cmd
    cmd=$(echo "$out" | cut -d'|' -f1)
    echo "$cmd" > "$BUILD_CMD_FILE"
    run_in_term "Build Mesa (manuel)" "cd '$HOME/mesa-git' && $cmd"
}
export -f do_manual_build

tab_mesa() {
    yad --plug="$KEY" --tabnum=7 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Download Manager.png" --image-on-top \
        --text="<big><b><span foreground='#FFB74D'>🔧 Compile Mesa</span></b></big>
<span foreground='#FFCC80'>Tools to patch and compile Mesa / libdrm for PS4 Linux.</span>
Expected sources in <tt>~/mesa-git</tt>  and  <tt>~/libdrm-git</tt>.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Script editing —</b>":LBL "" \
        --field="  Open a script in Geany":BTN 'bash -c "do_edit_script"' \
        \
        --field="":LBL "" \
        --field="<b>— Patch Mesa  (~/mesa-git) —</b>":LBL "" \
        --field="  Search and apply a Mesa .patch":BTN 'bash -c "do_patch_mesa"' \
        \
        --field="":LBL "" \
        --field="<b>— Patch libdrm  (~/libdrm-git) —</b>":LBL "" \
        --field="  Search and apply a libdrm .patch":BTN 'bash -c "do_patch_libdrm"' \
        \
        --field="":LBL "" \
        --field="<b>— Compilation —</b>":LBL "" \
        --field="  Build Mesa  (./mesa-build.py)":BTN 'bash -c "do_build_mesa"' \
        --field="  Manual command (editable before launch)":BTN 'bash -c "do_manual_build"' \
        \
        --field="":LBL "" \
        --field="<b>— mesa-build.py (baryluk) —</b>":LBL "" \
        --field="  <small><i>Alternative Mesa build script by baryluk (GitHub gist)</i></small>":LBL "" \
        --field="  ⬇  Download mesa-build.py (baryluk)":BTN 'bash -c "do_get_mesa_build_baryluk"' \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# TAB 2 — Create a tar.xz
#========================================================================

do_tar_set_name() {
    local cur
    cur=$(cat "$TAR_NAME_FILE" 2>/dev/null || echo "ps4linux.tar.xz")
    local out
    out=$(yad --center --borders=10 \
        --title="tar.xz name" \
        --form \
        --text="Enter the tar.xz filename:" \
        --field="Filename:":TEXT "$cur" \
        --button="Cancel:1" --button="Confirm:0" \
        --width=520)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local name
    name=$(echo "$out" | cut -d'|' -f1)
    echo "$name" > "$TAR_NAME_FILE"
    yad_info "✓ Name set: <b>$name</b>\nFinal location: <tt>/$name</tt>"
}
export -f do_tar_set_name

do_tar_add_exclude() {
    local out
    out=$(yad --center --borders=10 \
        --title="Add an exclusion" \
        --form \
        --text="Enter a path to exclude from the tar.xz:\n(ex: <tt>/var/cache</tt>  <tt>/proc</tt>  <tt>/tmp</tt>)" \
        --field="Path to exclude:":TEXT "/var/cache" \
        --button="Cancel:1" --button="Add:0" \
        --width=540)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local entry
    entry=$(echo "$out" | cut -d'|' -f1)
    [ -z "$entry" ] && return
    echo "$entry" >> "$TAR_EXCLUDES_FILE"
    yad_info "✓ Exclusion added: <tt>$entry</tt>"
}
export -f do_tar_add_exclude

do_tar_del_exclude() {
    [ ! -f "$TAR_EXCLUDES_FILE" ] && yad_info "The exclusion list is empty." && return
    local items=()
    while IFS= read -r line; do
        [ -n "$line" ] && items+=("$line")
    done < "$TAR_EXCLUDES_FILE"
    [ "${#items[@]}" -eq 0 ] && yad_info "The exclusion list is empty." && return

    local sel
    sel=$(yad --center --borders=10 \
        --title="Delete an exclusion" \
        --list \
        --text="Select the entry to delete:" \
        --column="Path to exclude" \
        "${items[@]}" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="Delete:0" \
        --width=520 --height=360)
    [ $? -ne 0 ] || [ -z "$sel" ] && return
    local escaped="${sel//\//\\/}"
    sed -i "/^${escaped}$/d" "$TAR_EXCLUDES_FILE"
    yad_info "✓ Deleted: <tt>$sel</tt>"
}
export -f do_tar_del_exclude

do_tar_show_excludes() {
    local content
    content=$(cat "$TAR_EXCLUDES_FILE" 2>/dev/null || echo "(empty list)")
    yad --center --borders=10 \
        --title="Current exclusions" \
        --text-info \
        --width=540 --height=340 \
        --button="Close:0" \
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

    yad_info "<b>Generated command:</b>\n\n<tt>$cmd</tt>\n\n📦 Final file: <tt>/$tarname</tt>\n\nClick <b>🚀 Launch creation</b> to execute."
}
export -f do_tar_generate

do_tar_run() {
    [ ! -f "$TAR_CMD_FILE" ] && yad_err "No command generated.\nClick <b>Generate command</b> first." && return
    local cmd tarname
    cmd=$(cat "$TAR_CMD_FILE")
    tarname=$(cat "$TAR_NAME_FILE" 2>/dev/null || echo "ps4linux.tar.xz")

    yad_confirm "Launch archive creation?\n\n<tt>$cmd</tt>\n\n📦 Result: <tt>/$tarname</tt>\n\n⚠️  This operation may take <b>several hours</b>." || return
    run_in_term "PS4 tar.xz Creation" "$cmd"
}
export -f do_tar_run

tab_tar_create() {
    yad --plug="$KEY" --tabnum=1 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/WinZip 1.png" --image-on-top \
        --text="<big><b><span foreground='#4FC3F7'>📦 Create a tar.xz</span></b></big>
Commande : <tt>sudo tar -cvf /[nom] --exclude=... --one-file-system / -I \"xz -9\"</tt>
The tar.xz will be created at the <b>root /</b> of the system.\n" \
        \
        --field="":LBL "" \
        --field="<b>— tar.xz filename —</b>":LBL "" \
        --field="  Current name:  $(cat "$TAR_NAME_FILE" 2>/dev/null || echo "ps4linux.tar.xz")":LBL "" \
        --field="  Edit name":BTN 'bash -c "do_tar_set_name"' \
        \
        --field="":LBL "" \
        --field="<b>— Exclusions (--exclude) —</b>":LBL "" \
        --field="  Add a path to exclude":BTN 'bash -c "do_tar_add_exclude"' \
        --field="  Delete an exclusion":BTN 'bash -c "do_tar_del_exclude"' \
        --field="  View exclusion list":BTN 'bash -c "do_tar_show_excludes"' \
        \
        --field="":LBL "" \
        --field="<b>— Generate and launch —</b>":LBL "" \
        --field="  Generate final command":BTN 'bash -c "do_tar_generate"' \
        --field="  🚀 Launch tar.xz creation":BTN 'bash -c "do_tar_run"' \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# TAB 3 — Create a .img
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
        yad_err "No partition detected.\nCheck that the disk is connected (<tt>lsblk</tt>)."
        return
    fi

    local sel
    sel=$(yad --center --borders=10 \
        --title="Select source partition" \
        --list \
        --text="<b>Select the partition to back up as .img</b>\n\n⚠️  Ideally, the partition should <b>not be mounted</b> for a consistent image." \
        --column="Partition" \
        --column="Size  |  FS  |  Mount point" \
        "${parts[@]}" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="Select:0" \
        --width=700 --height=440)
    [ $? -ne 0 ] || [ -z "$sel" ] && return
    sel="${sel//|/}"
    echo "$sel" > "$IMG_SRC_PART_FILE"
    yad_info "✓ Source partition selected:\n<tt>$sel</tt>"
}
export -f do_img_select_partition

do_img_select_dst() {
    local d
    d=$(yad --center --borders=10 \
        --title="Select destination folder" \
        --file --directory --filename="$HOME/" \
        --button="Cancel:1" --button="Select:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$d" ] && return
    echo "$d" > "$IMG_DST_DIR_FILE"
    yad_info "✓ Destination folder:\n<tt>$d</tt>"
}
export -f do_img_select_dst

do_img_set_name() {
    local cur
    cur=$(cat "$IMG_NAME_FILE2" 2>/dev/null || echo "ps4linux-partition.img")
    local out
    out=$(yad --center --borders=10 \
        --title=".img filename" \
        --form \
        --text="Enter the image filename to create:" \
        --field=".img filename:":TEXT "$cur" \
        --button="Cancel:1" --button="Confirm:0" \
        --width=520)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local name
    name=$(echo "$out" | cut -d'|' -f1)
    echo "$name" > "$IMG_NAME_FILE2"
    yad_info "✓ Name set: <b>$name</b>"
}
export -f do_img_set_name

do_img_show_sel() {
    local src dst name
    src=$(cat "$IMG_SRC_PART_FILE" 2>/dev/null || echo "— not selected —")
    dst=$(cat "$IMG_DST_DIR_FILE"  2>/dev/null || echo "— not selected —")
    name=$(cat "$IMG_NAME_FILE2"   2>/dev/null || echo "ps4linux-partition.img")
    yad_info "<b>Current selection:</b>\n\n  💽 Source partition: <tt>$src</tt>\n  📂 Dest. folder:    <tt>$dst</tt>\n  📄 Filename:        <b>$name</b>\n\n🗂 Final file: <tt>$dst/$name</tt>"
}
export -f do_img_show_sel

do_img_create() {
    local src dst name
    src=$(cat "$IMG_SRC_PART_FILE" 2>/dev/null)
    dst=$(cat "$IMG_DST_DIR_FILE"  2>/dev/null)
    name=$(cat "$IMG_NAME_FILE2"   2>/dev/null || echo "ps4linux-partition.img")

    [ -z "$src" ] && yad_err "No source partition selected.\nClick <b>① Select partition</b>." && return
    [ ! -b "$src" ] && yad_err "Block device not found:\n<tt>$src</tt>\nCheck that the disk is connected." && return
    [ -z "$dst" ] && yad_err "No destination folder selected.\nClick <b>② Select folder</b>." && return
    [ ! -d "$dst" ] && yad_err "Folder not found:\n<tt>$dst</tt>" && return

    local imgpath="$dst/$name"

    local part_size_human part_size_bytes avail_bytes space_warn=""
    part_size_human=$(lsblk -no SIZE "$src" 2>/dev/null | head -1 | tr -d ' ')
    part_size_bytes=$(lsblk -bno SIZE "$src" 2>/dev/null | head -1 | tr -d ' ')
    avail_bytes=$(df -B1 --output=avail "$dst" 2>/dev/null | tail -1 | tr -d ' ')

    if [ -n "$part_size_bytes" ] && [ -n "$avail_bytes" ]; then
        if [ "$avail_bytes" -lt "$part_size_bytes" ]; then
            local avail_human
            avail_human=$(df -h --output=avail "$dst" 2>/dev/null | tail -1 | tr -d ' ')
            space_warn="\n\n⚠️  <b>Insufficient space!</b>\n  Required:    $part_size_human\n  Available:   $avail_human"
        fi
    fi

    local cmd="sudo dd if='$src' of='$imgpath' bs=4M status=progress conv=fsync"

    yad_confirm "Create complete partition image?\n\n  💽 Source  : <tt>$src</tt>  ($part_size_human)\n  📄 Image   : <tt>$imgpath</tt>\n\nCommande :\n<tt>$cmd</tt>${space_warn}\n\n⏱  This operation may take several minutes." || return

    echo "$imgpath" > "$IMG_PATH_FILE"
    run_sudo_in_term "Partition backup → .img" \
        "dd if='$src' of='$imgpath' bs=4M status=progress conv=fsync && echo '' && echo '✓ Image created:' && ls -lh '$imgpath' || echo '✗ dd error'"
}
export -f do_img_create

do_img_show_path() {
    local p
    p=$(cat "$IMG_PATH_FILE" 2>/dev/null)
    if [ -n "$p" ]; then
        local info
        info=$(ls -lh "$p" 2>/dev/null || echo "(file not found)")
        yad_info "Last .img created:\n\n<tt>$p</tt>\n\n$info"
    else
        yad_info "No .img created yet."
    fi
}
export -f do_img_show_path

tab_img_create() {
    yad --plug="$KEY" --tabnum=2 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Zip.png" --image-on-top \
        --text="<big><b><span foreground='#CE93D8'>💿 Create a .img image</span></b></big>
Complete partition backup via <tt>dd</tt>.
Commande : <tt>sudo dd if=[partition] of=[fichier.img] bs=4M status=progress conv=fsync</tt>\n" \
        \
        --field="":LBL "" \
        --field="<b>— Source and destination —</b>":LBL "" \
        --field="  ① Select partition to back up":BTN 'bash -c "do_img_select_partition"' \
        --field="  ② Select destination folder":BTN 'bash -c "do_img_select_dst"' \
        --field="  ③ Edit .img filename":BTN 'bash -c "do_img_set_name"' \
        --field="  View current selection":BTN 'bash -c "do_img_show_sel"' \
        \
        --field="":LBL "" \
        --field="<b>— Backup —</b>":LBL "" \
        --field="  🚀 Create .img image of partition (dd)":BTN 'bash -c "do_img_create"' \
        \
        --field="":LBL "" \
        --field="<b>— Information —</b>":LBL "" \
        --field="  View last created .img location":BTN 'bash -c "do_img_show_path"' \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# TAB 4 — Extract a tar.xz
#========================================================================

do_ext_select_src() {
    local f
    f=$(yad --center --borders=10 \
        --title="Select tar.xz archive" \
        --file --filename="$HOME/" \
        --file-filter="Archives tar.xz | *.tar.xz *.tar" \
        --button="Cancel:1" --button="Select:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$f" ] && return
    echo "$f" > "$EXT_SRC_FILE"
    yad_info "✓ Archive selected:\n<tt>$f</tt>"
}
export -f do_ext_select_src

do_ext_select_dst() {
    local d
    d=$(yad --center --borders=10 \
        --title="Select destination partition" \
        --file --directory --filename="/media/$USER/" \
        --button="Cancel:1" --button="Select:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$d" ] && return
    echo "$d" > "$EXT_DST_FILE"
    yad_info "✓ Destination selected:\n<tt>$d</tt>"
}
export -f do_ext_select_dst

do_ext_show_sel() {
    local src dst
    src=$(cat "$EXT_SRC_FILE" 2>/dev/null || echo "— not selected —")
    dst=$(cat "$EXT_DST_FILE" 2>/dev/null || echo "— not selected —")
    yad_info "<b>Current selection:</b>\n\n  📁 Archive      : <tt>$src</tt>\n  📂 Destination  : <tt>$dst</tt>"
}
export -f do_ext_show_sel

do_ext_run() {
    local src dst
    src=$(cat "$EXT_SRC_FILE" 2>/dev/null)
    dst=$(cat "$EXT_DST_FILE" 2>/dev/null)

    [ -z "$src" ] && yad_err "No archive selected.\nClick <b>① Select archive</b>." && return
    [ ! -f "$src" ] && yad_err "File not found:\n<tt>$src</tt>" && return
    [ -z "$dst" ] && yad_err "No destination selected.\nClick <b>② Select partition</b>." && return

    local cmd="sudo tar -xvJpf '$src' -C '$dst' --numeric-owner"

    yad_confirm "Launch extraction?\n\n  📁 Archive     : <tt>$(basename "$src")</tt>\n  📂 Destination : <tt>$dst</tt>\n\n<tt>$cmd</tt>\n\n⚠️  This operation may take a long time." || return

    run_in_term "PS4 tar.xz Extraction" "$cmd"
}
export -f do_ext_run

tab_tar_extract() {
    yad --plug="$KEY" --tabnum=3 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Downloads 2.png" --image-on-top \
        --text="<big><b><span foreground='#A5D6A7'>📂 Extract a tar.xz</span></b></big>
Commande : <tt>sudo tar -xvJpf [archive] -C [partition] --numeric-owner</tt>\n" \
        \
        --field="":LBL "" \
        --field="<b>— Selection —</b>":LBL "" \
        --field="  ① Select tar.xz archive":BTN 'bash -c "do_ext_select_src"' \
        --field="  ② Select destination partition":BTN 'bash -c "do_ext_select_dst"' \
        --field="  View current selection":BTN 'bash -c "do_ext_show_sel"' \
        \
        --field="":LBL "" \
        --field="<b>— Extraction —</b>":LBL "" \
        --field="  🚀 Launch extraction":BTN 'bash -c "do_ext_run"' \
        \
        "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# TAB 5 — Mount PS4 SSD (SIMPLE VERSION)
#========================================================================

PS4_KEY="/key/eap_hdd_key.bin"
PS4_DEV="/dev/sda27"
PS4_MNT="/ps4hdd"

# ── Belize / Aeolia Mount ───────────────────────────────────────────
do_mount_ps4_belize() {
    xterm -hold -e bash -c "
echo '--- PS4 Belize / Aeolia Mount ---'
echo ''
echo '--- cryptsetup ---'
sudo cryptsetup -d /key/eap_hdd_key.bin --cipher aes-xts-plain64 -s 256 --offset 0 --skip 111669149696 create ps4hdd /dev/sd?27
sudo mount -t ufs -o ufstype=ufs2 /dev/mapper/ps4hdd /ps4hdd
sudo chmod -R a+rwX /ps4hdd

echo ''
echo 'OK → SSD mounted on $PS4_MNT'
cd /ps4hdd
ls 
read -p 'Enter... Vous pouvez fermer ce terminal, vous pouvez utiliser votre explorateur de fichier, dossier /ps4hdd'
"
}

# ── Baikal Mount ────────────────────────────────────────────────────
do_mount_ps4_baikal() {
    xterm -hold -e bash -c "
echo '--- PS4 Baikal Mount ---'
echo ''
echo '--- cryptsetup ---'
sudo cryptsetup -d $PS4_KEY --cipher aes-xts-plain64 -s 256 --offset 0 create ps4hdd $PS4_DEV
sudo mount -t ufs -o ufstype=ufs2 /dev/mapper/ps4hdd $PS4_MNT
sudo chmod -R a+rwX $PS4_MNT

echo ''
echo 'OK → SSD mounted on $PS4_MNT'
cd /ps4hdd
ls 
read -p 'Enter... Vous pouvez fermer ce terminal, vous pouvez utiliser votre explorateur de fichier, dossier /ps4hdd'
"
}

# ── Unmount ─────────────────────────────────────────────────────────
do_unmount_ps4() {
    xterm -hold -e bash -c "
echo '--- PS4 SSD Unmount ---'
echo ''

sudo umount $PS4_MNT 2>/dev/null
sudo cryptsetup remove ps4hdd 2>/dev/null

echo 'OK → unmounted'
read -p 'Enter...'
"
}

# ── YAD Interface ─────────────────────────────────────────────────────
tab_mount_ps4() {
    yad --plug="$KEY" --tabnum=4 \
        --form \
        --image="/usr/share/hybryde/SquareGlass/Harddrive 2.png" --image-on-top \
        --text="<b><span foreground='#EF9A9A'>PS4 SSD — Quick mount</span></b>

Key: <tt>$PS4_KEY</tt>
Partition: <tt>$PS4_DEV</tt>
Mount: <tt>$PS4_MNT</tt>
" \
        --field="🚀 Monter SSD (Belize / Aeolia)":BTN 'bash -c do_mount_ps4_belize' \
        --field="🚀 Monter SSD (Baikal)":BTN 'bash -c do_mount_ps4_baikal' \
        --field="⏏ Unmount SSD":BTN 'bash -c do_unmount_ps4' \
        "" "" "" "" "" "" &
}

export -f do_mount_ps4_belize
export -f do_mount_ps4_baikal
export -f do_unmount_ps4
export -f tab_mount_ps4

#========================================================================
# TAB 6 — Help (10 configurable documents)
#
# FIX v1.1: the old --list + --dclick-action approach opened
# a yad file selector (Thunar) instead of the PDF.
# New approach: --form with BTN per document → direct call to
# preview_pdf (preview) or xdg-open (default reader).
# Paths are expanded at plug generation (not in a subshell)
# so no variable scope issues.
#
# ─── Edit names and paths here ──────────────────────────────────────
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
    # Dynamically build --form fields
    # Each document → a LBL separator + two BTNs (Preview / Open)
    # Paths are expanded HERE (in main shell) and passed
    # literally in BTN actions between escaped single quotes.
    local fields=()

    for i in "${!AIDE_LABELS[@]}"; do
        local lbl="${AIDE_LABELS[$i]}"
        local fpath="${AIDE_PATHS[$i]}"
        # Expand ~ → $HOME if present
        fpath="${fpath/#\~/$HOME}"

        fields+=(
            --field="":LBL ""
            --field="<b>  📄 ${lbl}</b>":LBL ""
            # Preview button: calls preview_pdf with the literal path
            --field="     🔍 Preview":BTN "bash -c \"preview_pdf '${fpath}'\""
            # Open button: calls xdg-open directly, without going through yad --file
            --field="     📂 Open in PDF reader":BTN "bash -c \"xdg-open '${fpath}' >/dev/null 2>&1 &\""
        )
    done

    # Padding to push fields toward the top of the scrollable area
    local pad=()
    for _ in $(seq 1 6); do pad+=("" "" "" ""); done

    yad --plug="$KEY" --tabnum=12 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Notepad 4.png" \
        --image-on-top \
        --text="<big><b><span foreground='#B39DDB'>📖 PS4 Linux Help</span></b></big>
<small>🔍 Preview = page 1 text + reader button  •  📂 Open = direct PDF reader</small>\n" \
        "${fields[@]}" \
        "${pad[@]}" \
        &
}

#========================================================================
# TAB 7 — Network / Transfer
#========================================================================

do_net_scan() {
    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-netscan-XXXX.sh)
    cat > "$tmpscript" << 'EOF'
#!/bin/bash
echo "=== Local network scan (nmap -sn) ==="
echo ""
if ! command -v nmap >/dev/null 2>&1; then
    echo "ERROR: nmap not installed"
    echo "  sudo apt install nmap"
    read -rp "[Press Enter to close]"
    exit 1
fi
SUBNET=$(ip route | awk '/scope link/ {print $1}' | head -1)
echo "Detected subnet: $SUBNET"
echo ""
nmap -sn "$SUBNET" 2>/dev/null | grep -E "Nmap scan|Host is up|report for"
echo ""
read -rp "[Press Enter to close]"
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
        --title="Select source folder to copy" \
        --file --directory --filename="$HOME/" \
        --button="Cancel:1" --button="Select:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$src" ] && return

    local dst
    dst=$(yad --center --borders=10 \
        --title="Destination on /ps4hdd" \
        --form \
        --text="Destination folder on /ps4hdd:" \
        --field="Destination path:":TEXT "/ps4hdd/game/" \
        --button="Cancel:1" --button="Confirm:0" \
        --width=540)
    [ $? -ne 0 ] || [ -z "$dst" ] && return
    dst=$(echo "$dst" | cut -d'|' -f1)

    yad_confirm "Launch rsync transfer?\n\n  Source: <tt>$src</tt>\n  Dest:   <tt>$dst</tt>\n\n⚠️  May take several minutes depending on size." || return

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-rsync-XXXX.sh)
    printf '#!/bin/bash\nrsync -av --progress "%s" "%s"\necho ""\nread -rp "[Press Enter to close]"\n' "$src" "$dst" > "$tmpscript"
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="rsync to ps4hdd" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="rsync to ps4hdd" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="rsync to ps4hdd" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "rsync to ps4hdd" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_rsync_to_ps4hdd

do_ssh_ps4() {
    local out
    out=$(yad --center --borders=10 \
        --title="SSH to PS4" \
        --form \
        --text="<b>SSH connection to PS4</b>" \
        --field="PS4 IP address:":TEXT "192.168.1.xxx" \
        --field="Username:":TEXT "root" \
        --field="SSH Port:":NUM "22!1..65535!1" \
        --button="Cancel:1" --button="Connect:0" \
        --width=460)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local ip user port
    ip=$(echo "$out"   | cut -d'|' -f1)
    user=$(echo "$out" | cut -d'|' -f2)
    port=$(echo "$out" | cut -d'|' -f3)

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-ssh-XXXX.sh)
    printf '#!/bin/bash\necho "SSH connection: %s@%s:%s"\nssh -p "%s" "%s@%s"\nread -rp "[Press Enter to close]"\n' \
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
    yad --plug="$KEY" --tabnum=5 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/My Network Places 7.png" --image-on-top \
        --text="<big><b><span foreground='#81D4FA'>🌐 Network / Transfer</span></b></big>
Network scan, file transfer to /ps4hdd, SSH connection.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Local network —</b>":LBL "" \
        --field="  🔍 Scan local network (nmap)":BTN 'bash -c "do_net_scan"' \
        \
        --field="":LBL "" \
        --field="<b>— File transfer —</b>":LBL "" \
        --field="  📁 Copy a folder to /ps4hdd (rsync)":BTN 'bash -c "do_rsync_to_ps4hdd"' \
        \
        --field="":LBL "" \
        --field="<b>— Remote access —</b>":LBL "" \
        --field="  🖥  SSH connection to PS4":BTN 'bash -c "do_ssh_ps4"' \
        \
        "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# TAB 8 — Diagnostic / Logs
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

echo "=== PS4 Linux Prerequisites ==="
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
    warn "vulkaninfo" "not available"
fi

echo ""
echo "=== Active GPU Driver ==="
lspci -k 2>/dev/null | grep -A2 "VGA" | head -6

echo ""
echo "=== Mesa version ==="
if command -v glxinfo >/dev/null 2>&1; then
    glxinfo 2>/dev/null | grep -i "OpenGL version\|renderer" | head -3
else
    warn "glxinfo" "not available (sudo apt install mesa-utils)"
fi

echo ""
read -rp "[Press Enter to close]"
EOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="Prerequisites Diagnostic" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="Prerequisites Diagnostic" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="Prerequisites Diagnostic" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "Diagnostic Prérequis" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_diag_prereqs

do_dmesg_live() {
    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-dmesg-XXXX.sh)
    cat > "$tmpscript" << 'EOF'
#!/bin/bash
echo "=== Real-time dmesg — USB/SCSI/DRM/amdgpu filter ==="
echo "Ctrl+C to stop"
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
sudo cryptsetup status ps4hdd 2>/dev/null || echo "(ps4hdd mapping inactive)"
echo ""
echo "=== mount | grep ps4 ==="
mount 2>/dev/null | grep -E "ps4|ufs" || echo "(nothing mounted)"
echo ""
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null
echo ""
read -rp "[Press Enter to close]"
EOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="PS4 SSD Status" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="PS4 SSD Status" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="PS4 SSD Status" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "État SSD PS4" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_cryptsetup_status

tab_diagnostic() {
    yad --plug="$KEY" --tabnum=6 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Clock 3.png" --image-on-top \
        --text="<big><b><span foreground='#FFF176'>🔍 Diagnostic / Logs</span></b></big>
Prerequisites check, real-time kernel logs, PS4 SSD status.\n" \
        \
        --field="":LBL "" \
        --field="<b>— System prerequisites —</b>":LBL "" \
        --field="  ✅ Check all PS4 Linux prerequisites":BTN 'bash -c "do_diag_prereqs"' \
        \
        --field="":LBL "" \
        --field="<b>— Kernel logs —</b>":LBL "" \
        --field="  📋 Real-time dmesg (USB / DRM / amdgpu)":BTN 'bash -c "do_dmesg_live"' \
        \
        --field="":LBL "" \
        --field="<b>— PS4 SSD Status —</b>":LBL "" \
        --field="  💽 cryptsetup status + mount + lsblk":BTN 'bash -c "do_cryptsetup_status"' \
        \
        "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# TAB 9 — Mesa environment variables
#========================================================================

MESA_ENV_FILE="$CONF_DIR/mesa-env.conf"
MESA_PROFILES_DIR="$CONF_DIR/mesa-profiles"
mkdir -p "$MESA_PROFILES_DIR"
export MESA_ENV_FILE MESA_PROFILES_DIR

# Default profile if missing
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
    # Read current file
    source "$MESA_ENV_FILE" 2>/dev/null

    out=$(yad --center --borders=10 \
        --title="Mesa Variables" \
        --form \
        --text="<b>Mesa/Vulkan environment variables</b>\n<small>Leave empty = not exported</small>\n" \
        --field="RADV_DEBUG :":TEXT "${RADV_DEBUG:-}" \
        --field="MESA_DEBUG :":TEXT "${MESA_DEBUG:-}" \
        --field="AMD_DEBUG :":TEXT "${AMD_DEBUG:-}" \
        --field="VK_ICD_FILENAMES :":TEXT "${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/radeon_icd.x86_64.json}" \
        --field="mesa_glthread :":CBX "true!false" \
        --field="RADV_PERFTEST :":TEXT "${RADV_PERFTEST:-}" \
        --button="Cancel:1" --button="Save:0" \
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
    yad_info "✓ Variables saved to:\n<tt>$MESA_ENV_FILE</tt>"
}
export -f do_mesa_edit_env

do_mesa_save_profile() {
    local out
    out=$(yad --center --borders=10 \
        --title="Save a profile" \
        --form \
        --text="Mesa profile name to save:" \
        --field="Name:":TEXT "profil-debug" \
        --button="Cancel:1" --button="Save:0" \
        --width=400)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local name; name=$(echo "$out" | cut -d'|' -f1 | tr ' ' '-')
    cp "$MESA_ENV_FILE" "$MESA_PROFILES_DIR/$name.conf"
    yad_info "✓ Profile saved: <b>$name</b>\n<tt>$MESA_PROFILES_DIR/$name.conf</tt>"
}
export -f do_mesa_save_profile

do_mesa_load_profile() {
    local profiles=()
    for f in "$MESA_PROFILES_DIR"/*.conf; do
        [ -f "$f" ] && profiles+=("$(basename "$f" .conf)")
    done
    [ "${#profiles[@]}" -eq 0 ] && yad_info "No saved profiles." && return

    local sel
    sel=$(yad --center --borders=10 \
        --title="Load a Mesa profile" \
        --list \
        --text="Select the profile to load:" \
        --column="Profile" \
        "${profiles[@]}" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="Load:0" \
        --width=400 --height=300)
    [ $? -ne 0 ] || [ -z "$sel" ] && return
    sel="${sel//|/}"
    cp "$MESA_PROFILES_DIR/$sel.conf" "$MESA_ENV_FILE"
    yad_info "✓ Profile loaded: <b>$sel</b>"
}
export -f do_mesa_load_profile

do_mesa_launch_app() {
    local app
    app=$(yad --center --borders=10 \
        --title="Launch application with Mesa variables" \
        --file --filename="$HOME/" \
        --button="Cancel:1" --button="Launch:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$app" ] && return
    [ ! -f "$app" ] && yad_err "File not found." && return

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-mesa-launch-XXXX.sh)
    {
        echo "#!/bin/bash"
        echo "echo '=== Active Mesa Variables ==='"
        # Export each non-empty variable
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
        echo "read -rp '[Press Enter to close]'"
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
    content=$(cat "$MESA_ENV_FILE" 2>/dev/null || echo "(no variables defined)")
    yad --center --borders=10 \
        --title="Current Mesa Variables" \
        --text-info --width=560 --height=300 \
        --button="Close:0" \
        <<< "$content"
}
export -f do_mesa_show_current

tab_mesa_env() {
    yad --plug="$KEY" --tabnum=8 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Go Daddy.png" --image-on-top \
        --text="<big><b><span foreground='#FFCC80'>⚙  Mesa / Vulkan Variables</span></b></big>
Set RADV_DEBUG, MESA_DEBUG, AMD_DEBUG… save profiles
and launch an application with these pre-exported variables.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Edit —</b>":LBL "" \
        --field="  ✏  Edit Mesa/Vulkan variables":BTN 'bash -c "do_mesa_edit_env"' \
        --field="  📋 Show current variables":BTN 'bash -c "do_mesa_show_current"' \
        \
        --field="":LBL "" \
        --field="<b>— Profiles —</b>":LBL "" \
        --field="  💾 Save current profile":BTN 'bash -c "do_mesa_save_profile"' \
        --field="  📂 Load a profile":BTN 'bash -c "do_mesa_load_profile"' \
        \
        --field="":LBL "" \
        --field="<b>— Launch —</b>":LBL "" \
        --field="  🚀 Launch an application with active variables":BTN 'bash -c "do_mesa_launch_app"' \
        \
        "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# TAB 10 — PS4 Kernel Compilation (Jaguar / LTO)
#========================================================================

# Built-in documentation — text shown in tab
KERNEL_DOC="<b>Optimisation kernel pour PS4 (Jaguar / GCN 1.1)</b>

<b>Pourquoi kernel 5.15.x &gt; 6.x sur PS4 ?</b>
• GPU Sea Islands / GCN 1.1 (Liverpool) — no official support
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
        --title="Kernel source folder" \
        --file --directory --filename="$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/")" \
        --button="Cancel:1" --button="Select:0" \
        --width=860 --height=540)
    [ $? -ne 0 ] || [ -z "$d" ] && return
    echo "$d" > "$KERNEL_SRC_FILE"
    yad_info "✓ Kernel sources set:\n<tt>$d</tt>"
}
export -f do_kernel_select_src

do_kernel_menuconfig_standard() {
    local src
    src=$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/linux-kernel")
    [ ! -d "$src" ] && yad_err "Source folder not found:\n<tt>$src</tt>\nClick <b>Select sources</b>." && return

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-menuconfig-XXXX.sh)
    cat > "$tmpscript" << MEOF
#!/bin/bash
echo "=== Standard menuconfig ==="
echo "Sources: $src"
echo ""
cd "$src" || exit 1
make menuconfig
echo ""
read -rp "[Press Enter to close]"
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
    [ ! -d "$src" ] && yad_err "Source folder not found:\n<tt>$src</tt>\nClick <b>Select sources</b>." && return

    # Check clang/lld
    if ! command -v clang >/dev/null 2>&1 || ! command -v ld.lld >/dev/null 2>&1; then
        yad_err "clang or lld not installed.\n<b>sudo apt install clang lld llvm</b>"
        return
    fi

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-menuconfig-lto-XXXX.sh)
    cat > "$tmpscript" << MEOF
#!/bin/bash
echo "=== menuconfig LLVM=1 (LTO options visible) ==="
echo "Sources: $src"
echo "Compiler: clang $(clang --version 2>/dev/null | head -1)"
echo ""
cd "$src" || exit 1
make LLVM=1 menuconfig
echo ""
read -rp "[Press Enter to close]"
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
    [ ! -d "$src" ] && yad_err "Source folder not found:\n<tt>$src</tt>" && return

    if ! command -v clang >/dev/null 2>&1; then
        yad_err "clang not installed.\n<b>sudo apt install clang lld llvm</b>"
        return
    fi

    local jobs
    jobs=$(nproc)

    # Allow the user to adjust the number of jobs
    local out
    out=$(yad --center --borders=10 \
        --title="Kernel FULL LTO Compilation — Jaguar" \
        --form \
        --text="<b>Full LTO Compilation for PS4 (Jaguar / btver2)</b>\n\n⚠️  <b>Consumes a lot of RAM</b> — 24GB minimum recommended for Full LTO.\nWith 16GB, use <b>-j2</b> or <b>-j1</b> to avoid freezing.\n" \
        --field="Number of jobs (-j):":NUM "${jobs}!1..$(nproc)!1" \
        --field="Extra flags:":TEXT "" \
        --button="Cancel:1" --button="🚀 Compile:0" \
        --width=600)
    [ $? -ne 0 ] || [ -z "$out" ] && return
    local njobs extra_flags
    njobs=$(echo "$out"      | cut -d'|' -f1)
    extra_flags=$(echo "$out" | cut -d'|' -f2)

    yad_confirm "Launch Full LTO kernel compilation?\n\n  Sources: <tt>$src</tt>\n  Jobs:    <b>-j${njobs}</b>\n\n⚠️  May take <b>several hours</b>.\nMonitor RAM with <tt>monitor-compilation.sh</tt>." || return

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-compile-kernel-XXXX.sh)
    cat > "$tmpscript" << CEOF
#!/bin/bash
cd "$src" || exit 1
echo "=== Full LTO Jaguar Kernel Compilation ==="
echo "Jobs:    $njobs"
echo "Sources: $src"
echo "Start:   \$(date)"
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
echo "=== End: \$(date) ==="
echo ""
if [ -f arch/x86/boot/bzImage ]; then
    echo "OK  bzImage produced: arch/x86/boot/bzImage"
    echo "  → Copy it to /boot on your PS4"
else
    echo "ERROR: bzImage not found"
fi
echo ""
read -rp "[Press Enter to close]"
CEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="LTO Kernel Compilation" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="LTO Kernel Compilation" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="LTO Kernel Compilation" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "LTO Kernel Compilation" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_kernel_compile_lto

do_kernel_copy_bzimage() {
    local src
    src=$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/linux-kernel")
    local bzimage="$src/arch/x86/boot/bzImage"
    [ ! -f "$bzimage" ] && yad_err "bzImage not found:\n<tt>$bzimage</tt>\nCompile the kernel first." && return

    local dst
    dst=$(yad --center --borders=10 \
        --title="Copy bzImage" \
        --form \
        --text="bzImage copy destination:" \
        --field="Destination:":TEXT "/boot/bzImage-ps4-lto" \
        --button="Cancel:1" --button="Copy:0" \
        --width=520)
    [ $? -ne 0 ] || [ -z "$dst" ] && return
    dst=$(echo "$dst" | cut -d'|' -f1)

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-cpbz-XXXX.sh)
    cat > "$tmpscript" << CPEOF
#!/bin/bash
echo "Copying bzImage..."
sudo cp "$bzimage" "$dst" && echo "OK - bzImage copied: $dst" || echo "Copy ERROR"
echo ""
ls -lh "$dst" 2>/dev/null
echo ""
read -rp "[Press Enter to close]"
CPEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="Copy bzImage" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="Copy bzImage" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="Copy bzImage" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "Copie bzImage" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_kernel_copy_bzimage

do_kernel_show_doc() {
    # Afficher la documentation complète en texte brut dans yad --text-info
    local doc_text
    doc_text="Kernel Optimization 6.15.4 — PS4 Jaguar / GCN 1.1
=======================================================================

WHY IS THE 6.x KERNEL SLOWER ON PS4?
=======================================================================
The PS4 uses a Sea Islands / GCN 1.1 GPU (Liverpool).
No Linux kernel officially supports this hardware.

(1) Driver AMD (amdgpu) non adapté pour GCN1.1
    - Kernel 5.15.x : moins de régressions GCN1.1, amdgpu plus léger,
      gestion clock/powerplay/fences plus stable.
    - Kernel 6.x : modifications IRQ, memory barriers, power management,
      VM scheduler qui améliorent RDNA/Vega mais dégradent les vieux GCN.

(2) Protections sécurité (Spectre, Meltdown, Retpoline, IBPB, IBRS)
    - Coûtent des cycles sur Jaguar 1.6 GHz.
    - Kernel 5.15 activates fewer → higher FPS.
    - Heaven : 5.15.15 = 1200 pts | 6.15.4 = ~965 pts
    - Potential gain: +20 to +40% on some benchmarks.

=======================================================================
MENUCONFIG WITH LTO OPTIONS VISIBLE
=======================================================================
Without LLVM=1, LTO options do not appear in menuconfig.
Correct command: make LLVM=1 menuconfig

=======================================================================
KEY .config OPTIONS FOR PS4 / JAGUAR
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
JAGUAR COMPILATION FLAGS (btver2)
=======================================================================
KCFLAGS='-march=btver2 -mtune=btver2 -O3 -fomit-frame-pointer
         -flto -mno-sse4a -mno-xop -mno-tbm -pipe'

Full command:
make -j\$JOBS LLVM=1
    CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
    STRIP=llvm-strip OBJCOPY=llvm-objcopy
    HOSTCC=clang HOSTCXX=clang++ HOSTAR=llvm-ar HOSTLD=ld.lld
    KCFLAGS='...'

=======================================================================
RECOMMENDED PS4 BOOTARGS
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
RAM MEMORY — FULL LTO
=======================================================================
Full LTO consumes a lot of RAM.
With i3 + 16GB: use -j2 or -j1 to avoid freezing.
Provided scripts: compile-i3-fulllto-v2.sh + monitor-compilation.sh
"

    echo "$doc_text" | yad --center --borders=10 \
        --title="PS4 Jaguar Kernel Documentation" \
        --text-info --scroll \
        --width=820 --height=620 \
        --button="Close:0"
}
export -f do_kernel_show_doc

tab_kernel() {
    local src
    src=$(cat "$KERNEL_SRC_FILE" 2>/dev/null || echo "$HOME/linux-kernel")

    yad --plug="$KEY" --tabnum=9 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Control Panel 1.png" --image-on-top \
        --text="<big><b><span foreground='#C5E1A5'>🐧 PS4 Kernel Compilation (Jaguar / LTO)</span></b></big>
Kernel optimization for PS4 GCN 1.1 GPU (Liverpool).
Current sources: <tt>${src}</tt>\n" \
        \
        --field="":LBL "" \
        --field="<b>— Kernel sources —</b>":LBL "" \
        --field="  📂 Select kernel source folder":BTN 'bash -c "do_kernel_select_src"' \
        \
        --field="":LBL "" \
        --field="<b>— Configuration (menuconfig) —</b>":LBL "" \
        --field="  ⚙  Standard menuconfig  (make menuconfig)":BTN 'bash -c "do_kernel_menuconfig_standard"' \
        --field="  ⚡ LLVM/LTO menuconfig   (make LLVM=1 menuconfig)":BTN 'bash -c "do_kernel_menuconfig_lto"' \
        --field="  <small><i>→ LLVM=1 required to see Full LTO / Thin LTO options</i></small>":LBL "" \
        \
        --field="":LBL "" \
        --field="<b>— Full LTO Jaguar (btver2) Compilation —</b>":LBL "" \
        --field="  🚀 Compile kernel (Full LTO, -march=btver2)":BTN 'bash -c "do_kernel_compile_lto"' \
        --field="  <small><i>⚠ Requires clang/lld/llvm — large RAM needed (24GB ideal, 16GB: -j2)</i></small>":LBL "" \
        \
        --field="":LBL "" \
        --field="<b>— Deployment —</b>":LBL "" \
        --field="  💾 Copy bzImage to /boot (sudo)":BTN 'bash -c "do_kernel_copy_bzimage"' \
        \
        --field="":LBL "" \
        --field="<b>— Documentation —</b>":LBL "" \
        --field="  📖 Complete guide: Jaguar kernel, LTO, bootargs, Mesa":BTN 'bash -c "do_kernel_show_doc"' \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================
# TAB 11 — GIT PS4 KERNELS + ORBIS
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
        --title="Download PS4 Kernel" \
        --list \
        --text="Select PS4 branch:" \
        --column="Branch" \
        "${branches[@]}" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="🚀 Download:0" \
        --width=400 --height=280)
    
    [ $? -ne 0 ] || [ -z "$branch" ] && return
    branch="${branch//|/}"

    local dest="$KERNELS_DIR/linux-ps4-$branch"
    [ -d "$dest" ] && yad_confirm "Existing folder:\n<tt>$dest</tt>\n\nDelete and re-download?" || rm -rf "$dest"
    
    run_in_term "🚀 Git PS4 Kernel — $branch" "
        cd '$KERNELS_DIR'
        echo '=== Downloading PS4 kernel: $branch ==='
        git clone -b '$branch' --depth=1 https://github.com/crashniels/linux.git linux-ps4-$branch
        echo '=== PS4 Kernel sources downloaded ==='
        ls -la
        echo ''
        read -rp '[Press Enter to open folder]'
        sleep 1 && xdg-open '$KERNELS_DIR/linux-ps4-$branch'
    "
    
    yad_info "✓ PS4 Kernel $branch\n📂 <tt>$dest</tt>"
}
export -f do_git_ps4_kernel

#------------------------------------------------------------------------
# feeRnt/ps4-linux-12xx — kernels PS4 alternatifs
#------------------------------------------------------------------------
do_git_feernt_kernel() {
    # Récupérer les branches dynamiquement depuis l'API GitHub
    local branches_raw
    branches_raw=$(curl -s --max-time 8 \
        "https://api.github.com/repos/feeRnt/ps4-linux-12xx/branches" \
        2>/dev/null)

    local yad_branches=()
    if [ -n "$branches_raw" ] && echo "$branches_raw" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        # Branches fetched from API
        while IFS= read -r b; do
            [ -n "$b" ] && yad_branches+=("$b")
        done < <(echo "$branches_raw" | python3 -c "
import sys, json
branches = json.load(sys.stdin)
# master first, then others sorted
names = [b['name'] for b in branches]
if 'master' in names:
    names.remove('master')
    names = ['master'] + sorted(names)
else:
    names = sorted(names)
for n in names:
    print(n)
" 2>/dev/null)
    fi

    # Fallback if API unreachable or empty
    if [ "${#yad_branches[@]}" -eq 0 ]; then
        yad_branches=("master" "ps4-6.1.y" "ps4-6.6.y" "ps4-5.15.y")
    fi

    local branch
    branch=$(yad --center --borders=10 \
        --title="feeRnt — ps4-linux-12xx" \
        --list \
        --text="<b>feeRnt/ps4-linux-12xx</b>\nAlternative PS4 kernels\n<small>https://github.com/feeRnt/ps4-linux-12xx</small>\n\nSelect a branch:" \
        --column="Branch" \
        "${yad_branches[@]}" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="🚀 Download:0" \
        --width=420 --height=320)

    [ $? -ne 0 ] || [ -z "$branch" ] && return
    branch="${branch//|/}"

    local dest="$KERNELS_DIR/feeRnt-ps4-linux-$branch"

    if [ -d "$dest" ]; then
        yad_confirm "Existing folder:\n<tt>$dest</tt>\n\nDelete and re-download?"
        [ $? -ne 0 ] && return
        rm -rf "$dest"
    fi

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-feernt-XXXX.sh)
    cat > "$tmpscript" << FEOF
#!/bin/bash
echo '=== Downloading feeRnt/ps4-linux-12xx ==='
echo "Branch: $branch"
echo "Destination: $dest"
echo ''
cd '$KERNELS_DIR'
git clone -b '$branch' --depth=1 \
    https://github.com/feeRnt/ps4-linux-12xx.git \
    "feeRnt-ps4-linux-$branch"

if [ \$? -ne 0 ] || [ ! -d '$dest' ]; then
    echo ''
    echo '✗ Clone failed'
    echo '  Check your connection or that the branch exists.'
    read -rp '[Press Enter to close]'
    exit 1
fi

echo ''
echo '=== Contents ==='
ls -la '$dest'
echo ''
echo "✓ feeRnt ps4-linux-12xx ($branch) downloaded"
echo "  $dest"
echo ''
read -rp '[Press Enter to open folder]'
sleep 1 && xdg-open '$dest' 2>/dev/null
FEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="🐧 feeRnt ps4-linux — $branch" -e "bash $tmpscript" ;;
        gnome-terminal) gnome-terminal --title="🐧 feeRnt ps4-linux — $branch" -- bash "$tmpscript" ;;
        mate-terminal)  mate-terminal  --title="🐧 feeRnt ps4-linux — $branch" -e "bash $tmpscript" ;;
        *)              xterm -title "🐧 feeRnt ps4-linux — $branch" -e bash "$tmpscript" ;;
    esac

    sleep 1
    [ -d "$dest" ] && \
        yad_info "✓ feeRnt/ps4-linux-12xx ($branch) downloaded\n📂 <tt>$dest</tt>"
}
export -f do_git_feernt_kernel
do_git_orbis() {
    local out
    out=$(yad --center --borders=10 \
        --title="OpenOrbis PS4 Toolchain" \
        --form \
        --text="<b>Install OpenOrbis Toolchain</b>\n\n<small>Automatically downloads the latest release from GitHub\nhttps://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain</small>\n" \
        --field="Folder name:":TEXT "Orbis" \
        --button="Cancel:1" --button="🚀 Install:0" \
        --width=540)
    [ $? -ne 0 ] || [ -z "$out" ] && return

    local dest_name
    dest_name=$(echo "$out" | cut -d'|' -f1)
    dest_name="${dest_name//|/}"
    [ -z "$dest_name" ] && dest_name="Orbis"
    local dest="$PROJECT_DIR/$dest_name"

    # Direct heredoc — bypasses run_in_term to avoid issues
    # with nested variable expansion and inline Python
    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-orbis-XXXX.sh)
    cat > "$tmpscript" << ORBEOF
#!/bin/bash
set -e
cd '$PROJECT_DIR'

echo '=== Installing OpenOrbis PS4 Toolchain ==='
echo "Destination: $dest"
echo ''

echo '--- Dependencies ---'
sudo apt-get update -qq
sudo apt-get install -y clang lld make curl tar python3 2>&1 | tail -5

# libssl1.1 required by PkgTool.Core (.NET — incompatible with libssl3)
if ! dpkg -l libssl1.1 2>/dev/null | grep -q '^ii'; then
    echo '  → Installing libssl1.1 (required by PkgTool.Core)...'
    TMP_SSL=\$(mktemp /tmp/libssl1.1-XXXX.deb)
    curl -L --progress-bar \
        "http://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.1_1.1.1w-0+deb11u5_amd64.deb" \
        -o "\$TMP_SSL"
    sudo dpkg -i "\$TMP_SSL" 2>&1 | tail -3
    rm -f "\$TMP_SSL"
fi

# DOTNET variable required for libicu78 (Forky has no libicu66)
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
grep -q 'DOTNET_SYSTEM_GLOBALIZATION_INVARIANT' "\$HOME/.bashrc" || \
    echo 'export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1' >> "\$HOME/.bashrc"
echo '✓ Dependencies OK'
echo ''

echo '--- Fetching latest release ---'
API_URL="https://api.github.com/repos/OpenOrbis/OpenOrbis-PS4-Toolchain/releases/latest"
JSON=\$(curl -s "\$API_URL")
if [ -z "\$JSON" ] || echo "\$JSON" | grep -q '"message".*"Not Found"'; then
    echo '✗ Impossible de joindre l'\''API GitHub'
    echo '  Check your internet connection'
    read -rp '[Press Enter to close]'
    exit 1
fi

VERSION=\$(echo "\$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name','?'))" 2>/dev/null)
echo "Detected version: \$VERSION"

DOWNLOAD_URL=\$(echo "\$JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assets = data.get('assets', [])
# Priority 1: contains 'linux' + .tar.gz
for asset in assets:
    name = asset['name'].lower()
    if 'linux' in name and name.endswith('.tar.gz'):
        print(asset['browser_download_url']); break
else:
    # Priority 2: any .tar.gz except windows/mac/darwin/osx
    for asset in assets:
        name = asset['name'].lower()
        skip = any(x in name for x in ['windows', 'win', 'mac', 'darwin', 'osx', 'macos'])
        if name.endswith('.tar.gz') and not skip:
            print(asset['browser_download_url']); break
    else:
        # Priority 3: first available .tar.gz
        for asset in assets:
            if asset['name'].lower().endswith('.tar.gz'):
                print(asset['browser_download_url']); break
" 2>/dev/null)

if [ -z "\$DOWNLOAD_URL" ]; then
    echo '✗ No .tar.gz file found in the release'
    echo '  Available assets:'
    echo "\$JSON" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets',[]): print('  -', a['name'])
" 2>/dev/null
    read -rp '[Press Enter to close]'
    exit 1
fi
echo "URL : \$DOWNLOAD_URL"
echo ''

echo '--- Download ---'
curl -L --progress-bar "\$DOWNLOAD_URL" -o /tmp/toolchain.tar.gz
if [ ! -s /tmp/toolchain.tar.gz ]; then
    echo '✗ Download failed or empty file'
    read -rp '[Press Enter to close]'
    exit 1
fi
SIZE=\$(stat -c%s /tmp/toolchain.tar.gz)
echo "Size: \$(numfmt --to=iec \$SIZE 2>/dev/null || echo \$SIZE bytes)"
if [ "\$SIZE" -lt 500000 ]; then
    echo '✗ File too small — probably an error'
    rm -f /tmp/toolchain.tar.gz
    read -rp '[Press Enter to close]'
    exit 1
fi
echo ''

echo '--- Extraction ---'
rm -rf '$dest'
mkdir -p '$dest'
tar -xzf /tmp/toolchain.tar.gz -C '$dest' --strip-components=1 2>&1 || \
    tar -xzf /tmp/toolchain.tar.gz -C '$dest' 2>&1
rm -f /tmp/toolchain.tar.gz
echo '✓ Extraction complete'
echo ''

echo '--- .bashrc configuration ---'
BASHRC="\$HOME/.bashrc"
grep -q 'OO_PS4_TOOLCHAIN' "\$BASHRC" || \
    echo "export OO_PS4_TOOLCHAIN='$dest'" >> "\$BASHRC"
grep -q '$dest/bin/linux' "\$BASHRC" || \
    echo "export PATH=\"\\\$PATH:$dest/bin/linux\"" >> "\$BASHRC"
export OO_PS4_TOOLCHAIN='$dest'
export PATH="\$PATH:$dest/bin/linux"
echo '✓ Variables added to ~/.bashrc'
echo "  OO_PS4_TOOLCHAIN=$dest"
echo ''

echo '--- SDK contents ---'
ls -la '$dest'
echo ''

if [ -d '$dest/samples/hello_world' ]; then
    echo '--- hello_world compilation test ---'
    cd '$dest/samples/hello_world'
    make 2>&1 && echo '✓ Compilation successful 🎉' || echo '⚠ Compilation failed (ignored)'
    echo ''
fi

echo '============================================'
echo "✓ OpenOrbis \$VERSION installed in:"
echo "  $dest"
echo ''
echo 'To use in a new terminal:'
echo '  source ~/.bashrc'
echo '============================================'
echo ''
read -rp '[Press Enter to open SDK folder]'
sleep 1 && xdg-open '$dest' 2>/dev/null
ORBEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="🚀 Installation OpenOrbis" -e "bash $tmpscript" ;;
        gnome-terminal) gnome-terminal --title="🚀 Installation OpenOrbis" -- bash "$tmpscript" ;;
        mate-terminal)  mate-terminal  --title="🚀 Installation OpenOrbis" -e "bash $tmpscript" ;;
        *)              xterm -title "🚀 Installation OpenOrbis" -e bash "$tmpscript" ;;
    esac

    sleep 1
    if [ -d "$dest" ]; then
        yad_info "✓ OpenOrbis installed\n📂 <tt>$dest</tt>\n\nReload your terminal or: <tt>source ~/.bashrc</tt>"
    fi
}
export -f do_git_orbis

do_git_payloads() {
    local dest="$PROJECT_DIR/ps4-linux-payloads"

    if [ -d "$dest" ]; then
        yad_confirm "Existing folder:\n<tt>$dest</tt>\n\nRe-download from scratch?"
        if [ $? -eq 0 ]; then
            rm -rf "$dest"
        else
            # Folder already there → just recompile
            run_in_term "🔧 Compile PS4 Linux Payloads" "
                cd '$dest/linux'
                echo '=== PS4 Linux Payloads Compilation ==='
                make
                echo ''
                echo '=== Compilation complete ==='
                ls -la
                echo ''
                read -rp '[Press Enter to close]'
            "
            return
        fi
    fi

    run_in_term "🚀 Git + Compile PS4 Linux Payloads" "
        cd '$PROJECT_DIR'
        echo '=== Downloading ps4-linux-payloads ==='
        git clone https://github.com/ps4boot/ps4-linux-payloads
        echo ''
        echo '=== make Compilation ==='
        cd ps4-linux-payloads/linux
        make
        echo ''
        echo '=== Done ==='
        ls -la
        echo ''
        read -rp '[Press Enter to open folder]'
        sleep 1 && xdg-open '$dest'
    "
    yad_info "✓ PS4 Linux Payloads compiled\n📂 <tt>$dest</tt>"
}
export -f do_git_payloads

do_payloads_readme() {
    local readme_text="The host with precompiled Linux payloads works only with GoldHEN v2.4b18.5/v2.4b18.6 BinLoader.
Simply open your web browser and cache the host; it will also work offline.

▶️  https://ps4boot.github.io  (bouton ci-dessous pour ouvrir)

You will find Linux payloads for your firmware, as well as additional payloads.
The rest is already included in GoldHEN.

━━━  Automatic placement of boot files  ━━━
The kernel (bzImage) and initramfs.cpio.gz are now automatically copied to /data/linux/boot
on the internal disk from the external FAT32 partition.
→ No external disk is needed for the recovery interface, except during the first boot.

━━━  RTC time passed to initramfs  ━━━
The current OrbisOS time is added to the kernel command line (time=CURRENTTIME),
ensuring the correct time is set at boot instead of the default value of 1970,
even if the RTC hardware cannot be read directly.
A prepared initramfs is needed to read the time from the command line and set it.

━━━  Default internal path  ━━━
  /data/linux/boot
The rest comes from the initramfs.cpio.gz initialization configuration.

Access without USB stick: transfer via FTP to your PS4:
  /data/linux/boot/bzImage
  /data/linux/boot/initramfs.cpio.gz

USB devices take priority: if a stick is connected, the system will use
bzImage and initramfs.cpio.gz from that stick.

You can add a text file (bootargs.txt) to modify the command line.
The vram.txt file allows you to modify VRAM via a text file.

━━━  Important notes  ━━━
★  With GoldHEN v2.4b18.5/v2.4b18.6, use .elf files instead of .bin files;
   this works better and guarantees 100% success.

★  Do not use PRO payloads for Phat or Slim formats.

★  UART (if needed) — currently disabled, does not work on recent kernels:
     Aeolia / Belize: console=uart8250,mmio32,0xd0340000
     Baikal:          console=uart8250,mmio32,0xC890E000"

    echo "$readme_text" | yad --center --borders=12 \
        --title="📖 README — PS4 Linux Payloads" \
        --text-info --scroll \
        --width=800 --height=580 \
        --button="🌐 Open ps4boot.github.io:2" \
        --button="Close:0"

    local ret=$?
    [ $ret -eq 2 ] && xdg-open "https://ps4boot.github.io" >/dev/null 2>&1 &
}
export -f do_payloads_readme

#------------------------------------------------------------------------
# 1. ps4-kexec — le payload kexec pour booter Linux depuis la PS4
#------------------------------------------------------------------------
do_git_kexec() {
    local dest="$PROJECT_DIR/ps4-kexec"

    if [ -d "$dest" ]; then
        yad_confirm "Existing folder:\n<tt>$dest</tt>\n\nRe-download from scratch?"
        if [ $? -eq 0 ]; then
            rm -rf "$dest"
        else
            run_in_term "🔧 Recompiler ps4-kexec" "
                cd '$dest'
                echo '=== ps4-kexec recompilation ==='
                make clean 2>/dev/null; make
                echo ''
                echo '=== Produced files ==='
                ls -lh *.elf *.bin 2>/dev/null || ls -lh
                echo ''
                read -rp '[Press Enter to close]'
            "
            return
        fi
    fi

    run_in_term "🚀 Git + Compile ps4-kexec" "
        cd '$PROJECT_DIR'
        echo '=== Downloading ps4-kexec ==='
        git clone https://github.com/ps4boot/ps4-kexec
        echo ''
        echo '=== Checking dependencies ==='
        for dep in make gcc git; do
            command -v \$dep >/dev/null 2>&1 \
                && echo \"  ✓ \$dep\" \
                || echo \"  ✗ \$dep manquant — sudo apt install \$dep\"
        done
        echo ''
        echo '=== Compilation ==='
        cd ps4-kexec && make
        echo ''
        echo '=== Produced files ==='
        ls -lh *.elf *.bin 2>/dev/null || ls -lh
        echo ''
        echo 'NOTE: use the .elf with GoldHEN v2.4b18.5/v2.4b18.6 BinLoader'
        echo ''
        read -rp '[Press Enter to open folder]'
        sleep 1 && xdg-open '$dest'
    "
    yad_info "✓ ps4-kexec compiled\n📂 <tt>$dest</tt>\n\n<small>Use the .elf with GoldHEN BinLoader</small>"
}
export -f do_git_kexec

#------------------------------------------------------------------------
# 2. fail0verflow/ps4-linux — fork original de référence
#------------------------------------------------------------------------
do_git_fail0verflow() {
    local dest="$KERNELS_DIR/ps4-linux-fail0verflow"

    if [ -d "$dest" ]; then
        yad_confirm "Existing folder:\n<tt>$dest</tt>\n\nUpdate (git pull)?"
        if [ $? -eq 0 ]; then
            run_in_term "🔄 Update fail0verflow/ps4-linux" "
                cd '$dest'
                echo '=== git pull ==='
                git pull
                echo ''
                echo '=== Available branches ==='
                git branch -a | head -20
                echo ''
                read -rp '[Press Enter to close]'
            "
        fi
        return
    fi

    local branch
    branch=$(yad --center --borders=10 \
        --title="fail0verflow/ps4-linux — Branche" \
        --list \
        --text="<b>fail0verflow/ps4-linux</b>\nOriginal PS4 Linux fork — historical reference.\nUseful to retrieve .config files or compare patches.\n\nChoose a branch:" \
        --column="Branch" \
        --column="Description" \
        "master"    "Main branch" \
        "ps4"       "PS4 specific branch" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="🚀 Download:0" \
        --width=500 --height=240)
    [ $? -ne 0 ] || [ -z "$branch" ] && return
    branch="${branch//|/}"

    run_in_term "🚀 Git fail0verflow/ps4-linux — $branch" "
        cd '$KERNELS_DIR'
        echo '=== Downloading fail0verflow/ps4-linux (shallow) ==='
        echo 'Large repository — this may take several minutes...'
        echo ''
        git clone -b '$branch' --depth=1 https://github.com/fail0verflow/ps4-linux ps4-linux-fail0verflow
        echo ''
        echo '=== Available .config files ==='
        find '$dest' -name '.config*' 2>/dev/null | head -10
        echo ''
        echo '=== Contents ==='
        ls -la '$dest' 2>/dev/null
        echo ''
        read -rp '[Press Enter to open folder]'
        sleep 1 && xdg-open '$dest' 2>/dev/null
    "
    yad_info "✓ fail0verflow/ps4-linux downloaded\n📂 <tt>$dest</tt>"
}
export -f do_git_fail0verflow

#------------------------------------------------------------------------
# GoldHEN — télécharger la dernière release
#------------------------------------------------------------------------
do_git_goldhen() {
    local dest="$PROJECT_DIR/GoldHEN"

    local out
    out=$(yad --center --borders=10 \
        --title="GoldHEN — Dernière release" \
        --form \
        --text="<b>Download the latest GoldHEN release</b>\n\n<small>Source : https://github.com/GoldHEN/GoldHEN/releases\nFiles will be downloaded to:\n<tt>$PROJECT_DIR/GoldHEN/</tt></small>\n" \
        --field="Destination folder:":TEXT "$PROJECT_DIR/GoldHEN" \
        --button="Cancel:1" --button="🚀 Download:0" \
        --width=580)
    [ $? -ne 0 ] || [ -z "$out" ] && return

    dest=$(echo "$out" | cut -d'|' -f1)
    dest="${dest//|/}"
    [ -z "$dest" ] && dest="$PROJECT_DIR/GoldHEN"

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-goldhen-XXXX.sh)
    cat > "$tmpscript" << GHEOF
#!/bin/bash
echo '=== Downloading GoldHEN — latest release ==='
echo "Destination: $dest"
echo ''

if ! command -v curl >/dev/null 2>&1; then
    echo '✗ curl required: sudo apt install curl'
    read -rp '[Press Enter to close]'
    exit 1
fi

echo '--- Fetching release info ---'
# /releases (without /latest) returns ALL releases including pre-releases
# Take the first (most recent), whether stable or pre-release
API_URL="https://api.github.com/repos/GoldHEN/GoldHEN/releases"
JSON_ALL=\$(curl -s "\$API_URL")
if [ -z "\$JSON_ALL" ]; then
    echo '✗ Impossible de joindre l'\''API GitHub'
    read -rp '[Press Enter to close]'
    exit 1
fi

# Extract first release (index 0) — the most recent
JSON=\$(echo "\$JSON_ALL" | python3 -c "
import sys, json
releases = json.load(sys.stdin)
if not releases:
    print('{}')
else:
    # Take the very first release (pre-release or stable)
    import json as j
    print(j.dumps(releases[0]))
" 2>/dev/null)

VERSION=\$(echo "\$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
pre = '(pre-release)' if d.get('prerelease') else '(stable)'
print(d.get('tag_name', '?'), pre)
" 2>/dev/null)
echo "Version: \$VERSION"
echo ''

# List all assets
echo '--- Available assets ---'
ASSETS=\$(echo "\$JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for a in data.get('assets', []):
    print(a['browser_download_url'], a['name'], a.get('size', 0))
" 2>/dev/null)

if [ -z "\$ASSETS" ]; then
    echo '✗ No assets found in release'
    read -rp '[Press Enter to close]'
    exit 1
fi

echo "\$ASSETS" | while read url name size; do
    echo "  - \$name  (\$size octets)"
done
echo ''

echo '--- Downloading all files ---'
mkdir -p '$dest'
cd '$dest'

echo "\$ASSETS" | while read url name size; do
    echo "Downloading: \$name"
    curl -L --progress-bar "\$url" -o "\$name"
    if [ -s "\$name" ]; then
        echo "  ✓ \$name"
    else
        echo "  ✗ Failed: \$name"
    fi
    echo ''
done

echo ''
echo '=== GoldHEN folder contents ==='
ls -lh '$dest'
echo ''
echo "✓ GoldHEN \$VERSION downloaded to:"
echo "  $dest"
echo ''
read -rp '[Press Enter to open folder]'
sleep 1 && xdg-open '$dest' 2>/dev/null
GHEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="🎮 GoldHEN Release" -e "bash $tmpscript" ;;
        gnome-terminal) gnome-terminal --title="🎮 GoldHEN Release" -- bash "$tmpscript" ;;
        mate-terminal)  mate-terminal  --title="🎮 GoldHEN Release" -e "bash $tmpscript" ;;
        *)              xterm -title "🎮 GoldHEN Release" -e bash "$tmpscript" ;;
    esac

    sleep 1
    [ -d "$dest" ] && ls "$dest"/*.bin "$dest"/*.elf 2>/dev/null | head -3 && \
        yad_info "✓ GoldHEN downloaded\n📂 <tt>$dest</tt>"
}
export -f do_git_goldhen

#------------------------------------------------------------------------
# 3. Préparation clé USB de boot PS4
#------------------------------------------------------------------------
do_prepare_usb() {
    # Detect USB sticks (FAT partitions on USB devices)
    local usb_list=()
    while IFS= read -r line; do
        local dev size fstype tran
        dev=$(echo "$line"    | awk '{print $1}')
        size=$(echo "$line"   | awk '{print $2}')
        fstype=$(echo "$line" | awk '{print $3}')
        tran=$(echo "$line"   | awk '{print $4}')
        [ -z "$dev" ] && continue
        [ "$tran" != "usb" ] && continue
        usb_list+=("/dev/$dev" "${size}  |  ${fstype:-—}")
    done < <(lsblk -ln -o NAME,SIZE,FSTYPE,TRAN 2>/dev/null | grep -v "^loop")

    if [ "${#usb_list[@]}" -eq 0 ]; then
        yad_err "No USB stick detected.\nConnect the USB stick and try again.\n\n<small>Check with: lsblk -o NAME,SIZE,FSTYPE,TRAN</small>"
        return
    fi

    local sel_dev
    sel_dev=$(yad --center --borders=10 \
        --title="Select USB stick" \
        --list \
        --text="<b>Prepare a PS4 boot USB stick</b>\n\nSelect the target USB partition:\n⚠️  Existing files in <tt>/boot</tt> will be replaced." \
        --column="Partition" \
        --column="Size  |  FS" \
        "${usb_list[@]}" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="Select:0" \
        --width=560 --height=300)
    [ $? -ne 0 ] || [ -z "$sel_dev" ] && return
    sel_dev="${sel_dev//|/}"

    # Search for bzImage in project
    local bzimage_default=""
    for k in "$KERNELS_DIR"/*/arch/x86/boot/bzImage; do
        [ -f "$k" ] && bzimage_default="$k" && break
    done
    # Fallback: kernel sources Tab 10
    if [ -z "$bzimage_default" ]; then
        local kdir
        kdir=$(cat "$CONF_DIR/kernel-src-dir.txt" 2>/dev/null)
        [ -f "$kdir/arch/x86/boot/bzImage" ] && bzimage_default="$kdir/arch/x86/boot/bzImage"
    fi

    # Search for initramfs
    local initramfs_default=""
    [ -f "$PROJECT_DIR/ps4-linux-payloads/linux/initramfs.cpio.gz" ] && \
        initramfs_default="$PROJECT_DIR/ps4-linux-payloads/linux/initramfs.cpio.gz"

    local out
    out=$(yad --center --borders=10 \
        --title="Fichiers à copier sur la clé USB" \
        --form \
        --text="<b>PS4 USB stick preparation</b>\n\nThe <tt>boot/</tt> structure will be created at the root of the stick.\nLeave empty to skip copying the file.\n" \
        --field="USB stick (partition):":RO "$sel_dev" \
        --field="bzImage :":FL "${bzimage_default:-$PROJECT_DIR/}" \
        --field="initramfs.cpio.gz :":FL "${initramfs_default:-$PROJECT_DIR/}" \
        --field="Create bootargs.txt:":CHK "FALSE" \
        --field="Create vram.txt:":CHK "FALSE" \
        --button="Cancel:1" --button="🚀 Prepare stick:0" \
        --width=680)
    [ $? -ne 0 ] || [ -z "$out" ] && return

    IFS='|' read -r _dev bzimage_src initramfs_src do_bootargs do_vram <<< "$out"
    bzimage_src="${bzimage_src//|/}"
    initramfs_src="${initramfs_src//|/}"

    # Validate selected files
    local copy_bz="" copy_init=""
    [ -f "$bzimage_src" ]   && copy_bz="$bzimage_src"
    [ -f "$initramfs_src" ] && copy_init="$initramfs_src"

    if [ -z "$copy_bz" ] && [ -z "$copy_init" ] && \
       [ "$do_bootargs" != "TRUE" ] && [ "$do_vram" != "TRUE" ]; then
        yad_err "No file to copy selected."
        return
    fi

    # bootargs / vram values if requested
    local bootargs_val="" vram_val=""
    if [ "$do_bootargs" = "TRUE" ] || [ "$do_vram" = "TRUE" ]; then
        local bv_out
        bv_out=$(yad --center --borders=10 \
            --title="Text files content" \
            --form \
            --text="<b>Optional files content</b>\n\n<small>bootargs.txt: arguments passed to kernel\nvram.txt:    VRAM size in MB (e.g. 256)</small>\n" \
            --field="bootargs.txt:":TEXT "amdgpu.cik_support=1 amdgpu.si_support=1 amdgpu.dc=0 mitigations=off nopti" \
            --field="vram.txt (Mo) :":TEXT "256" \
            --button="Cancel:1" --button="OK:0" \
            --width=700)
        [ $? -ne 0 ] || [ -z "$bv_out" ] && return
        bootargs_val=$(echo "$bv_out" | cut -d'|' -f1)
        vram_val=$(echo "$bv_out"     | cut -d'|' -f2)
    fi

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-usb-XXXX.sh)
    cat > "$tmpscript" << UEOF
#!/bin/bash
set -e
echo '=== Preparing PS4 boot USB stick ==='
echo "Partition: $sel_dev"
echo ''

# Mount USB stick if not already mounted
MNT=\$(lsblk -no MOUNTPOINT '$sel_dev' 2>/dev/null | head -1 | tr -d ' ')
MOUNTED_BY_US=0

if [ -z "\$MNT" ]; then
    MNT=\$(mktemp -d /tmp/ps4usb-XXXX)
    echo "Temporary mount at \$MNT..."
    sudo mount '$sel_dev' "\$MNT" 2>/dev/null || {
        echo "ERROR: unable to mount $sel_dev"
        read -rp '[Press Enter to close]'
        exit 1
    }
    MOUNTED_BY_US=1
fi

echo "Mount point: \$MNT"
echo ''

# Create boot/ structure
echo '--- Creating boot/ folder ---'
sudo mkdir -p "\$MNT/boot"

# Copy bzImage
$([ -n "$copy_bz" ] && echo "echo '--- Copying bzImage ---'
sudo cp '$copy_bz' \"\$MNT/boot/bzImage\"
echo '  ✓ bzImage copied'")

# Copy initramfs
$([ -n "$copy_init" ] && echo "echo '--- Copying initramfs.cpio.gz ---'
sudo cp '$copy_init' \"\$MNT/boot/initramfs.cpio.gz\"
echo '  ✓ initramfs.cpio.gz copied'")

# bootargs.txt
$([ "$do_bootargs" = "TRUE" ] && echo "echo '--- Creating bootargs.txt ---'
echo '$bootargs_val' | sudo tee \"\$MNT/boot/bootargs.txt\" >/dev/null
echo '  ✓ bootargs.txt created'")

# vram.txt
$([ "$do_vram" = "TRUE" ] && echo "echo '--- Creating vram.txt ---'
echo '$vram_val' | sudo tee \"\$MNT/boot/vram.txt\" >/dev/null
echo '  ✓ vram.txt created'")

echo ''
echo '=== USB stick contents (/boot) ==='
ls -lh "\$MNT/boot/" 2>/dev/null

sync
echo ''
echo '✓ Sync OK — you can remove the stick.'

if [ \$MOUNTED_BY_US -eq 1 ]; then
    sudo umount "\$MNT" 2>/dev/null
    rmdir "\$MNT" 2>/dev/null
fi

echo ''
read -rp '[Press Enter to close]'
UEOF
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="Prepare PS4 boot USB" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="Prepare PS4 boot USB" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="Prepare PS4 boot USB" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "Préparer clé USB PS4" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_prepare_usb

#------------------------------------------------------------------------
# 4. Transfert FTP vers la PS4 (bzImage + initramfs → /data/linux/boot)
#------------------------------------------------------------------------
PS4_FTP_IP_FILE="$CONF_DIR/ps4-ftp-ip.txt"
export PS4_FTP_IP_FILE

do_ftp_transfer() {
    local last_ip
    last_ip=$(cat "$PS4_FTP_IP_FILE" 2>/dev/null || echo "192.168.1.")

    # Search for bzImage in project
    local bzimage_default=""
    for k in "$KERNELS_DIR"/*/arch/x86/boot/bzImage; do
        [ -f "$k" ] && bzimage_default="$k" && break
    done
    local kdir; kdir=$(cat "$CONF_DIR/kernel-src-dir.txt" 2>/dev/null)
    [ -z "$bzimage_default" ] && [ -f "$kdir/arch/x86/boot/bzImage" ] && \
        bzimage_default="$kdir/arch/x86/boot/bzImage"

    local initramfs_default=""
    [ -f "$PROJECT_DIR/ps4-linux-payloads/linux/initramfs.cpio.gz" ] && \
        initramfs_default="$PROJECT_DIR/ps4-linux-payloads/linux/initramfs.cpio.gz"

    local out
    out=$(yad --center --borders=10 \
        --title="Transfert FTP vers la PS4" \
        --form \
        --text="<b>FTP Transfer → /data/linux/boot/ on PS4</b>\n\n<small>The PS4 must be under Linux or have an active FTP server (GoldHEN).\nLeave empty to skip sending the file.</small>\n" \
        --field="PS4 IP address:":TEXT "$last_ip" \
        --field="FTP Port:":NUM "2121!1..65535!1" \
        --field="FTP Username:":TEXT "anonymous" \
        --field="Password:":TEXT "" \
        --field="Remote folder:":TEXT "/data/linux/boot" \
        --field="bzImage local :":FL "${bzimage_default:-$PROJECT_DIR/}" \
        --field="initramfs.cpio.gz local :":FL "${initramfs_default:-$PROJECT_DIR/}" \
        --button="Cancel:1" --button="🚀 Send:0" \
        --width=720)
    [ $? -ne 0 ] || [ -z "$out" ] && return

    IFS='|' read -r ps4_ip ps4_port ftp_user ftp_pass remote_dir bz_src init_src <<< "$out"
    ps4_ip="${ps4_ip//|/}"
    ps4_port="${ps4_port//|/}"
    ftp_user="${ftp_user//|/}"
    ftp_pass="${ftp_pass//|/}"
    remote_dir="${remote_dir//|/}"
    bz_src="${bz_src//|/}"
    init_src="${init_src//|/}"

    [ -z "$ps4_ip" ] && yad_err "PS4 IP not entered." && return

    echo "$ps4_ip" > "$PS4_FTP_IP_FILE"

    # Check that curl is available
    if ! command -v curl >/dev/null 2>&1; then
        yad_err "curl is required.\n<b>sudo apt install curl</b>"
        return
    fi

    local files_to_send=()
    [ -f "$bz_src" ]   && files_to_send+=("$bz_src")
    [ -f "$init_src" ] && files_to_send+=("$init_src")

    if [ "${#files_to_send[@]}" -eq 0 ]; then
        yad_err "No valid file selected."
        return
    fi

    local tmpscript
    tmpscript=$(mktemp /tmp/hyb-ftp-XXXX.sh)
    {
        echo "#!/bin/bash"
        echo "echo '=== Transfert FTP vers PS4 ==='"
        echo "echo \"  IP     : $ps4_ip:$ps4_port\""
        echo "echo \"  Folder:  $remote_dir\""
        echo "echo ''"
        local ftp_url="ftp://${ftp_user}"
        [ -n "$ftp_pass" ] && ftp_url="${ftp_url}:${ftp_pass}"
        ftp_url="${ftp_url}@${ps4_ip}:${ps4_port}${remote_dir}/"

        for f in "${files_to_send[@]}"; do
            local fname
            fname=$(basename "$f")
            echo "echo \"--- Sending: $fname ---\""
            echo "curl -T '$f' '${ftp_url}' --ftp-create-dirs --progress-bar 2>&1"
            echo "[ \$? -eq 0 ] && echo \"  ✓ $fname sent\" || echo \"  ✗ Send error $fname\""
            echo "echo ''"
        done
        echo "echo '=== Transfert terminé ==='"
        echo "echo ''"
        echo "read -rp '[Press Enter to close]'"
    } > "$tmpscript"
    chmod +x "$tmpscript"
    case "$TERM_BIN" in
        xfce4-terminal) xfce4-terminal --title="FTP PS4 — $ps4_ip" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        gnome-terminal) gnome-terminal --title="FTP PS4 — $ps4_ip" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
        mate-terminal)  mate-terminal  --title="FTP PS4 — $ps4_ip" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
        *)              xterm -title "FTP PS4 — $ps4_ip" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
    esac
}
export -f do_ftp_transfer

#------------------------------------------------------------------------
# 5. Éditeur bootargs.txt / vram.txt
#------------------------------------------------------------------------
BOOTARGS_FILE="$CONF_DIR/bootargs.txt"
VRAM_FILE="$CONF_DIR/vram.txt"
export BOOTARGS_FILE VRAM_FILE

[ ! -f "$BOOTARGS_FILE" ] && cat > "$BOOTARGS_FILE" << 'BAEOF'
amdgpu.cik_support=1 amdgpu.si_support=1 amdgpu.dc=0 amdgpu.gttsize=2048 amdgpu.vm_fragment_size=9 amdgpu.pcie_gen2=1 amdgpu.aspm=0 amdgpu.dpm=1 amdgpu.lockup_timeout=10000 mitigations=off nopti spectre_v2=off noibpb noibrs ibt=off processor.max_cstate=1 idle=nomwait
BAEOF
[ ! -f "$VRAM_FILE" ] && echo "256" > "$VRAM_FILE"

do_edit_bootargs() {
    local cur_ba cur_vram
    cur_ba=$(cat "$BOOTARGS_FILE"  2>/dev/null)
    cur_vram=$(cat "$VRAM_FILE"    2>/dev/null || echo "256")

    local out
    out=$(yad --center --borders=10 \
        --title="bootargs.txt / vram.txt editor" \
        --form \
        --text="<b>PS4 kernel configuration files editor</b>\n
<b>bootargs.txt</b> — arguments passed to kernel at boot
<b>vram.txt</b>     — reserved VRAM size (in MB)

<small>UART parameters (disabled on recent kernels):
  Aeolia/Belize: <tt>console=uart8250,mmio32,0xd0340000</tt>
  Baikal:        <tt>console=uart8250,mmio32,0xC890E000</tt></small>\n" \
        --field="bootargs.txt:":TEXT "$cur_ba" \
        --field="VRAM (MB):":TEXT "$cur_vram" \
        --field="Add mitigations=off:":CHK "FALSE" \
        --field="Add UART Aeolia/Belize:":CHK "FALSE" \
        --field="Add UART Baikal:":CHK "FALSE" \
        --button="Cancel:1" \
        --button="💾 Save:0" \
        --width=800)
    [ $? -ne 0 ] || [ -z "$out" ] && return

    IFS='|' read -r new_ba new_vram add_mit add_uart_belize add_uart_baikal <<< "$out"

    # Add checked options if not already present
    [ "$add_mit"          = "TRUE" ] && \
        [[ "$new_ba" != *"mitigations=off"* ]] && \
        new_ba="$new_ba mitigations=off nopti spectre_v2=off noibpb noibrs ibt=off"
    [ "$add_uart_belize"  = "TRUE" ] && \
        [[ "$new_ba" != *"uart8250"* ]] && \
        new_ba="$new_ba console=uart8250,mmio32,0xd0340000"
    [ "$add_uart_baikal"  = "TRUE" ] && \
        [[ "$new_ba" != *"uart8250"* ]] && \
        new_ba="$new_ba console=uart8250,mmio32,0xC890E000"

    # Clean up multiple spaces
    new_ba=$(echo "$new_ba" | tr -s ' ' | sed 's/^ //;s/ $//')

    echo "$new_ba"   > "$BOOTARGS_FILE"
    echo "$new_vram" > "$VRAM_FILE"

    # Offer to copy to USB or via FTP
    local action
    action=$(yad --center --borders=10 \
        --title="Files saved" \
        --list \
        --text="✓ <b>bootargs.txt</b> and <b>vram.txt</b> saved to:\n<tt>$CONF_DIR</tt>\n\nWhat would you like to do next?" \
        --column="Action" \
        --column="Description" \
        "usb"   "Copy to boot USB stick" \
        "ftp"   "Transfer via FTP to PS4" \
        "open"  "Open config folder" \
        "done"  "Done" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="OK:0" \
        --width=480 --height=280)
    [ $? -ne 0 ] || [ -z "$action" ] && return
    action="${action//|/}"

    case "$action" in
        usb)  do_prepare_usb   ;;
        ftp)  do_ftp_transfer  ;;
        open) xdg-open "$CONF_DIR" >/dev/null 2>&1 & ;;
    esac
}
export -f do_edit_bootargs

#------------------------------------------------------------------------
# 6. Builder initramfs minimaliste (busybox statique + repackage cpio.gz)
#------------------------------------------------------------------------
INITRAMFS_DIR="$PROJECT_DIR/initramfs-build"
export INITRAMFS_DIR

do_build_initramfs() {
    # Check required tools
    local missing_tools=()
    for t in cpio gzip find; do
        command -v "$t" >/dev/null 2>&1 || missing_tools+=("$t")
    done
    if [ "${#missing_tools[@]}" -gt 0 ]; then
        yad_err "Missing tools: <b>${missing_tools[*]}</b>\n<tt>sudo apt install ${missing_tools[*]}</tt>"
        return
    fi

    local choice
    choice=$(yad --center --borders=10 \
        --title="PS4 initramfs builder" \
        --list \
        --text="<b>Minimal PS4 initramfs builder</b>\n\nQue voulez-vous faire ?" \
        --column="Action" \
        --column="Description" \
        "create"   "Create a new working folder (static busybox)" \
        "repack"   "Repackage an existing initramfs to cpio.gz" \
        "extract"  "Extract an existing initramfs.cpio.gz to modify it" \
        "addscript" "Add a custom init script" \
        --print-column=1 --separator="" \
        --button="Cancel:1" --button="OK:0" \
        --width=600 --height=300)
    [ $? -ne 0 ] || [ -z "$choice" ] && return
    choice="${choice//|/}"

    case "$choice" in

        create)
            # Check busybox-static
            if ! command -v busybox >/dev/null 2>&1 && \
               [ ! -f /bin/busybox ] && [ ! -f /usr/bin/busybox ]; then
                yad_confirm "busybox-static is not installed.\n\nInstall now?\n<tt>sudo apt install busybox-static</tt>" || return
                run_in_term "Installing busybox-static" "sudo apt install -y busybox-static"
            fi

            local tmpscript
            tmpscript=$(mktemp /tmp/hyb-initramfs-XXXX.sh)
            cat > "$tmpscript" << IEOF
#!/bin/bash
echo '=== Creating PS4 initramfs folder ==='
mkdir -p '$INITRAMFS_DIR'
cd '$INITRAMFS_DIR'

# Minimal structure
for d in bin sbin etc proc sys dev tmp lib lib64 usr/bin usr/sbin mnt/root; do
    mkdir -p \$d
done

# Copy busybox
BUSYBOX=\$(command -v busybox || echo /bin/busybox)
if [ ! -f "\$BUSYBOX" ]; then
    echo 'ERROR: busybox not found — sudo apt install busybox-static'
    read -rp '[Press Enter to close]'
    exit 1
fi
cp "\$BUSYBOX" bin/busybox
chmod +x bin/busybox

# Create busybox applets
cd bin
./busybox --list 2>/dev/null | while read app; do
    [ "\$app" = "busybox" ] && continue
    ln -sf busybox "\$app" 2>/dev/null
done
cd ..

# Minimal init script
cat > init << 'INITEOF'
#!/bin/sh
mount -t proc     none /proc
mount -t sysfs    none /sys
mount -t devtmpfs none /dev 2>/dev/null || mknod /dev/null c 1 3

# Read time from kernel command line (time=TIMESTAMP)
CMDLINE=\$(cat /proc/cmdline)
for param in \$CMDLINE; do
    case "\$param" in
        time=*) date -s @"\${param#time=}" 2>/dev/null ;;
    esac
done

echo "=== initramfs PS4 boot ==="
echo "Command line: \$CMDLINE"

# Rescue shell
exec /bin/sh
INITEOF
chmod +x init

echo ''
echo '=== Structure created ==='
find . -maxdepth 2 | sort
echo ''
echo 'To repackage → restart the builder and choose "Repackage"'
echo ''
read -rp '[Press Enter to open folder]'
sleep 1 && xdg-open '$INITRAMFS_DIR'
IEOF
            chmod +x "$tmpscript"
            case "$TERM_BIN" in
                xfce4-terminal) xfce4-terminal --title="Create initramfs" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
                gnome-terminal) gnome-terminal --title="Create initramfs" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
                mate-terminal)  mate-terminal  --title="Create initramfs" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
                *)              xterm -title "Create initramfs" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
            esac
            ;;

        extract)
            local src_cpio
            src_cpio=$(yad --center --borders=10 \
                --title="Select initramfs to extract" \
                --file --filename="$PROJECT_DIR/" \
                --file-filter="initramfs | *.cpio.gz *.cpio *.gz" \
                --button="Cancel:1" --button="Select:0" \
                --width=860 --height=540)
            [ $? -ne 0 ] || [ -z "$src_cpio" ] && return

            local tmpscript
            tmpscript=$(mktemp /tmp/hyb-extract-initramfs-XXXX.sh)
            cat > "$tmpscript" << EXEOF
#!/bin/bash
echo '=== Initramfs extraction ==='
mkdir -p '$INITRAMFS_DIR'
cd '$INITRAMFS_DIR'
echo "Source: $src_cpio"
echo ''
case "$src_cpio" in
    *.gz) zcat '$src_cpio' | cpio -idm --quiet ;;
    *)    cpio -idm --quiet < '$src_cpio' ;;
esac
echo '✓ Extraction complete'
echo ''
echo '=== Contents ==='
ls -la
echo ''
read -rp '[Press Enter to open folder]'
sleep 1 && xdg-open '$INITRAMFS_DIR'
EXEOF
            chmod +x "$tmpscript"
            case "$TERM_BIN" in
                xfce4-terminal) xfce4-terminal --title="Extract initramfs" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
                gnome-terminal) gnome-terminal --title="Extract initramfs" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
                mate-terminal)  mate-terminal  --title="Extract initramfs" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
                *)              xterm -title "Extraire initramfs" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
            esac
            ;;

        repack)
            [ ! -d "$INITRAMFS_DIR" ] && \
                yad_err "Initramfs folder not found:\n<tt>$INITRAMFS_DIR</tt>\nCreate the structure first with 'Create'." && return

            local out_file="$PROJECT_DIR/initramfs.cpio.gz"
            local out_choice
            out_choice=$(yad --center --borders=10 \
                --title="Destination du repackage" \
                --form \
                --text="<b>Repackage as initramfs.cpio.gz</b>\n\nSource: <tt>$INITRAMFS_DIR</tt>" \
                --field="Output file:":FL "$out_file" \
                --button="Cancel:1" --button="🚀 Repackage:0" \
                --width=680)
            [ $? -ne 0 ] || [ -z "$out_choice" ] && return
            out_file=$(echo "$out_choice" | cut -d'|' -f1)

            local tmpscript
            tmpscript=$(mktemp /tmp/hyb-repack-initramfs-XXXX.sh)
            cat > "$tmpscript" << RPEOF
#!/bin/bash
echo '=== Initramfs repackage ==='
echo "Source:  $INITRAMFS_DIR"
echo "Output:  $out_file"
echo ''
cd '$INITRAMFS_DIR'
find . | cpio -o -H newc 2>/dev/null | gzip -9 > '$out_file'
echo "✓ Created: $out_file"
echo ""
ls -lh '$out_file'
echo ''
echo 'You can now:'
echo '  → Copy to USB stick  (tab: Prepare USB)'
echo '  → Transfer via FTP  (tab: PS4 FTP Transfer)'
echo ''
read -rp '[Press Enter to close]'
RPEOF
            chmod +x "$tmpscript"
            case "$TERM_BIN" in
                xfce4-terminal) xfce4-terminal --title="Repackage initramfs" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
                gnome-terminal) gnome-terminal --title="Repackage initramfs" -- bash -c "$tmpscript; rm -f $tmpscript" ;;
                mate-terminal)  mate-terminal  --title="Repackage initramfs" -e "bash -c '$tmpscript; rm -f $tmpscript'" ;;
                *)              xterm -title "Repackager initramfs" -e bash -c "$tmpscript; rm -f $tmpscript" ;;
            esac
            ;;

        addscript)
            [ ! -d "$INITRAMFS_DIR" ] && \
                yad_err "Initramfs folder not found:\n<tt>$INITRAMFS_DIR</tt>\nCreate the structure first." && return

            local script_name
            local out_s
            out_s=$(yad --center --borders=10 \
                --title="Add a script to initramfs" \
                --form \
                --text="<b>Add a script to the initramfs</b>\n\nThe script will be created in <tt>$INITRAMFS_DIR/</tt>" \
                --field="Script name:":TEXT "custom-init.sh" \
                --field="Content:":TXT "#!/bin/sh\n# Script personnalisé\necho 'Hello from PS4 initramfs'\n" \
                --button="Cancel:1" --button="Create:0" \
                --width=700 --height=400)
            [ $? -ne 0 ] || [ -z "$out_s" ] && return
            script_name=$(echo "$out_s" | cut -d'|' -f1)
            local script_content
            script_content=$(echo "$out_s" | cut -d'|' -f2-)
            local script_path="$INITRAMFS_DIR/$script_name"
            printf '%s' "$script_content" > "$script_path"
            chmod +x "$script_path"
            yad_info "✓ Script created: <tt>$script_path</tt>\n\nDon't forget to reference it in <tt>init</tt>,\nthen repackage the initramfs."
            ;;
    esac
}
export -f do_build_initramfs

#------------------------------------------------------------------------
# Al-Azif — profil GitHub
#------------------------------------------------------------------------
do_open_url_alazif() {
    xdg-open "https://github.com/Al-Azif" >/dev/null 2>&1 &
    yad_info "🐙 <b>Al-Azif</b>

Opening GitHub profile...

<small>You will find his PS4 tools there:
payloads, exploits, firmware dumps and more.</small>

<tt>https://github.com/Al-Azif</tt>"
}
export -f do_open_url_alazif

#------------------------------------------------------------------------
# Ouvrir le dossier projet
#------------------------------------------------------------------------
do_open_project_dir() {
    xdg-open "$PROJECT_DIR" >/dev/null 2>&1 &
    yad_info "📂 Project opened:\n<tt>$PROJECT_DIR</tt>"
}

tab_git_ps4() {
    yad --plug="$KEY" --tabnum=10 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Java 1.png" --image-on-top \
        --text="<big><b><span foreground='#F48FB1'>🚀 GIT PS4 — Kernels + Orbis + Payloads + Deployment</span></b></big>

<b>PROJET :</b> <tt>$PROJECT_DIR</tt>

Downloads, compiles and deploys the entire PS4 Linux ecosystem.\n" \
        \
        --field="":LBL "" \
        --field="<b>— PS4 KERNELS (crashniels/linux) —</b>":LBL "" \
        --field="  🚀 crashniels/linux — PS4 kernel (branch of choice)":BTN 'bash -c "do_git_ps4_kernel"' \
        --field="  🚀 feeRnt/ps4-linux-12xx — PS4 kernel (auto branches)":BTN 'bash -c "do_git_feernt_kernel"' \
        --field="  🗂  fail0verflow/ps4-linux (original reference)":BTN 'bash -c "do_git_fail0verflow"' \
        --field="  🐙 Al-Azif — GitHub profile (payloads, PS4 tools)":BTN 'bash -c "do_open_url_alazif"' \
        --field="  🎮 GoldHEN — download latest release":BTN 'bash -c "do_git_goldhen"' \
        \
        --field="":LBL "" \
        --field="<b>— ORBIS (PS4 SDK) —</b>":LBL "" \
        --field="  🚀 OpenOrbis PS4 Toolchain (latest release auto)":BTN 'bash -c "do_git_orbis"' \
        \
        --field="":LBL "" \
        --field="<b>— LINUX PAYLOADS (ps4boot) —</b>":LBL "" \
        --field="  🚀 ps4-linux-payloads — download + compile":BTN 'bash -c "do_git_payloads"' \
        --field="  📖 README GoldHEN / bzImage / initramfs":BTN 'bash -c "do_payloads_readme"' \
        --field="  ⚡ ps4-kexec — kexec payload (boot chain)":BTN 'bash -c "do_git_kexec"' \
        \
        --field="":LBL "" \
        --field="<b>— DEPLOYMENT —</b>":LBL "" \
        --field="  💾 Prepare a PS4 boot USB stick":BTN 'bash -c "do_prepare_usb"' \
        --field="  📡 FTP Transfer → /data/linux/boot/ on PS4":BTN 'bash -c "do_ftp_transfer"' \
        \
        --field="":LBL "" \
        --field="<b>— KERNEL CONFIGURATION —</b>":LBL "" \
        --field="  ⚙  Edit bootargs.txt / vram.txt":BTN 'bash -c "do_edit_bootargs"' \
        \
        --field="":LBL "" \
        --field="<b>— INITRAMFS BUILDER —</b>":LBL "" \
        --field="  🛠  Create / extract / repackage an initramfs.cpio.gz":BTN 'bash -c "do_build_initramfs"' \
        --field="  <small><i>→ Based on static busybox — supports PS4 RTC init script</i></small>":LBL "" \
        \
        --field="":LBL "" \
        --field="<b>— Project —</b>":LBL "" \
        --field="  📂 Open PROJECT-PS4/":BTN 'bash -c "do_open_project_dir"' \
        \
        --field="Kernels  : <tt>$KERNELS_DIR</tt>":LBL "" \
        --field="Orbis    : <tt>$ORBIS_DIR</tt>":LBL "" \
        --field="Payloads : <tt>$PROJECT_DIR/ps4-linux-payloads</tt>":LBL "" \
        --field="kexec    : <tt>$PROJECT_DIR/ps4-kexec</tt>":LBL "" \
        --field="initramfs: <tt>$INITRAMFS_DIR</tt>":LBL "" \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

#========================================================================

#========================================================================
# TAB 11 — PS4 Linux Community
#========================================================================

do_open_url_dionkill() {
    xdg-open "https://dionkill.github.io/ps4-linux-tutorial/files.html" >/dev/null 2>&1 &
}
export -f do_open_url_dionkill

do_open_url_ps4linux() {
    xdg-open "https://ps4linux.com/downloads/#PS4_Linux_Kernel_Source" >/dev/null 2>&1 &
}
export -f do_open_url_ps4linux

tab_communaute() {
    yad --plug="$KEY" --tabnum=11 \
        --form --scroll \
        --image="/usr/share/hybryde/SquareGlass/Pidgin 2.png" --image-on-top \
        --text="<big><b><span foreground='#80CBC4'>🌍 PS4 Linux Community</span></b></big>
Community resources, tutorials, downloads and online help.\n" \
        \
        --field="":LBL "" \
        --field="<b>— Dionkill — PS4 Linux Tutorial —</b>":LBL "" \
        --field="  🌐 Open ps4-linux-tutorial (dionkill.github.io)":BTN 'bash -c "do_open_url_dionkill"' \
        --field="  <small><i>All In One for PS4: bzImage distribution, initramfs, tutorials and more.</i></small>":LBL "" \
        \
        --field="":LBL "" \
        --field="<b>— noob404 — PS4Linux.com —</b>":LBL "" \
        --field="  🌐 Open ps4linux.com (noob404)":BTN 'bash -c "do_open_url_ps4linux"' \
        --field="  <small><i>Forum, help, tutorials, downloads and other PS4 Linux resources.</i></small>":LBL "" \
        \
        --field="":LBL "" \
        --field="<b>— Useful links —</b>":LBL "" \
        --field="  <small><tt>https://dionkill.github.io/ps4-linux-tutorial/files.html</tt></small>":LBL "" \
        --field="  <small><tt>https://ps4linux.com/downloads/#PS4_Linux_Kernel_Source</tt></small>":LBL "" \
        \
        "" "" "" "" "" "" "" "" "" "" "" "" \
        &
}

# LAUNCH TABS IN BACKGROUND
#========================================================================

# Tab 11 exports — all functions must be defined before this call
export -f do_git_ps4_kernel
export -f do_git_feernt_kernel
export -f do_git_orbis
export -f do_git_payloads
export -f do_payloads_readme
export -f do_git_kexec
export -f do_git_fail0verflow
export -f do_git_goldhen
export -f do_prepare_usb
export -f do_ftp_transfer
export -f do_edit_bootargs
export -f do_build_initramfs
export -f do_open_url_alazif
export -f do_open_project_dir
export -f tab_git_ps4

tab_tar_create
tab_img_create
tab_tar_extract
tab_mount_ps4
tab_reseau
tab_diagnostic
tab_mesa
tab_mesa_env
tab_kernel
tab_git_ps4
tab_communaute
tab_aide
#========================================================================
# MAIN WINDOW
#========================================================================

yad --notebook \
    --window-icon="applications-system" \
    --title="Hybryde PS4 Tools" \
    --width=960 --height=720 \
    --image="$LOGO" \
    --image-on-top \
    --text="<span size='x-large'><b>Hybryde PS4 Tools</b></span>
<small>Mesa  •  Archiving  •  Disk image  •  PS4 SSD  •  Network  •  Diagnostic  •  Mesa ENV  •  Kernel</small>" \
    --button="Close:0" \
    --key="$KEY" \
    --tab="📦 Create a tar.xz" \
    --tab="💿 Create a .img" \
    --tab="📂 Extract tar.xz" \
    --tab="🔌 Mount PS4 SSD" \
    --tab="🌐 Network" \
    --tab="🔍 Diagnostic" \
    --tab="🔧 Compile Mesa" \
    --tab="⚙ Mesa ENV" \
    --tab="🐧 Kernel LTO" \
    --tab="🐧 GIT DEV Kernel/Orbis..." \
    --tab="🌍 Community" \
    --tab="📖 Help" \
    --active-tab=1
