#!/usr/bin/env bash
set -euo pipefail
export PAGER=cat  # Отключаем pager для всего скрипта

# Configuration variables
PG_USER="myuser"
PG_PASSWORD="mypassword"
PG_DATABASE="mydb"
OLLAMA_HOST="localhost"
OLLAMA_PORT="11434"
PG_VERSION="16"
PGVECTOR_REPO="https://github.com/pgvector/pgvector.git"
CLEAN_INSTALL=true

# PostgreSQL paths
PGLIB_DIR=$(pg_config --pkglibdir)
PG_EXTENSION_DIR=$(pg_config --sharedir)/extension
PG_LIBDIR=$(dirname "$PGLIB_DIR")

# Set PGDATA and PGPORT
export PGDATA=/var/lib/postgresql/16/main
export PGPORT=5432

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo or as root."
    exit 1
fi

# System update and dependencies
echo "Updating system and installing dependencies..."
apt-get update -y
apt-get upgrade -y

# Проверяем доступные пакеты plpython3
echo "Checking available plpython3 packages..."
apt-cache search postgresql-plpython3

# Пробуем разные варианты установки plpython3
install_plpython3() {
    local versions=("postgresql-plpython3-${PG_VERSION}" "postgresql-plpython3u-${PG_VERSION}" "plpython3" "plpython3u")

    for pkg in "${versions[@]}"; do
        echo "Trying to install $pkg..."
        if apt-get install -y "$pkg" 2>/dev/null; then
            echo "$pkg installed successfully"
            return 0
        fi
    done

    echo "Failed to install any plpython3 package. System info:"
    lsb_release -a
    return 1
}

# Основные зависимости
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

# Устанавливаем plpython3
install_plpython3 || {
    echo "Error: Failed to install plpython3. Please check package availability."
    exit 1
}

# Create PostgreSQL service configuration
echo "Creating PostgreSQL service configuration..."
cat > /lib/systemd/system/postgresql.service <<EOF
[Unit]
Description=PostgreSQL RDBMS Service
Documentation=https://www.postgresql.org/docs/16/
After=network.target

[Service]
Type=notify
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/postgresql/16/main
Environment=PGPORT=5432

ExecStart=/usr/lib/postgresql/16/bin/postgres -D \${PGDATA}
ExecReload=/usr/lib/postgresql/16/bin/pg_ctl -D \${PGDATA} reload
ExecStop=/usr/lib/postgresql/16/bin/pg_ctl -D \${PGDATA} -m fast stop

TimeoutSec=300
OOMScoreAdjust=-900

[Install]
WantedBy=multi-user.target
EOF

# Set correct permissions
chmod 644 /lib/systemd/system/postgresql.service

# Ensure the data directory exists and has correct permissions
if [ ! -d "/var/lib/postgresql/16/main" ]; then
    echo "Creating PostgreSQL data directory..."
    sudo -u postgres mkdir -p /var/lib/postgresql/16/main
    sudo chown postgres:postgres /var/lib/postgresql/16/main
    sudo chmod 700 /var/lib/postgresql/16/main
    echo "Initializing PostgreSQL database..."
    sudo -u postgres /usr/lib/postgresql/16/bin/initdb -D /var/lib/postgresql/16/main
fi

# Reload systemd and restart PostgreSQL
echo "Applying new PostgreSQL configuration..."
systemctl daemon-reload
systemctl restart postgresql || {
    echo "Error: Failed to restart PostgreSQL"
    systemctl status postgresql.service
    journalctl -xeu postgresql.service
    exit 1
}

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if systemctl is-active --quiet postgresql; then
        break
    fi
    echo "Waiting for PostgreSQL to start... ($i/30)"
    sleep 1
done

# Проверяем, заданы ли переменные среды
if [ -z "${PGDATA:-}" ] || [ -z "${PGPORT:-}" ]; then
    echo "Error: PGDATA или PGPORT не установлены."
    exit 1
fi

# Проверяем существование и права директорий
mkdir -p "/usr/include/postgresql/${PG_VERSION}/server/extension/vector/" || {
    echo "Error: Не удалось создать директорию в /usr/include/postgresql/${PG_VERSION}/server/extension/vector/"
    exit 1
}
mkdir -p "/usr/lib/postgresql/${PG_VERSION}/lib/bitcode/vector/" || {
    echo "Error: Не удалось создать директорию в /usr/lib/postgresql/${PG_VERSION}/lib/bitcode/vector/"
    exit 1
}

# Set postgres password and authentication
echo "Setting up PostgreSQL authentication..."
PG_SYSTEM_USER="postgres"
PG_SYSTEM_PASS="postgres"  # Change this to a secure password

# Устанавливаем trust (упрощённая замена)
echo "Temporarily setting local auth to trust..."
sudo sed -i 's/^local\s\+all\s\+postgres.*/local   all             postgres                                trust/' /etc/postgresql/16/main/pg_hba.conf
sudo sed -i 's/^local\s\+all\s\+all.*/local   all             all                                     trust/' /etc/postgresql/16/main/pg_hba.conf
sudo systemctl restart postgresql

