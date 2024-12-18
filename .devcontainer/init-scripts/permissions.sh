#!/bin/bash
<<<<<<< Updated upstream
if [ ! -x "$0" ]; then
    chmod +x "$0"
fi
=======
>>>>>>> Stashed changes
set -e

echo "=== Setting up permissions ==="

# Основные директории
sudo chown -R vscode:vscode /workspace
sudo chown -R vscode:vscode /home/vscode

# GPG настройки
chmod 700 /home/vscode/.gnupg
find /home/vscode/.gnupg -type f -exec chmod 600 {} \;

# SSH настройки
chmod 700 /home/vscode/.ssh
find /home/vscode/.ssh -type f -exec chmod 600 {} \;

# Continue директория
mkdir -p /home/vscode/.continue
chown -R vscode:vscode /home/vscode/.continue
chmod -R 755 /home/vscode/.continue

# Python venv
if [ -d /workspace/.venv ]; then
    chown -R vscode:vscode /workspace/.venv
    chmod -R 755 /workspace/.venv
fi

echo "=== Permissions setup complete ==="
