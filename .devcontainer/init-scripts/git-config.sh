#!/bin/bash
set -e

# Configure Git
git config --global user.name "Oleg Kizyma"
git config --global user.email "oleg1203@gmail.com"
git config --global commit.gpgsign true
git config --global push.autoSetupRemote true
git config --global push.default current
git config --global core.editor "code --wait"
git config --global pull.rebase true

# Generate and configure GPG key
gpg --batch --generate-key <<EOF
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

# Configure GPG for Git
KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | cut -d'/' -f2 | cut -d' ' -f1)
if [ ! -z "$KEY_ID" ]; then
    git config --global user.signingkey "$KEY_ID"
    echo "Your GPG public key:"
    gpg --armor --export "$KEY_ID"
fi
