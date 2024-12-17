#!/bin/bash
set -ex

echo "=== Starting GPG setup ==="

# Проверка и установка GPG
if ! command -v gpg &> /dev/null; then
    echo "Installing GPG..."
    sudo apt-get update && sudo apt-get install -y gnupg2
fi

# Настройка GPG
echo "Configuring GPG..."
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf
echo "keyserver hkps://keys.openpgp.org" >> ~/.gnupg/gpg.conf
killall gpg-agent || true
export GPG_TTY=$(tty)

# Генерация ключа
echo "Generating GPG key..."
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

gpg --batch --debug-all --gen-key key_config
rm key_config

# Настройка Git
KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | head -n 1 | cut -d'/' -f2 | cut -d' ' -f1)
if [ ! -z "$KEY_ID" ]; then
    echo "=== GPG key generated: $KEY_ID ==="
    git config --global user.signingkey "$KEY_ID"
    git config --global commit.gpgsign true
    git config --global gpg.program $(which gpg)
    echo "=== GPG public key: ==="
    gpg --armor --export "$KEY_ID"
else
    echo "!!! GPG key generation failed !!!"
    exit 1
fi
#ACAEE2ADC54FBE31E073DC24A1AE5720F9457E1A