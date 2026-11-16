#!/bin/bash
# auditor.sh - File Auditor & Backup Tool (menu-driven, or one action from the command line).
# Usage: ./auditor.sh [directory] [scan|perms|ext|backup]
# Run it from inside its own folder (it loads lib.sh from the current folder).

source ./lib.sh

# ---------- Settings ----------
DIR="${1:-.}"            # folder to audit (default: current directory)
ACTION="${2:-}"          # optional action; empty means: open the menu
BACKUP_DIR="backups"     # where the .bak copies are stored

# ---------- Functions ----------

# 1. List every file and folder of DIR and print how many of each there are.
scan_directory() {
    local item name
    local files=0
    local folders=0

    for item in "$DIR"/*; do
        [ -e "$item" ] || continue          # empty folder: the glob stays literal
        name="${item##*/}"
        if [ -d "$item" ]; then
            echo "[dir ] $name"
            folders=$((folders + 1))
        elif [ -f "$item" ]; then
            echo "[file] $name"
            files=$((files + 1))
        fi
    done

    echo "Files: $files Folders: $folders"
    log_action "scan of '$DIR': $files files, $folders folders"
}

# 2. Show rwx flags of every regular file for the current user, then summary counts.
permission_audit() {
    local f name flags
    local unreadable=0
    local executable=0

    for f in "$DIR"/*; do
        [ -f "$f" ] || continue
        name="${f##*/}"
        flags=""

        if [ -r "$f" ]; then flags="${flags}r"; else flags="${flags}-"; fi
        if [ -w "$f" ]; then flags="${flags}w"; else flags="${flags}-"; fi
        if [ -x "$f" ]; then flags="${flags}x"; else flags="${flags}-"; fi

        echo "$flags $name"

        if [ ! -r "$f" ]; then
            unreadable=$((unreadable + 1))
        fi
        if [ -x "$f" ]; then
            executable=$((executable + 1))
        fi
    done

    echo "Unreadable files: $unreadable Executable files: $executable"
    log_action "permission audit of '$DIR': $unreadable unreadable, $executable executable"
}

# 3. Count regular files per extension (txt, log, sh, jpg, other) with an associative array.
extension_report() {
    local f name ext key
    local -A counts=([txt]=0 [log]=0 [sh]=0 [jpg]=0 [other]=0)

    for f in "$DIR"/*; do
        [ -f "$f" ] || continue
        name="${f##*/}"
        ext="${name##*.}"
        # a name without a dot has no extension: ${name##*.} returns the whole name
        if [ "$ext" = "$name" ]; then
            ext="other"
        fi
        case "$ext" in
            txt|log|sh|jpg) counts[$ext]=$((counts[$ext] + 1)) ;;
            *)              counts[other]=$((counts[other] + 1)) ;;
        esac
    done

    for key in jpg log other sh txt; do
        echo "$key : ${counts[$key]}"
    done
    log_action "extension report of '$DIR'"
}

# 4. Ask for a text and print every file whose name contains it.
search_file() {
    local term f name
    local found=0

    read -r -p "Text to search in file names: " term
    if [ -z "$term" ]; then
        log_error "Nothing typed."
        log_action "search with empty text in '$DIR'"
        return 1
    fi

    for f in "$DIR"/*; do
        [ -f "$f" ] || continue
        name="${f##*/}"
        if [[ "$name" == *"$term"* ]]; then
            echo "$name"
            found=$((found + 1))
        fi
    done

    if [ "$found" -eq 0 ]; then
        echo "No file name contains '$term'."
    fi
    log_action "search '$term' in '$DIR': $found match(es)"
}

# 5. Copy every readable file to BACKUP_DIR as name_YYYYMMDD_HHMMSS.bak; skip unreadable ones.
backup_all() {
    local f name stamp
    local saved=0
    local skipped=0

    mkdir -p "$BACKUP_DIR"
    stamp="$(date '+%Y%m%d_%H%M%S')"

    for f in "$DIR"/*; do
        [ -f "$f" ] || continue
        name="${f##*/}"
        if [ -r "$f" ]; then
            if cp -- "$f" "$BACKUP_DIR/${name}_${stamp}.bak"; then
                saved=$((saved + 1))
            else
                log_error "Could not copy '$name'."
                skipped=$((skipped + 1))
            fi
        else
            log_error "Skipping '$name': file is not readable."
            skipped=$((skipped + 1))
        fi
    done

    echo "Saved: $saved Skipped: $skipped"
    log_action "backup of '$DIR': $saved saved, $skipped skipped"
}

# 6. Print the names of the saved backups, or "(no backups yet)".
list_backups() {
    local b
    local count=0

    if [ -d "$BACKUP_DIR" ]; then
        for b in "$BACKUP_DIR"/*.bak; do
            [ -f "$b" ] || continue
            echo "${b##*/}"
            count=$((count + 1))
        done
    fi

    if [ "$count" -eq 0 ]; then
        echo "(no backups yet)"
    fi
    log_action "list backups: $count found"
}

# 7. Copy a chosen backup into DIR as restored_NAME; never overwrite an existing file.
restore_backup() {
    local bname original target b
    bname="$1"

    if [ -z "$bname" ]; then
        echo "Available backups:"
        for b in "$BACKUP_DIR"/*.bak; do
            [ -f "$b" ] && echo "  ${b##*/}"
        done
        read -r -p "Backup name to restore: " bname
    fi

    if [ -z "$bname" ] || [ ! -f "$BACKUP_DIR/$bname" ]; then
        log_error "Backup '$bname' does not exist."
        log_action "restore failed: backup '$bname' not found"
        return 1
    fi

    # remove the _YYYYMMDD_HHMMSS.bak suffix to get the original file name
    original="${bname%_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].bak}"
    target="$DIR/restored_$original"

    if [ -e "$target" ]; then
        log_error "'restored_$original' already exists; will not overwrite it."
        log_action "restore failed: '$target' already exists"
        return 1
    fi

    if cp -- "$BACKUP_DIR/$bname" "$target"; then
        echo "Restored as: restored_$original"
        log_action "restored '$bname' to '$target'"
    else
        log_error "Restore failed."
        log_action "restore failed: copy error for '$bname'"
        return 1
    fi
}

# Show the menu in a loop until the user chooses Exit; a wrong choice shows an error.
show_menu() {
    local choice
    local running=true

    while [ "$running" = true ]; do
        echo
        echo "===== File Auditor & Backup Tool ====="
        echo "Folder: $DIR"
        echo "1) Scan directory"
        echo "2) Permission audit"
        echo "3) Extension report"
        echo "4) Search file"
        echo "5) Backup all"
        echo "6) List backups"
        echo "7) Restore backup"
        echo "0) Exit"
        if ! read -r -p "Choose: " choice; then
            echo
            break                           # end of input (Ctrl-D): leave the menu
        fi

        case "$choice" in
            1) scan_directory ;;
            2) permission_audit ;;
            3) extension_report ;;
            4) search_file ;;
            5) backup_all ;;
            6) list_backups ;;
            7) restore_backup "" ;;
            0) echo "Goodbye."; running=false ;;
            *) log_error "Invalid choice '$choice'. Please try again." ;;
        esac
    done
}

# ---------- Main part ----------
require_dir "$DIR"

if [ -z "$ACTION" ]; then
    show_menu
else
    case "$ACTION" in
        scan)   scan_directory ;;
        perms)  permission_audit ;;
        ext)    extension_report ;;
        backup) backup_all ;;
        *)      log_error "Unknown action '$ACTION' (use: scan | perms | ext | backup)"
                exit 1 ;;
    esac
fi
