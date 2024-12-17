#!/bin/bash
set -e

# Ensure GPG directory permissions
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc

# Create GPG key with proper settings
cat >key_config <<EOF
    %echo Generating GPG key
    Key-Type: RSA
    Key-Length: 4096
    Name-Real: Oleg Kizyma
    Name-Email: oleg1203@gmail.com
    Expire-Date: 0
    %no-ask-passphrase
    %no-protection
    %commit
    %echo done
EOF

# Generate key and configure Git
gpg --batch --gen-key key_config
rm key_config

# Get key ID and configure Git
KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | head -n 1 | cut -d '/' -f 2 | cut -d ' ' -f 1)

if [ ! -z "$KEY_ID" ]; then
    echo "GPG key generated successfully: $KEY_ID"
    git config --global user.signingkey $KEY_ID
    git config --global commit.gpgsign true
    git config --global gpg.program $(which gpg)
    
    echo "Your GPG public key (add this to GitHub):"
    gpg --armor --export $KEY_ID
else
    echo "Failed to generate GPG key"
    exit 1
fi
