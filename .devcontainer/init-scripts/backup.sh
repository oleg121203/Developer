#!/bin/bash
if [ ! -x "$0" ]; then
    chmod +x "$0"
fi
set -e

# Директория для резервных копий
BACKUP_DIR="/workspace/.backups"
# Исходная директория
SOURCE_DIR="/workspace"

# Создаем директорию для бэкапов если её нет
mkdir -p "$BACKUP_DIR"

# Имя файла бэкапа с датой
BACKUP_FILE="$BACKUP_DIR/backup_$(date +'%Y%m%d_%H%M%S').tar.gz"

# Создание бэкапа
tar --exclude=".backups" --exclude=".git" --exclude=".venv" -czf "$BACKUP_FILE" -C "$SOURCE_DIR" .

echo "Backup created at $BACKUP_FILE"

# Удаление старых бэкапов, оставляем только последние 5
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR" | wc -l)
if [ "$BACKUP_COUNT" -gt 5 ]; then
    ls -1t "$BACKUP_DIR" | tail -n +6 | xargs -I {} rm -f "$BACKUP_DIR/{}"
    echo "Old backups deleted, keeping only the latest 5 backups."
fi