# Update postgres user password without password prompt
echo "Updating postgres user password..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '${PG_SYSTEM_PASS}';"

# Revert authentication method back to md5
echo "Reverting authentication to md5..."
sudo sed -i 's/^local\s\+all\s\+postgres.*/local   all             postgres                                md5/' /etc/postgresql/16/main/pg_hba.conf
sudo sed -i 's/^local\s\+all\s\+all.*/local   all             all                                     md5/' /etc/postgresql/16/main/pg_hba.conf
sudo systemctl restart postgresql

# Export PGPASSWORD для последующих команд
export PGPASSWORD="${PG_SYSTEM_PASS}"

# Create .pgpass file for passwordless authentication
PGPASS_FILE="/var/lib/postgresql/.pgpass"
sudo -u postgres bash -c "echo '*:*:*:postgres:${PG_SYSTEM_PASS}' > ${PGPASS_FILE}"
sudo -u postgres chmod 0600 ${PGPASS_FILE}

# Update all psql commands to use PGPASSWORD
function psql_exec() {
    PGPASSWORD=${PG_SYSTEM_PASS} sudo -E -u postgres psql "$@"
}

# Verify PostgreSQL status
echo "Checking PostgreSQL status..."
if ! sudo systemctl status postgresql | grep -q "active (running)"; then
    echo "Error: PostgreSQL is not running"
    exit 1
fi

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if sudo -u postgres psql -c '\l' >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Database setup
if [ "$CLEAN_INSTALL" = true ]; then
    echo "Clean install: dropping previous data..."
    psql_exec -c "DROP DATABASE IF EXISTS ${PG_DATABASE};" || true
    psql_exec -c "DROP ROLE IF EXISTS ${PG_USER};" || true
fi

echo "Creating user and database..."
psql_exec -tc "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" | grep -q 1 || \
    psql_exec -c "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';"
psql_exec -tc "SELECT 1 FROM pg_database WHERE datname='${PG_DATABASE}'" | grep -q 1 || \
    psql_exec -c "CREATE DATABASE ${PG_DATABASE};"
psql_exec -c "GRANT ALL PRIVILEGES ON DATABASE ${PG_DATABASE} TO ${PG_USER};"

# Install pgvector and create schemas
echo "Installing pgvector..."
cd /tmp
rm -rf pgvector || true
git clone ${PGVECTOR_REPO}
cd pgvector
make
make install

# Create required schemas with improved error handling
echo "Creating required schemas..."
psql_exec -d ${PG_DATABASE} -c "CREATE SCHEMA IF NOT EXISTS vector; CREATE SCHEMA IF NOT EXISTS ai; CREATE EXTENSION IF NOT EXISTS vector SCHEMA vector; CREATE EXTENSION IF NOT EXISTS plpython3u;" || {
    echo "Error creating schemas or extensions."
    exit 1
}

# Create and setup Python virtual environment for postgres
echo "Setting up Python virtual environment..."
VENV_PATH="/var/lib/postgresql/venv"
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

sudo -u postgres python3 -m venv ${VENV_PATH} || {
    echo "Error creating virtual environment"
    exit 1
}

# Install ollama in virtual environment with proper activation
echo "Installing ollama package..."
sudo -u postgres bash -c "source ${VENV_PATH}/bin/activate && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir ollama" || {
    echo "Error installing ollama package"
    exit 1
}

# Check ollama package installation and permissions
echo "Checking ollama installation..."
sudo -u postgres ls -la ${VENV_PATH}/lib/python*/site-packages/ollama* || {
    echo "Error: ollama package not found or permissions issue"
    exit 1
}

# Remove existing function if exists
psql_exec -d ${PG_DATABASE} -c "DROP FUNCTION IF EXISTS install_ollama();" || {
    echo "Error dropping existing install_ollama function"
    exit 1
}

# Create function to use installed ollama with correct path
psql_exec -d ${PG_DATABASE} -c "CREATE OR REPLACE FUNCTION install_ollama() RETURNS TEXT AS \$\$ 
import sys, os, glob

venv_path = '${VENV_PATH}'
python_version = '.'.join(map(str, sys.version_info[:2]))
site_packages = glob.glob(os.path.join(venv_path, 'lib', f'python{python_version}', 'site-packages'))[0]

if site_packages not in sys.path:
    sys.path.insert(0, site_packages)
    
try:
    import ollama
    return 'Ollama installed successfully at ' + site_packages
except ImportError as e:
    plpy.error(f'Failed to import ollama from {site_packages}: {str(e)}')
except Exception as e:
    plpy.error(f'Unexpected error: {str(e)}')
\$\$ LANGUAGE plpython3u;" || {
    echo "Error creating install_ollama function"
    exit 1
}

