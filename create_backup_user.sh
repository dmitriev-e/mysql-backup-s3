#!/bin/bash

# Script to create MySQL backup user
# This script creates a dedicated MySQL user for backup operations

# Determine script directory path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Please create config.sh based on config.sh.example"
    exit 1
fi

# Load configuration
source "$CONFIG_FILE"

# Check if required variables are set
if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: Required variables not set in config.sh"
    echo "Please ensure DB_NAME, DB_USER, and DB_PASSWORD are configured"
    exit 1
fi

echo "Creating MySQL backup user..."
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "Host: $DB_HOST"

# Prompt for MySQL root password
echo ""
read -s -p "Enter MySQL root password: " ROOT_PASSWORD
echo ""

# Create the backup user
echo "Creating user and setting permissions..."

mysql -h "$DB_HOST" -P "$DB_PORT" -u root -p"$ROOT_PASSWORD" << EOF
-- Create backup user
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';

-- Grant necessary privileges for backup operations
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';

-- Grant PROCESS privilege for consistent backups
GRANT PROCESS ON *.* TO '${DB_USER}'@'localhost';

-- Flush privileges to ensure changes take effect
FLUSH PRIVILEGES;

-- Show user privileges for verification
SHOW GRANTS FOR '${DB_USER}'@'localhost';
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "SUCCESS: Backup user '${DB_USER}' created successfully!"
    echo ""
    echo "The user has been granted the following privileges:"
    echo "- SELECT: Read data from tables"
    echo "- LOCK TABLES: Lock tables during backup"
    echo "- SHOW VIEW: Access to view definitions"
    echo "- EVENT: Access to scheduled events"
    echo "- TRIGGER: Access to triggers"
    echo "- PROCESS: See running processes for consistent backups"
    echo ""
    echo "You can now run backup operations with this user."
else
    echo ""
    echo "ERROR: Failed to create backup user"
    echo "Please check your MySQL root password and try again"
    exit 1
fi 