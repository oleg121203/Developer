#!/bin/bash

# Enable better error handling and logging
set -euo pipefail
exec 1> >(tee -a "/tmp/init-script.log") 2>&1

# Ensure script is run with bash
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

# Add logging function
log() {
    echo "[$(date)] $1"
}

echo "=== Starting container initialization ==="

# Ensure execution permissions on all scripts in init-scripts folder
find .devcontainer/init-scripts -name "*.sh" -exec chmod +x {} \;

# Run permissions.sh
log "Running permissions.sh..."
./.devcontainer/init-scripts/permissions.sh || { log "permissions.sh failed"; exit 1; }

# Git configuration
log "Configuring Git..."
git config --global user.name "Oleg Kizyma"
git config --global user.email "oleg1203@gmail.com"
git config --global core.editor "code --wait"
git config --global pull.rebase true
git config --global push.autoSetupRemote true
git config --global push.default current

# Run check_git_config.sh
log "Running check_git_config.sh..."
./.devcontainer/init-scripts/check_git_config.sh || { log "check_git_config.sh failed"; exit 1; }

# Save current branch if repository exists
CURRENT_BRANCH=""
if [ -d .git ]; then
    CURRENT_BRANCH=$(git branch --show-current || echo "main")
    log "Current branch: $CURRENT_BRANCH"
fi

# Create directories
mkdir -p ~/.gnupg ~/.ssh

# Setup Python environment
log "Setting up Python environment..."
python3 -m venv .venv || { log "Warning: Failed to create virtual environment"; }
if [ -f .venv/bin/activate ]; then
    source .venv/bin/activate
    # Upgrade pip and install dependencies
    python3 -m pip install --upgrade pip || { log "Warning: Failed to upgrade pip"; exit 1; }
    pip install --upgrade setuptools wheel || { log "Warning: Failed to upgrade setuptools and wheel"; }
    if [ -f requirements.txt ]; then
        log "Installing dependencies from requirements.txt..."
        pip install -r requirements.txt || { log "Error: Failed to install dependencies"; exit 1; }
    fi
fi

# Ensure proper GPG environment
export GPG_TTY=$(tty)
chmod 700 ~/.gnupg
echo "disable-ipv6" > ~/.gnupg/dirmngr.conf
echo "keyserver hkps://keys.openpgp.org" > ~/.gnupg/gpg.conf

# Enhanced GPG Setup
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Base GPG configuration
cat > ~/.gnupg/gpg.conf <<EOF
use-agent
pinentry-mode loopback
no-tty
EOF

# Configure GPG agent
cat > ~/.gnupg/gpg-agent.conf <<EOF
allow-loopback-pinentry
enable-ssh-support
pinentry-program /usr/bin/pinentry-tty
default-cache-ttl 34560000
max-cache-ttl 34560000
EOF

# Restart GPG agent
gpgconf --kill all
gpg-agent --daemon --allow-loopback-pinentry

# Set GPG environment variables
export GPG_TTY=$(tty)
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc

# Improved package installation with checks
install_packages() {
    local packages=("$@")
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$pkg"; then
            sudo apt-get install -y "$pkg" || log "Warning: Failed to install $pkg"
        fi
    done
}

# Install required packages safely
install_packages gnupg2 pinentry-tty gpg-agent rng-tools haveged

# Generate new GPG key if it doesn't exist
if ! gpg --list-secret-keys --keyid-format=long | grep -q "oleg1203@gmail.com"; then
    # Check for existing backup
    if [ -d "$HOME/.gnupg.bak" ]; then
        log "Found GPG backup, restoring..."
        cp -r "$HOME/.gnupg.bak/"* "$HOME/.gnupg/"
    else
        log "Generating new GPG key..."
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
fi

# Configure Git to use GPG
KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | head -n 1 | cut -d'/' -f2 | cut -d' ' -f1)
if [ ! -z "$KEY_ID" ]; then
    git config --global user.signingkey "$KEY_ID"
    git config --global commit.gpgsign true
    git config --global gpg.program $(which gpg)
fi

# Test GPG signing
log "Testing GPG signing..."
echo "test" | gpg --clearsign || log "GPG test signing failed"

# Add more entropy
sudo apt-get update && sudo apt-get install -y rng-tools haveged || true
sudo service haveged start || true

# Setup Git hooks
log "Setting up Git hooks..."
mkdir -p /workspace/.git/hooks

cat > /workspace/.git/hooks/post-commit <<EOF
#!/bin/bash
set -e

# Run backup script without auto-signing
/workspace/.devcontainer/init-scripts/backup.sh
EOF

chmod +x /workspace/.git/hooks/post-commit
chmod +x /workspace/.devcontainer/init-scripts/backup.sh

# Improved shell detection and compatibility
SHELL_TYPE="$(basename "$SHELL")"
if [ "$SHELL_TYPE" = "bash" ]; then
    RCFILE="$HOME/.bashrc"
elif [ "$SHELL_TYPE" = "zsh" ]; then
    RCFILE="$HOME/.zshrc"
else
    RCFILE="$HOME/.profile"
fi

# Shell customization with safe defaults
if [ -f "$HOME/.bashrc" ]; then
    # Remove any existing prompt configuration
    sed -i '/PROMPT_CONFIGURED/d' "$HOME/.bashrc"
    sed -i '/parse_git_branch/d' "$HOME/.bashrc"
    
    # Add git branch parser and prompt configuration
    cat >> "$HOME/.bashrc" <<EOF
# Git branch parser
parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}

# Prompt configuration
if [ -z "\${PROMPT_CONFIGURED:-}" ]; then
    export PROMPT_CONFIGURED=1
    PS1='\[\033[01;32m\](\$) \u\[\033[00m\] ➜ \[\033[01;34m\]\w\[\033[91m\]\$(parse_git_branch)\[\033[00m\]\$ '
fi
EOF
fi

# Add GPG environment variables to bashrc
cat >> ~/.bashrc <<-EOF
export GPG_TTY=\$(tty)
export SSH_AUTH_SOCK=\$(gpgconf --list-dirs agent-ssh-socket)
gpg-connect-agent updatestartuptty /bye >/dev/null
EOF

# Simpler Ollama check
check_ollama() {
    log "Checking Ollama API availability..."
    local response
    
    response=$(curl -s http://${OLLAMA_API_HOST:-172.17.0.1}:${OLLAMA_API_PORT:-11434} || echo "Failed")
    
    if [[ "$response" == *"Ollama is running"* ]]; then
        log "Ollama is running and ready!"
        return 0
    else
        log "ERROR: Ollama not running. Response: $response"
        return 1
    fi
}

# Run model.py in background
log "Starting model.py..."
nohup python3 /workspace/model.py > /tmp/model.log 2>&1 &
MODEL_PID=$!
log "model.py started (PID: $MODEL_PID)"

# Check if model.py is running
sleep 5
if ps -p $MODEL_PID > /dev/null; then
    log "model.py is running"
else
    log "Error: model.py failed to start"
    exit 1
fi

# Run health check at the end
if ! check_ollama; then
    log "WARNING: Ollama not available, but continuing..."
fi

log "=== Container initialization complete ==="
exit 0