# Verify ollama installation
echo "Verifying ollama installation..."
psql_exec -d ${PG_DATABASE} -c "SELECT install_ollama();" || {
    echo "Error verifying ollama installation"
    rm -rf ${VENV_PATH}  # Cleanup on failure
    exit 1
}

# Function to check network connectivity
psql_exec -d ${PG_DATABASE} -c "CREATE OR REPLACE FUNCTION test_network() RETURNS TEXT AS \$\$ 
import socket
try:
    socket.create_connection(('8.8.8.8', 53), 2)
    return 'Network connection successful'
except OSError as e:
    return f'Network connection failed: {e}'
\$\$ LANGUAGE plpython3u;" || {
    echo "Error creating test_network function. Check PostgreSQL logs."
    exit 1
}

psql_exec -d ${PG_DATABASE} -c "SELECT test_network();" || {
    echo "Error executing test_network(). Check PostgreSQL logs."
    exit 1
}

# Function to check environment variables
psql_exec -d ${PG_DATABASE} -c "CREATE OR REPLACE FUNCTION check_env() RETURNS TEXT AS \$\$ 
import os
return str(os.environ)
\$\$ LANGUAGE plpython3u;" || {
    echo "Error creating check_env function. Check PostgreSQL logs."
    exit 1
}

psql_exec -d ${PG_DATABASE} -c "SELECT check_env();" || {
    echo "Error executing check_env(). Check PostgreSQL logs."
    exit 1
}

# Function to get Python version
psql_exec -d ${PG_DATABASE} -c "CREATE OR REPLACE FUNCTION get_python_version() RETURNS TEXT AS \$\$ 
import sys
return sys.version
\$\$ LANGUAGE plpython3u;" || {
    echo "Error creating get_python_version function. Check PostgreSQL logs."
    exit 1
}

psql_exec -d ${PG_DATABASE} -c "SELECT get_python_version();" || {
    echo "Error executing get_python_version(). Check PostgreSQL logs."
    exit 1
}

# Create tables and triggers
psql_exec -d ${PG_DATABASE} <<SQL_BLOCK
CREATE TABLE IF NOT EXISTS questions (
    question TEXT,
    answer TEXT DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS answers (
    question TEXT,
    answer TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
GRANT ALL PRIVILEGES ON TABLE questions TO ${PG_USER};
GRANT ALL PRIVILEGES ON TABLE answers TO ${PG_USER};

CREATE OR REPLACE FUNCTION process_question()
RETURNS TRIGGER AS \$function\$
import ollama
import plpy

def generate_answer(question):
    try:
        client = ollama.Client("http://localhost:11434")
        response = client.generate(model='qwen2.5:latest', prompt=question)
        try:
            return response.choices[0].text
        except AttributeError:
            try:
                return response.generations[0].text
            except AttributeError:
                return str(response)
    except Exception as e:
        plpy.log(f"Ollama error for question '{question}': {str(e)}")
        return f"Error: {str(e)}"

if TD["new"].get("question") is not None:
    question = TD["new"].get("question")
    answer = generate_answer(question)
    try:
        with plpy.subtransaction():
            plpy.execute("UPDATE questions SET answer = %s WHERE question = %s", (answer, question))
            plpy.execute("INSERT INTO answers (question, answer) VALUES (%s, %s)", (question, answer))
    except plpy.Error as e:
        plpy.log(f"Database error for question '{question}': {e}")
        return "SKIP"

return "MODIFY"
\$function\$ LANGUAGE plpython3u;

CREATE TRIGGER process_question_trigger
    AFTER INSERT ON questions
    FOR EACH ROW
    EXECUTE FUNCTION process_question();

-- Update privileges
GRANT ALL PRIVILEGES ON DATABASE ${PG_DATABASE} TO ${PG_USER};
REVOKE CREATE ON DATABASE ${PG_DATABASE} FROM ${PG_USER};
SQL_BLOCK

# Verify schemas exist
echo "Verifying schemas..."
psql_exec -d ${PG_DATABASE} -c "\dn" | grep -E "vector|ai" || {
    echo "Error: Required schemas not created"
    exit 1
}

# Dependency check
echo "Checking PostgreSQL dependencies..."
dpkg -l | grep -E "postgresql-${PG_VERSION}|postgresql-server-dev-${PG_VERSION}" || {
    echo "Error: PostgreSQL ${PG_VERSION} or dev packages not found"
    exit 1
}

# Удаляем создание ollama_pg.py и его запуск
echo "Trigger setup completed. You can now insert questions into the questions table."
echo "Example: psql -d ${PG_DATABASE} -U ${PG_USER} -c \"INSERT INTO questions (question) VALUES ('What is PostgreSQL?');\""

# Restart PostgreSQL service
echo "Restarting PostgreSQL service..."
sudo systemctl restart postgresql || {
    echo "Error restarting PostgreSQL service."
    exit 1
}

# Add final verification
echo "=== Проверка установки ==="
psql_exec -d ${PG_DATABASE} -c "\dx" || {
    echo "Error: Unable to list extensions"
    exit 1
}

echo "Script executed successfully."