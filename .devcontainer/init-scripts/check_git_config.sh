#!/bin/bash
<<<<<<< Updated upstream
if [ ! -x "$0" ]; then
    chmod +x "$0"
fi
=======
>>>>>>> Stashed changes
set -e

# Проверяем глобальные настройки git
git_name=$(git config --global user.name)
git_email=$(git config --global user.email)

if [ -z "$git_name" ] || [ -z "$git_email" ]; then
    echo "Git не настроен!"
    echo "Выполните команды:"
    echo "git config --global user.name \"Oleg Kizyma\""
    echo "git config --global user.email \"oleg1203@gmail.com\""
    exit 1
else
    echo "Git настроен:"
    echo "user.name: $git_name"
    echo "user.email: $git_email"
fi
