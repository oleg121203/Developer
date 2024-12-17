#!/bin/bash
set -ex

echo "=== Starting setup ==="

# Python setup
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel
[ -f requirements.txt ] && pip install -r requirements.txt

# Git config
git config --global user.name "Oleg Kizyma"
git config --global user.email "oleg1203@gmail.com"
git config --global core.editor "code --wait"
git config --global pull.rebase true
git config --global push.autoSetupRemote true
git config --global push.default current

# GPG setup
if ! bash .devcontainer/init-scripts/gpg-setup.sh; then
    echo "!!! GPG setup failed !!!"
    exit 1
fi

# Prompt setup
echo 'export PS1="($$$) \u ➜ \w\$ "' >> ~/.bashrc
source ~/.bashrc

echo "=== Setup complete ==="
