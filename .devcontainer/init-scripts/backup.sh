#!/bin/bash
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