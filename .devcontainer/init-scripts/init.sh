#!/bin/bash
if [ ! -x "$0" ]; then
    chmod +x "$0"
fi
set -e

echo "=== Starting container initialization ==="

# Save current branch if repository exists
CURRENT_BRANCH=""
if [ -d .git ]; then
    CURRENT_BRANCH=$(git branch --show-current || echo "main")
    echo "Current branch: $CURRENT_BRANCH"
fi

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

# Restore original branch if it was saved
if [ ! -z "$CURRENT_BRANCH" ]; then
    echo "Restoring branch: $CURRENT_BRANCH"
    git checkout "$CURRENT_BRANCH" 2>/dev/null || echo "Warning: Could not restore branch $CURRENT_BRANCH"
fi

# Ensure proper GPG environment
export GPG_TTY=$(tty)
chmod 700 ~/.gnupg
echo "disable-ipv6" > ~/.gnupg/dirmngr.conf
echo "keyserver hkps://keys.openpgp.org" > ~/.gnupg/gpg.conf

# Enhanced GPG Setup
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Базовая конфигурация GPG
cat > ~/.gnupg/gpg.conf <<EOF
use-agent
pinentry-mode loopback
no-tty
allow-loopback-pinentry
EOF

# Конфигурация GPG агента
cat > ~/.gnupg/gpg-agent.conf <<EOF
allow-loopback-pinentry
enable-ssh-support
pinentry-program /usr/bin/pinentry-tty
default-cache-ttl 34560000
max-cache-ttl 34560000
EOF

# Перезапуск GPG агента
gpgconf --kill all
gpg-agent --daemon --allow-loopback-pinentry

# Установка переменных окружения
export GPG_TTY=$(tty)
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc

# Создание нового ключа если не существует
if ! gpg --list-secret-keys --keyid-format=long | grep -q "oleg1203@gmail.com"; then
    # Генерация ключа без пароля
    gpg --batch --gen-key <<EOF
%echo Generating a basic OpenPGP key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: Oleg Kizyma
Name-Email: oleg1203@gmail.com
Expire-Date: 0
%no-protection
%commit
%echo done
EOF
fi

# Настройка Git для использования GPG
KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | head -n 1 | cut -d'/' -f2 | cut -d' ' -f1)
if [ ! -z "$KEY_ID" ]; then
    git config --global user.signingkey "$KEY_ID"
    git config --global commit.gpgsign true
    git config --global gpg.program $(which gpg)
fi

# Тест подписи
echo "test" | gpg --clearsign || echo "GPG test signing failed"

// ...existing code...

# Add more entropy
apt-get update && apt-get install -y rng-tools haveged || true
service haveged start || true

echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent

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

# Add GPG environment variables to bashrc
cat >> ~/.bashrc <<-EOF
export GPG_TTY=\$(tty)
export SSH_AUTH_SOCK=\$(gpgconf --list-dirs agent-ssh-socket)
gpg-connect-agent updatestartuptty /bye >/dev/null
EOF

echo "=== Container initialization complete ==="
exit 0
