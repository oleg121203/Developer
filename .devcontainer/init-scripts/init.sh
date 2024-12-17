#!/bin/bash
set -e

echo "=== Starting container initialization ==="

# Create directories
mkdir -p ~/.gnupg ~/.ssh

# Python setup
echo "Setting up Python environment..."
python3 -m venv .venv || echo "Warning: venv creation failed, continuing..."
if [ -f .venv/bin/activate ]; then
    source .venv/bin/activate
    pip install --upgrade pip setuptools wheel || echo "Warning: base package installation failed"
    if [ -f requirements.txt ]; then
        pip install -r requirements.txt || echo "Warning: requirements installation failed"
    fi
fi

# Git and GPG setup
echo "Configuring Git..."
git config --global user.name "Oleg Kizyma" || true
git config --global user.email "oleg1203@gmail.com" || true
git config --global core.editor "code --wait" || true
git config --global pull.rebase true || true
git config --global push.autoSetupRemote true || true
git config --global push.default current || true

# Ensure proper GPG environment
export GPG_TTY=$(tty)
chmod 700 ~/.gnupg
echo "disable-ipv6" > ~/.gnupg/dirmngr.conf
echo "keyserver hkps://keys.openpgp.org" > ~/.gnupg/gpg.conf

# Add more entropy
apt-get update && apt-get install -y rng-tools haveged || true
service haveged start || true

echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent

# Generate GPG key if needed
if ! gpg --list-secret-keys --keyid-format=long | grep -q "Oleg Kizyma"; then
    echo "Generating GPG key..."
    cat >gpg_config <<-EOF
%echo Generating GPG key
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: Oleg Kizyma
Name-Email: oleg1203@gmail.com
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF
    
    # Try to generate key with increased verbosity
    gpg --verbose --batch --gen-key gpg_config
    GPG_STATUS=$?
    rm -f gpg_config

    if [ $GPG_STATUS -ne 0 ]; then
        echo "Failed to generate GPG key. Error code: $GPG_STATUS"
        exit 1
    fi

    # Verify key generation
    if ! gpg --list-secret-keys --keyid-format=long | grep -q "Oleg Kizyma"; then
        echo "GPG key verification failed"
        exit 1
    fi
fi

# Configure Git signing
KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | head -n 1 | cut -d'/' -f2 | cut -d' ' -f1)
if [ ! -z "$KEY_ID" ]; then
    git config --global user.signingkey "$KEY_ID"
    git config --global commit.gpgsign true
    git config --global gpg.program $(which gpg)
    echo "=== Your GPG public key (add to GitHub): ==="
    gpg --armor --export "$KEY_ID"
fi

# Setup Git hooks
echo "Setting up Git hooks..."
mkdir -p /workspace/.git/hooks

cat > /workspace/.git/hooks/post-commit <<EOF
#!/bin/bash
set -e

# Run backup script without auto-signing
/workspace/.devcontainer/init-scripts/backup.sh
EOF

chmod +x /workspace/.git/hooks/post-commit
chmod +x /workspace/.devcontainer/init-scripts/backup.sh

# Shell customization
cat >> ~/.bashrc <<-EOF
export PS1="(\$\$\$) \u ➜ \w\$ "
export GPG_TTY=\$(tty)
[ -f ~/.venv/bin/activate ] && source ~/.venv/bin/activate
EOF

echo "=== Container initialization complete ==="
exit 0
