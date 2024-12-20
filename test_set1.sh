#!/usr/bin/env bash
# test_set1.sh

set -euo pipefail

# Setup
source ./set1.sh

# Test helper functions
log_test() {
    echo "TEST: $1"
}

assert() {
    if [ "$1" != "$2" ]; then
        echo "FAIL: Expected '$2', got '$1'"
        exit 1
    fi
}

# Test 1: Environment Setup
test_environment() {
    log_test "Checking environment variables"
    assert "${PG_USER}" "myuser"
    assert "${PG_DATABASE}" "mydb"
    assert "${PG_VERSION}" "16"
}

# Test 2: PostgreSQL Installation
test_postgresql_installation() {
    log_test "Checking PostgreSQL installation"
    if ! command -v psql &> /dev/null; then
        echo "FAIL: PostgreSQL is not installed"
        exit 1
    fi
    
    pg_version=$(psql --version | grep -oE '[0-9]+' | head -1)
    assert "${pg_version}" "${PG_VERSION}"
}

# Test 3: Database Creation
test_database_creation() {
    log_test "Checking database creation"
    db_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${PG_DATABASE}'")
    assert "${db_exists}" "1"
}

# Test 4: User Creation
test_user_creation() {
    log_test "Checking user creation"
    user_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'")
    assert "${user_exists}" "1"
}

# Test 5: Extensions
test_extensions() {
    log_test "Checking required extensions"
    vector_installed=$(sudo -u postgres psql -d "${PG_DATABASE}" -tAc "SELECT 1 FROM pg_extension WHERE extname='vector'")
    assert "${vector_installed}" "1"
    
    pgai_installed=$(sudo -u postgres psql -d "${PG_DATABASE}" -tAc "SELECT 1 FROM pg_extension WHERE extname='pgai'")
    assert "${pgai_installed}" "1"
}

# Test 6: Configuration
test_configuration() {
    log_test "Checking Ollama configuration"
    ollama_config=$(sudo -u postgres psql -d "${PG_DATABASE}" -tAc "SELECT pgai_get_service('ollama')")
    assert "${ollama_config}" "http://${OLLAMA_HOST}:${OLLAMA_PORT}"
}

# Run all tests
main() {
    echo "Starting tests..."
    test_environment
    test_postgresql_installation
    test_database_creation
    test_user_creation
    test_extensions
    test_configuration