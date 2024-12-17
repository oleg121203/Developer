#!/bin/bash
set -e

# Установка GPG без sudo
if ! command -v gpg &> /dev/null; then
    apt-get update && apt-get install -y gnupg2
fi

# Настройка для текущего пользователя
cd /workspace
export GPG_TTY=$(tty)

# Генерация GPG ключа
cat >key_config <<EOF
%echo Generating GPG key
Key-Type: RSA
Key-Length: 4096
Name-Real: Oleg Kizyma
Name-Email: oleg1203@gmail.com
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF

gpg --batch --generate-key key_config
rm key_config

# Настройка Git для использования GPG
KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | cut -d'/' -f2 | cut -d' ' -f1)
if [ ! -z "$KEY_ID" ]; then
    git config --global user.signingkey "$KEY_ID"
    git config --global commit.gpgsign true
    git config --global gpg.program $(which gpg)
    
    # Экспорт публичного ключа
    echo "Your GPG public key:"
    gpg --armor --export "$KEY_ID"
else
    echo "Failed to generate GPG key"
    exit 1
fi
