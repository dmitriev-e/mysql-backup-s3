#!/bin/bash

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

# Build S3 path for backup
# if folder does not exist, s3cmd will create it
S3_BACKUP_PATH="s3://$S3_BUCKET/$SRV_FOLDER/$S3_PREFIX/$DB_NAME"

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${DB_NAME}_backup_$DATE.sql.gz"
TEMP_FILE="/tmp/$BACKUP_FILE"

echo "Creating database backup: $DB_NAME"
echo "S3 destination: $S3_BACKUP_PATH/$BACKUP_FILE"

# Create backup and upload to S3 storage
mysqldump \
    $MYSQLDUMP_OPTIONS \
    -u "$DB_USER" \
    -p"$DB_PASSWORD" \
    "$DB_NAME" | \
gzip | \
s3cmd put - "$S3_BACKUP_PATH/$BACKUP_FILE" \
    --storage-class=$STORAGE_CLASS

if [ $? -eq 0 ]; then
    echo "Backup successfully uploaded to $S3_BACKUP_PATH/$BACKUP_FILE"
    # delete the temp file
    rm -f "$TEMP_FILE"
else
    echo "Backup failed"
    # delete the temp file
    rm -f "$TEMP_FILE"
    exit 1
fi
