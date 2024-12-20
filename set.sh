#!/usr/bin/env bash
set -euo pipefail

# Конфігураційні змінні
PG_USER="myuser"
PG_PASSWORD="mypassword"
PG_DATABASE="mydb"
OLLAMA_HOST="localhost"
OLLAMA_PORT="11434"
PG_VERSION="16"
PGAI_REPO="https://github.com/timescale/pgai.git"
PGVECTOR_REPO="https://github.com/pgvector/pgvector.git"

# Встановлюємо true для повної переінсталяції бази, користувача і розширень
CLEAN_INSTALL=true

# Перевірка прав
if [[ $EUID -ne 0 ]]; then
   echo "Будь ласка, запустіть цей скрипт з правами sudo або під користувачем root."
   exit 1
fi

echo "Оновлення системи та встановлення залежностей..."
apt-get update -y
apt-get upgrade -y
apt-get install -y build-essential git libpq-dev postgresql postgresql-contrib "postgresql-server-dev-${PG_VERSION}" llvm-17 just

echo "Перевірка статусу PostgreSQL..."
systemctl enable postgresql
systemctl start postgresql

# Якщо CLEAN_INSTALL=true, видалити існуючу БД та роль
if [ "$CLEAN_INSTALL" = true ]; then
    echo "Чиста інсталяція: видалення попередніх даних..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${PG_DATABASE};" || true
    sudo -u postgres psql -c "DROP ROLE IF EXISTS ${PG_USER};" || true
fi

echo "Створення користувача і БД..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" | grep -q 1 || sudo -u postgres psql -c "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${PG_DATABASE}'" | grep -q 1 || sudo -u postgres psql -c "CREATE DATABASE ${PG_DATABASE};"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${PG_DATABASE} TO ${PG_USER};"

echo "Встановлення pgvector..."
cd /tmp
rm -rf pgvector || true
git clone ${PGVECTOR_REPO}
cd pgvector
make
make install
sudo -u postgres psql -d ${PG_DATABASE} -c "CREATE EXTENSION IF NOT EXISTS vector;"

echo "Встановлення pgai..."
cd /tmp
rm -rf pgai || true
git clone ${PGAI_REPO}
cd pgai
git submodule update --init --recursive

# Створення директорії .git/hooks та базового файлу commit-msg
#echo "Створення директорії .git/hooks та базового файлу commit-msg..."
#mkdir -p .git/hooks/
#cat << 'EOF' > .git/hooks/commit-msg
#!/bin/bash
# Це базовий скрипт commit-msg. Ви можете додати перевірки за потреби.
##exit 0
#EOF
#chmod +x .git/hooks/commit-msg

# Модифікація justfile для вимкнення install-commit-hook
echo "Вимкнення рецепта install-commit-hook у justfile..."
if grep -q "^install-commit-hook:" justfile; then
    sed -i 's/^install-commit-hook:/# install-commit-hook:/g' justfile
    echo "Рецепт install-commit-hook вимкнено."
else
    echo "Рецепт install-commit-hook не знайдено у justfile."
fi

# Перевірка наявності justfile
if [ ! -f "justfile" ]; then
    echo "Не знайдено justfile у репозиторії pgai. Перевірте структуру репозиторію."
    echo "Вміст директорії /tmp/pgai:"
    ls -la /tmp/pgai
    echo "Вміст піддиректорій:"
    find /tmp/pgai -type d -print
    exit 1
fi

# Отримати список доступних рецептів
AVAILABLE_RECIPES=$(just --unstable --list | awk '{print $1}')

# Визначити рецепт для встановлення (перший, який містить 'install')
INSTALL_RECIPE=""
for recipe in $AVAILABLE_RECIPES; do
    if [[ "$recipe" == *"install"* ]]; then
        INSTALL_RECIPE="$recipe"
        break
    fi
done

if [[ -z "$INSTALL_RECIPE" ]]; then
    echo "Не знайдено рецепт для встановлення pgai у justfile. Будь ласка, перевірте доступні рецепти:"
    just --unstable --list
    exit 1
fi

echo "Компіляція та встановлення pgai за допомогою just..."
just --unstable "$INSTALL_RECIPE"

sudo -u postgres psql -d ${PG_DATABASE} -c "CREATE EXTENSION IF NOT EXISTS pgai;"

echo "Налаштування pgai для роботи з Ollama (порт ${OLLAMA_PORT})..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT pgai_set_service('ollama', 'http://${OLLAMA_HOST}:${OLLAMA_PORT}');"

echo "Тестовий запит до моделі 'qwen2.5:latest'..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT pgai_query('ollama', 'qwen2.5:latest', 'Скажи \"Привіт, світ!\" українською') AS response;"

echo "Успішно завершено!"
echo "Система налаштована для використання PostgreSQL з pgai та Ollama (модель qwen2.5:latest)."
echo "Якщо потрібно було почати з нуля, встановлюйте CLEAN_INSTALL=true та повторно запускайте скрипт."