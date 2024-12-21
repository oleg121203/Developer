#!/usr/bin/env bash
set -euo pipefail

# Configuration
PG_USER="myuser"
PG_PASSWORD="mypassword"
PG_DATABASE="mydb"

# Check Ollama status
echo "=== Checking Ollama server ==="
if ! systemctl is-active --quiet ollama; then
    echo "Starting Ollama server..."
    sudo systemctl start ollama || sudo ollama start
fi

# Test database connection
echo "=== Testing database connection ==="
PGPASSWORD=${PG_PASSWORD} psql -d ${PG_DATABASE} -U ${PG_USER} -c "SELECT version();"

# Add test question
echo "=== Adding test question ==="
PGPASSWORD=${PG_PASSWORD} psql -d ${PG_DATABASE} -U ${PG_USER} -c "INSERT INTO questions (question) VALUES ('Что такое PostgreSQL?');"

# Monitor PostgreSQL logs
echo "=== Last PostgreSQL logs ==="
sudo tail -n 20 /var/log/postgresql/postgresql-16-main.log

# Check results
echo "=== Checking results ==="
PGPASSWORD=${PG_PASSWORD} psql -d ${PG_DATABASE} -U ${PG_USER} -c "\
    SELECT q.question, 
           substring(q.answer, 1, 50) as answer_preview, 
           q.created_at,
           EXISTS(SELECT 1 FROM answers a WHERE a.question = q.question) as has_answer
    FROM questions q
    ORDER BY q.created_at DESC
    LIMIT 5;"

# Check trigger status
echo "=== Checking trigger configuration ==="
PGPASSWORD=${PG_PASSWORD} psql -d ${PG_DATABASE} -U ${PG_USER} -c "\
    SELECT pg_trigger_depth() as trigger_depth,
           current_setting('plpython3.extra_modules', true) as python_modules,
           current_setting('plpython3.python_path', true) as python_path;"

echo "Test completed."
