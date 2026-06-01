#!/bin/bash
#
#backup.sh - daily backup of important server config and home directory
# Author: Kenneth (project 1 bootcamp deliverable 

set -euo pipefail 


# --- configuration 

BACKUP_ROOT="/var/backups/server"
SOURCES=("/etc" "/home/ubuntu" "/var/log/nginx")
RETENTION_DAYS=7 
LOG_FILE="/var/log/backup.log" 

# --- Helpers ---
log() {
  echo "[$(date '+%y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" 
}

require_root() {
   if [[ $EUID -ne 0 ]];  then 
     echo "ERROR: this script must be run as root (use sudo)" >&2
     exit 1
    fi 
}

# --- Main ---
require_root 


TODAY=$(date '+%Y-%m-%d') 
BACKUP_DIR="${BACKUP_ROOT}/${TODAY}"


log "starting backup to ${BACKUP_DIR}"

mkdir -p "$BACKUP_DIR" 

for SRC in "${SOURCES[@]}"; do 
     if [[ ! -e "$SRC" ]];  then
     log "WARN: source ${SRC} does not exist, skipping"
     continue 
     fi 

DEST_NAME=$(echo "$SRC" | tr '/' '_' | sed 's/^_//')
ARCHIVE="${BACKUP_DIR}/${DEST_NAME}.tar.gz" 

log "archiving ${SRC} -> ${ARCHIVE}"
tar -czf "$ARCHIVE" -C / "${SRC#/}" 2>/dev/null   || { 
   log "ERROR: tar failed  for ${SRC}" 
   continue 
}

SIZE=$(du -h "$ARCHIVE" | cut -f1)
log "done: ${ARCHIVE} (${SIZE})" 
done 

log "pruning backups older than ${RETENTION_DAYS} days"
find "$BACKUP_ROOT" -maxdepth 1 -type d -name '????-??-??' -mtime +${RETENTION_DAYS} -exec rm -rf {} \; -exec echo X "pruned: {}" \;


log "backup finished"





