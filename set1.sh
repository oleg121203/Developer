#!/usr/bin/env bash
set -euo pipefail

# Configuration variables
PG_USER="myuser"
PG_PASSWORD="mypassword"
PG_DATABASE="mydb"
OLLAMA_HOST="localhost"
OLLAMA_PORT="11434"
PG_VERSION="16"
PGAI_REPO="https://github.com/timescale/pgai.git"
PGVECTOR_REPO="https://github.com/pgvector/pgvector.git"
CLEAN_INSTALL=true

# PostgreSQL paths
PGLIB_DIR=$(pg_config --pkglibdir)
PG_EXTENSION_DIR=$(pg_config --sharedir)/extension
PG_LIBDIR=$(dirname "$PGLIB_DIR")

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo or as root."
    exit 1
fi

echo "Updating system and installing dependencies..."
apt-get update -y
apt-get upgrade -y
apt-get install -y \
    build-essential \
    git \
    libpq-dev \
    postgresql \
    postgresql-contrib \
    "postgresql-server-dev-${PG_VERSION}" \
    llvm-17 \
    just \
    python3-pip \
    python3-dev \
    python3-setuptools \
    python3-venv \
    cmake \
    ninja-build

# Clean install: drop database and user
if [ "$CLEAN_INSTALL" = true ]; then
    echo "Clean install: dropping previous data..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${PG_DATABASE};" || true
    sudo -u postgres psql -c "DROP ROLE IF EXISTS ${PG_USER};" || true
fi

# Create user and database
echo "Creating user and database..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" | grep -q 1 || sudo -u postgres psql -c "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${PG_DATABASE}'" | grep -q 1 || sudo -u postgres psql -c "CREATE DATABASE ${PG_DATABASE};"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${PG_DATABASE} TO ${PG_USER};"

# Install pgvector
echo "Installing pgvector..."
cd /tmp
rm -rf pgvector || true
git clone ${PGVECTOR_REPO}
cd pgvector
make
make install
sudo -u postgres psql -d ${PG_DATABASE} -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Проверка зависимостей
echo "Checking PostgreSQL dependencies..."
dpkg -l | grep -E "postgresql-${PG_VERSION}|postgresql-server-dev-${PG_VERSION}" || {
    echo "Error: PostgreSQL ${PG_VERSION} or dev packages not found"
    exit 1
}

# Функции для сборки pgai
build_pgai() {
    local extension_dir="projects/extension"
    cd "$extension_dir" || exit 1
    
    # Проверяем/создаем виртуальное окружение
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    
    # Активируем виртуальное окружение
    . venv/bin/activate
    
    # Устанавливаем зависимости
    pip install --upgrade pip
    pip install -r old_requirements.txt
    
    # Собираем расширение
    python3 build.py build || return 1
    python3 build.py install || return 1
    
    # Деактивируем виртуальное окружение
    if [ -n "${VIRTUAL_ENV-}" ]; then
        deactivate
    fi
}

# Функция удаления предыдущей установки pgai
remove_pgai() {
    echo "Removing previous installation of pgai..."
    
    # Удаляем расширение из базы данных
    sudo -u postgres psql -d ${PG_DATABASE} -c "DROP EXTENSION IF EXISTS pgai CASCADE;"
    
    # Удаляем файлы расширения
    sudo rm -f "${PG_EXTENSION_DIR}/pgai.control"
    sudo rm -f "${PG_EXTENSION_DIR}/pgai--*.sql"
    sudo rm -f "${PGLIB_DIR}/pgai.so"
    
    # Удаляем пакет pgai из виртуального окружения
    if [ -d "/tmp/pgai/projects/extension/venv" ]; then
        source /tmp/pgai/projects/extension/venv/bin/activate
        pip uninstall -y pgai
        deactivate
    fi
    
    # Удаляем директорию с исходным кодом
    rm -rf /tmp/pgai
}

# Перед установкой удаляем предыдущую версию pgai
remove_pgai

# Install pgai
echo "Installing pgai..."
cd /tmp
git clone ${PGAI_REPO}
cd pgai

# Собираем и устанавливаем pgai
build_pgai || {
    echo "Error: pgai build failed"
    exit 1
}

# Проверка установки
PGLIB_DIR=$(pg_config --pkglibdir)
PG_EXTENSION_DIR=$(pg_config --sharedir)/extension

