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

# System update and dependencies
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

# Database setup
if [ "$CLEAN_INSTALL" = true ]; then
    echo "Clean install: dropping previous data..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${PG_DATABASE};" || true
    sudo -u postgres psql -c "DROP ROLE IF EXISTS ${PG_USER};" || true
fi

echo "Creating user and database..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${PG_DATABASE}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${PG_DATABASE};"
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

# Dependency check
echo "Checking PostgreSQL dependencies..."
dpkg -l | grep -E "postgresql-${PG_VERSION}|postgresql-server-dev-${PG_VERSION}" || {
    echo "Error: PostgreSQL ${PG_VERSION} or dev packages not found"
    exit 1
}

# Functions
build_pgai() {
    local extension_dir="projects/extension"
    cd "$extension_dir" || exit 1

    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi

    . venv/bin/activate
    pip install --upgrade pip
    pip install -r old_requirements.txt

    python3 build.py build || return 1
    python3 build.py install || return 1

    deactivate
}

remove_pgai() {
    echo "Removing previous installation of pgai..."
    sudo -u postgres psql -d ${PG_DATABASE} -c "DROP EXTENSION IF EXISTS pgai CASCADE;"
    sudo rm -f "${PG_EXTENSION_DIR}/pgai.control"
    sudo rm -f "${PG_EXTENSION_DIR}/pgai--*.sql"
    sudo rm -f "${PGLIB_DIR}/pgai.so"

    if [ -d "/tmp/pgai/projects/extension/venv" ]; then
        source /tmp/pgai/projects/extension/venv/bin/activate
        pip uninstall -y pgai
        deactivate
    fi

    rm -rf /tmp/pgai
}

prepare_sql_files() {
    local sql_file="$1"
    local output_file="$2"
    local tmp_file="/tmp/pgai_tmp.sql"

    sed -e 's/@extowner@/postgres/g' \
        -e 's/@extschema@/public/g' \
        -e 's/@extversion@/0.6.1-dev/g' \
        -e 's|@extschema:vector@|vector|g' \
        -e 's/set local search_path = pg_catalog, pg_temp;/SET search_path = pg_catalog, pg_temp;/g' \
        "$sql_file" | grep -v '^--' > "$tmp_file"

    {
        echo "BEGIN;"
        echo "SET search_path TO public;"
        cat "$tmp_file"
        echo "COMMIT;"
    } > "$output_file"

    rm -f "$tmp_file"
    return 0
}

# Main installation
remove_pgai

echo "Installing pgai..."
cd /tmp
git clone ${PGAI_REPO}
cd pgai

build_pgai || {
    echo "Error: pgai build failed"
    exit 1
}

echo "Installing SQL files..."
SQL_DIR="/tmp/pgai/projects/extension/sql"
if [ -d "$SQL_DIR" ]; then
    echo "Found SQL directory: $SQL_DIR"
    SQL_OUT="${PG_EXTENSION_DIR}/pgai--0.6.1-dev.sql"
    
    if prepare_sql_files "${SQL_DIR}/ai--0.6.1-dev.sql" "$SQL_OUT"; then
        sudo chown postgres:postgres "$SQL_OUT"
        sudo chmod 644 "$SQL_OUT"
        echo "SQL file installed: $SQL_OUT"

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

# Create control file
cat > "${PG_EXTENSION_DIR}/pgai.control" << EOL
# pgai extension
comment = 'PostgreSQL AI Extension'
default_version = '0.6.1-dev'
module_pathname = '\$libdir/pgai'
schema = public
requires = 'plpgsql,vector'
relocatable = true
EOL

# Final setup and verification
systemctl restart postgresql
sudo -u postgres psql -d ${PG_DATABASE} -c "DROP EXTENSION IF EXISTS pgai;"
sudo -u postgres psql -d ${PG_DATABASE} -c "CREATE EXTENSION pgai VERSION '0.6.1-dev';"

echo "Verifying installation..."
sudo -u postgres psql -d ${PG_DATABASE} -c "\dx pgai"

echo "Configuring pgai for Ollama (port ${OLLAMA_PORT})..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT pgai_set_service('ollama', 'http://${OLLAMA_HOST}:${OLLAMA_PORT}');"

echo "Test query to model 'qwen2.5:latest'..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT pgai_query('ollama', 'qwen2.5:latest', 'Скажи \"Привіт, світ!\" українською') AS response;"

echo "Installation completed successfully!"
echo "System configured for using PostgreSQL with pgai and Ollama (model qwen2.5:latest)."
echo "If you need to start from scratch, set CLEAN_INSTALL=true and re-run the script."
