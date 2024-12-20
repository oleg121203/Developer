#!/bin/bash
set -euo pipefail

# Переменные окружения
PG_VERSION=${PG_VERSION:-16}
INSTALL_DIR=${INSTALL_DIR:-/usr/lib/postgresql/${PG_VERSION}}

# Функции для проверки
check_dependencies() {
    if ! dpkg -l | grep -q "postgresql-server-dev-${PG_VERSION}"; then
        echo "Installing postgresql-server-dev-${PG_VERSION}..."
        sudo apt-get update
        sudo apt-get install -y postgresql-server-dev-${PG_VERSION} python3-dev
    fi
}

build_extension() {
    cd projects/extension
    
    # Создаем виртуальное окружение
    python3 -m venv venv
    source venv/bin/activate
    
    # Устанавливаем зависимости
    pip install --upgrade pip
    pip install -r old_requirements.txt
    
    # Собираем расширение
    python3 build.py build
    python3 build.py install
}

# Основной скрипт
main() {
    check_dependencies
    build_extension
}

main "$@"
