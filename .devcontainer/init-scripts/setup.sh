#!/bin/bash
set -e

# Setup Python environment
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel

# Install requirements
if [ -f requirements.txt ]; then
    pip install -r requirements.txt
fi

# Basic Git configuration
git config --global user.name "Oleg Kizyma"
git config --global user.email "oleg1203@gmail.com"
git config --global push.autoSetupRemote true
git config --global push.default current
git config --global core.editor "code --wait"
git config --global pull.rebase true

# Setup GPG
bash .devcontainer/init-scripts/gpg-init.sh || echo "GPG setup failed, continuing..."

# Add custom prompt
echo 'export PS1="($$$) \u ➜ \w\$ "' >> ~/.bashrc
source ~/.bashrc
