#!/bin/bash

# Измените эти значения на реальные
PG_USER="myuser"
PG_PASSWORD="mypassword" 
PG_DATABASE="mydb"
PG_VECTOR_REPO="https://github.com/pgvector/pgvector.git"

# Функція для виводу помилки та завершення скрипту
fail_and_exit() {
    echo "Error: $1"
    exit 1
}

# Установка зависимостей
echo "Installing required packages..."
sudo apt-get update
sudo apt-get install -y postgresql-plpython3-16 postgresql-server-dev-16

# Перевірка статусу PostgreSQL і підняття, якщо не працює
if ! systemctl is-active --quiet postgresql.service; then
    echo "PostgreSQL is not running. Starting now..."
    sudo service postgresql start || fail_and_exit "Failed to start PostgreSQL"
fi

# Удаление существующей базы и пользователя
echo "Dropping existing database and user..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${PG_DATABASE};"
sudo -u postgres psql -c "DROP USER IF EXISTS ${PG_USER};"

# Создание нового пользователя
echo "Creating new user..."
sudo -u postgres psql -c "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';"

# Создание новой базы данных
echo "Creating new database..."
sudo -u postgres psql -c "CREATE DATABASE ${PG_DATABASE} OWNER ${PG_USER};"

# Установка расширения plpython3u
echo "Installing plpython3u extension..."
sudo -u postgres psql -d ${PG_DATABASE} -c "CREATE EXTENSION IF NOT EXISTS plpython3u;"

# Встановлюємо pgvector та створюємо схему
echo "Installing pgvector..."
cd /tmp
rm -rf pgvector || true
git clone "${PG_VECTOR_REPO}"
cd pgvector
make
sudo make install

echo "Creating required schemas..."
sudo -u postgres psql -d ${PG_DATABASE} -c "CREATE SCHEMA IF NOT EXISTS vector;" || {
    echo "Error creating schema."
    fail_and_exit "Failed to create schema"
}
sudo -u postgres psql -d ${PG_DATABASE} -c "CREATE EXTENSION IF NOT EXISTS vector SCHEMA vector;" || {
    echo "Error installing pgvector extension."
    fail_and_exit "Failed to install pgvector extension"
}

# Створення та настройка Python віртуального окремого середовища для PostgreSQL
echo "Setting up Python virtual environment..."
VENV_PATH="/var/lib/postgresql/venv"
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

sudo -u postgres python3 -m venv ${VENV_PATH} || {
    echo "Error creating virtual environment."
    fail_and_exit "Failed to create virtual environment"
}

# Установка ollama в віртуальному середовищі з правильною активациєю
echo "Installing ollama package..."
sudo -u postgres bash -c "source ${VENV_PATH}/bin/activate && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir ollama" || {
    echo "Error installing ollama package."
    fail_and_exit "Failed to install ollama package"
}

# Перевірка установки ollama пакета та права доступу
echo "Checking ollama installation..."
sudo -u postgres ls -la ${VENV_PATH}/lib/python*/site-packages/ollama* || {
    echo "Error: ollama package not found or permissions issue."
    fail_and_exit "Failed to verify ollama installation"
}

# Видалення існуючої функції, якщо вона існує
echo "Dropping existing install_ollama function..."
sudo -u postgres psql -d ${PG_DATABASE} -c "DROP FUNCTION IF EXISTS install_ollama;" || {
    echo "Error dropping existing install_ollama function."
    fail_and_exit "Failed to drop existing function"
}

# Створення функції для використання установленого ollama з правильним шляхом
echo "Creating install_ollama function..."
sudo -u postgres psql -d ${PG_DATABASE} -c "
CREATE OR REPLACE FUNCTION install_ollama() RETURNS TEXT AS \$\$ 
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
    echo "Error creating install_ollama function."
    fail_and_exit "Failed to create install_ollama function"
}

# Перевірка установки ollama
echo "Verifying ollama installation..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT install_ollama();" || {
    echo "Error verifying ollama installation."
    fail_and_exit "Failed to verify ollama installation"
}

# Створення функції для перевірки мережевого підключення
echo "Creating test_network function..."
sudo -u postgres psql -d ${PG_DATABASE} -c "
CREATE OR REPLACE FUNCTION test_network() RETURNS TEXT AS \$\$ 
import socket
try:
    socket.create_connection(('8.8.8.8', 53), 2)
    return 'Network connection successful'
except OSError as e:
    return f'Network connection failed: {e}'
\$\$ LANGUAGE plpython3u;" || {
    echo "Error creating test_network function."
    fail_and_exit "Failed to create test_network function"
}

# Перевірка мережевого підключення
echo "Testing network connection..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT test_network();" || {
    echo "Error executing test_network(). Check PostgreSQL logs."
    fail_and_exit "Failed to execute test_network()"
}

# Створення функції для перевірки змінних середовища
echo "Creating check_env function..."
sudo -u postgres psql -d ${PG_DATABASE} -c "
CREATE OR REPLACE FUNCTION check_env() RETURNS TEXT AS \$\$ 
import os
return str(os.environ)
\$\$ LANGUAGE plpython3u;" || {
    echo "Error creating check_env function."
    fail_and_exit "Failed to create check_env function"
}

# Перевірка змінних середовища
echo "Verifying environment variables..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT check_env();" || {
    echo "Error executing check_env(). Check PostgreSQL logs."
    fail_and_exit "Failed to execute check_env()"
}

# Створення функції для отримання версії Python
echo "Creating get_python_version function..."
sudo -u postgres psql -d ${PG_DATABASE} -c "
CREATE OR REPLACE FUNCTION get_python_version() RETURNS TEXT AS \$\$ 
import sys
return sys.version
\$\$ LANGUAGE plpython3u;" || {
    echo "Error creating get_python_version function."
    fail_and_exit "Failed to create get_python_version function"
}

# Перевірка версії Python
echo "Verifying Python version..."
sudo -u postgres psql -d ${PG_DATABASE} -c "SELECT get_python_version();" || {
    echo "Error executing get_python_version(). Check PostgreSQL logs."
    fail_and_exit "Failed to execute get_python_version()"
}

# Створення таблиць та триггерів
echo "Creating tables and triggers..."
sudo -u postgres psql -d ${PG_DATABASE} <<SQL_BLOCK
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

-- Оновлення прав доступу
GRANT ALL PRIVILEGES ON DATABASE ${PG_DATABASE} TO ${PG_USER};
REVOKE CREATE ON DATABASE ${PG_DATABASE} FROM ${PG_USER};
SQL_BLOCK

# Перевірка існування схем
echo "Verifying schemas..."
sudo -u postgres psql -d ${PG_DATABASE} -c "\dn" | grep -E "vector|ai" || {
    echo "Error: Required schemas not created."
    fail_and_exit "Failed to verify required schemas"
}

# Перезавантаження PostgreSQL service
echo "Restarting PostgreSQL service..."
sudo systemctl restart postgresql || {
    echo "Error restarting PostgreSQL service."
    fail_and_exit "Failed to restart PostgreSQL service"
}

# Окончальна перевірка установки
echo "=== Проверка установки ==="
sudo -u postgres psql -d ${PG_DATABASE} -c "\dx" || {
    echo "Error: Unable to list extensions."
    fail_and_exit "Failed to check installed extensions"
}

echo "Script executed successfully."

# Очистимо робочу директорію
cd /tmp
rm -rf pgvector