# Create pgai.control with correct version
echo "Creating pgai.control..."
cat > "${PG_EXTENSION_DIR}/pgai.control" << EOL
# pgai extension
comment = 'PostgreSQL AI Extension'
default_version = '0.6.1-dev'
relocatable = true
module_pathname = '${PG_LIBDIR}/pgai'
requires = 'plpgsql'
EOL

# Функция подготовки SQL
prepare_sql_files() {
    local sql_file="$1"
    local output_file="$2"
    local tmp_file="/tmp/pgai_tmp.sql"

    echo "Processing SQL file: $sql_file"
    
    if [ ! -f "$sql_file" ]; then
        echo "Error: Source SQL file not found: $sql_file"
        return 1
    fi

    # Save original for debugging
    cp "$sql_file" "${sql_file}.original"
    
    echo "Applying SQL transformations..."
    sed -e 's/@extowner@/postgres/g' \
        -e 's/@extschema@/public/g' \
        -e 's/@extversion@/0.6.1-dev/g' \
        -e 's|@extschema:vector@|vector|g' \
        -e 's/set local search_path = pg_catalog, pg_temp;/SET search_path = pg_catalog, pg_temp;/g' \
        "$sql_file" | grep -v '^--' > "$tmp_file"

    {
        echo "\\set ON_ERROR_STOP on"
        echo "\\set VERBOSITY verbose"
        echo "\\timing on"
        echo "BEGIN;"
        echo "SET client_min_messages TO debug1;"
        echo "SET search_path TO public;"
        cat "$tmp_file"
        echo "COMMIT;"
    } > "$output_file"

    # Enhanced SQL validation
    echo "Pre-checking SQL syntax..."
    if ! sudo -u postgres psql -X -v ON_ERROR_STOP=1 -f "$output_file" --echo-all template1 > "${output_file}.log" 2>&1; then
        echo "SQL syntax pre-check failed. Log contents:"
        cat "${output_file}.log"
        return 1
    fi

    rm -f "$tmp_file"
    echo "SQL file prepared successfully"
    return 0
}

# Обновленная секция установки SQL
echo "Installing SQL files..."
SQL_DIR="/tmp/pgai/projects/extension/sql"
if [ -d "$SQL_DIR" ]; then
    echo "Found SQL directory: $SQL_DIR"
    
    # Подготавливаем SQL файл
    SQL_OUT="${PG_EXTENSION_DIR}/pgai--0.6.1-dev.sql"
    if prepare_sql_files "${SQL_DIR}/ai--0.6.1-dev.sql" "$SQL_OUT"; then
        sudo chown postgres:postgres "$SQL_OUT"
        sudo chmod 644 "$SQL_OUT"
        echo "SQL file installed: $SQL_OUT"
        
        # Проверяем синтаксис
        if sudo -u postgres psql -f "$SQL_OUT" -v ON_ERROR_STOP=1 template1; then
            echo "SQL syntax check passed"
        else
            echo "Error: SQL syntax check failed"
            exit 1
        fi
    else
        echo "Error: Failed to prepare SQL files"
        exit 1
    fi
fi

# Создаем control файл
cat > "${PG_EXTENSION_DIR}/pgai.control" << EOL
# pgai extension
comment = 'PostgreSQL AI Extension'
default_version = '0.6.1-dev'
module_pathname = '\$libdir/pgai'
schema = public
requires = 'plpgsql,vector'
relocatable = true
EOL

# Restart PostgreSQL
systemctl restart postgresql
sudo -u postgres psql -d ${PG_DATABASE} -c "DROP EXTENSION IF EXISTS pgai;"
sudo -u postgres psql -d ${PG_DATABASE} -c "CREATE EXTENSION pgai VERSION '0.6.1-dev';"

# Verify installation with detailed output
echo "Verifying installation..."
sudo -u postgres psql -d ${PG_DATABASE} -c "\dx pgai"

# Configure pgai for Ollama
echo "Configuring pgai for Ollama (port ${OLLAMA_PORT})..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT pgai_set_service('ollama', 'http://${OLLAMA_HOST}:${OLLAMA_PORT}');"

# Test query to model 'qwen2.5:latest'
echo "Test query to model 'qwen2.5:latest'..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT pgai_query('ollama', 'qwen2.5:latest', 'Скажи \"Привіт, світ!\" українською') AS response;"

echo " Successfully completed!"
echo "System configured for using PostgreSQL with pgai and Ollama (model qwen2.5:latest)."
echo "If you need to start from scratch, set CLEAN_INSTALL=true and re-run the script."