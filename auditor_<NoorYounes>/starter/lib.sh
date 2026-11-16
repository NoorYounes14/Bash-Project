#!/bin/bash
# lib.sh - helper functions for auditor.sh (loaded with "source lib.sh").

# Log file used by log_action (created in the folder the script runs from).
LOG_FILE="auditor.log"

# Print an informational message on the screen.
log_info() {
    local msg="$1"
    echo "[INFO] $msg"
}

# Print an error message on the error output (screen only, not the log file).
log_error() {
    local msg="$1"
    echo "[ERROR] $msg" >&2
}

# Append one line to the log file: date, time and what was done.
log_action() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

# Stop the whole script with an error if the given path is not a directory.
require_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        log_error "Directory '$dir' does not exist."
        exit 1
    fi
}
