#!/bin/bash

# MySQL restore script from S3 using s3cmd
# Usage: ./restore_mysql_s3cmd.sh [backup_filename] [options]

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

# Override user for restore if separate user is specified
if [ -n "$DB_RESTORE_USER" ]; then
    DB_USER="$DB_RESTORE_USER"
fi

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    echo "Usage: $0 [backup_filename] [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help"
    echo "  -l, --list              Show available backups"
    echo "  -d, --database NAME     Database name (default: $DB_NAME)"
    echo "  -u, --user USER         MySQL user (default: $DB_USER)"
    echo "  -H, --host HOST         MySQL host (default: $DB_HOST)"
    echo "  -p, --port PORT         MySQL port (default: $DB_PORT)"
    echo "  -f, --force             Force restore without confirmation"
    echo "  --dry-run               Only download and check file"
    echo ""
    echo "Examples:"
    echo "  $0 --list"
    echo "  $0 db_backup_20231201_020000.sql.gz"
    echo "  $0 db_backup_20231201_020000.sql.gz.enc --database db_test"
    echo ""
}

# Function to show available backups
list_backups() {
    log_message "Getting list of available backups..."
    
    echo "Available backups in s3://$S3_BUCKET/$SRV_FOLDER/$S3_PREFIX/$DB_NAME/:"
    echo "================================================="
    
    s3cmd ls "s3://$S3_BUCKET/$SRV_FOLDER/$S3_PREFIX/$DB_NAME/" | grep -E '\.(sql|sql\.gz|sql\.gz\.enc)$' | while read -r line; do
        # Parse s3cmd ls output (format: date time size file)
        date_part=$(echo "$line" | awk '{print $1, $2}')
        size_part=$(echo "$line" | awk '{print $3}')
        file_part=$(echo "$line" | awk '{print $4}' | sed "s|s3://$S3_BUCKET/$SRV_FOLDER/$S3_PREFIX/$DB_NAME/||")
        
        # Format size
        if [ "$size_part" -gt 1073741824 ]; then
            size_formatted="$(echo "scale=1; $size_part/1073741824" | bc -l)GB"
        elif [ "$size_part" -gt 1048576 ]; then
            size_formatted="$(echo "scale=1; $size_part/1048576" | bc -l)MB"
        else
            size_formatted="$(echo "scale=1; $size_part/1024" | bc -l)KB"
        fi
        
        printf "%-35s %10s %s\n" "$file_part" "$size_formatted" "$date_part"
    done
    
    echo ""
    echo "For restore use: $0 <filename>"
}

# Function to check database connection
check_database_connection() {
    log_message "Checking database connection..."
    
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p -e "SELECT 1;" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_message "ERROR: Cannot connect to database"
        return 1
    fi
    
    log_message "Database connection successful"
    return 0
}

# Function to check database existence
check_database_exists() {
    local db_name="$1"
    
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p -e "USE $db_name;" >/dev/null 2>&1
    return $?
}

# Function to download backup from S3
download_backup() {
    local backup_file="$1"
    local local_file="$TEMP_DIR/$backup_file"
    
    log_message "Downloading backup from S3: $backup_file"
    
    # Check if file exists in S3
    s3cmd ls "s3://$S3_BUCKET/$SRV_FOLDER/$S3_PREFIX/$DB_NAME/$backup_file" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_message "ERROR: File not found in S3: s3://$S3_BUCKET/$SRV_FOLDER/$S3_PREFIX/$DB_NAME/$backup_file"
        return 1
    fi
    
    # Download file
    s3cmd get "s3://$S3_BUCKET/$SRV_FOLDER/$S3_PREFIX/$DB_NAME/$backup_file" "$local_file"
    
    if [ $? -eq 0 ]; then
        local file_size=$(du -h "$local_file" | cut -f1)
        log_message "Backup downloaded successfully. Size: $file_size"
        
        # Check integrity of downloaded file
        if [ ! -s "$local_file" ]; then
            log_message "ERROR: Downloaded file is empty"
            return 1
        fi
        
        return 0
    else
        log_message "ERROR: Error downloading file from S3"
        return 1
    fi
}

# Function to detect backup type
detect_backup_type() {
    local backup_file="$1"
    
    if [[ "$backup_file" == *.enc ]]; then
        echo "encrypted"
    elif [[ "$backup_file" == *.gz ]]; then
        echo "compressed"
    elif [[ "$backup_file" == *.sql ]]; then
        echo "plain"
    else
        echo "unknown"
    fi
}

# Function to restore database
restore_database() {
    local backup_file="$1"
    local db_name="$2"
    local local_file="$TEMP_DIR/$backup_file"
    local backup_type=$(detect_backup_type "$backup_file")
    
    log_message "Starting database restore: $db_name"
    log_message "Backup type: $backup_type"
    
    case "$backup_type" in
        "encrypted")
            if [ -z "$ENCRYPTION_KEY" ]; then
                echo -n "Enter encryption key: "
                read -s ENCRYPTION_KEY
                echo
            fi
            
            log_message "Decrypting and restoring encrypted backup..."
            openssl enc -aes-256-cbc -d -salt -k "$ENCRYPTION_KEY" -in "$local_file" | \
            gunzip | \
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p "$db_name"
            ;;
            
        "compressed")
            log_message "Restoring compressed backup..."
            gunzip < "$local_file" | mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p "$db_name"
            ;;
            
        "plain")
            log_message "Restoring plain SQL backup..."
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p "$db_name" < "$local_file"
            ;;
            
        *)
            log_message "ERROR: Unknown backup type: $backup_file"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_message "SUCCESS: Database restored successfully"
        return 0
    else
        log_message "ERROR: Error restoring database"
        return 1
    fi
}

# Action confirmation function
confirm_action() {
    local message="$1"
    
    if [ "$FORCE_RESTORE" = "true" ]; then
        return 0
    fi
    
    echo "$message"
    echo -n "Continue? (y/N): "
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Cleanup temporary files function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        log_message "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

# Dependencies check function
check_dependencies() {
    local missing_deps=()
    
    # Check s3cmd
    if ! command -v s3cmd >/dev/null 2>&1; then
        missing_deps+=("s3cmd")
    fi
    
    # Check mysql
    if ! command -v mysql >/dev/null 2>&1; then
        missing_deps+=("mysql-client")
    fi
    
    # Check openssl (for encrypted backups)
    if ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi
    
    # Check bc (for size calculations)
    if ! command -v bc >/dev/null 2>&1; then
        missing_deps+=("bc")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "ERROR: Missing required dependencies:"
        printf '  %s\n' "${missing_deps[@]}"
        echo ""
        echo "Install them:"
        echo "Ubuntu/Debian: sudo apt install s3cmd mysql-client openssl bc"
        echo "CentOS/RHEL: sudo yum install s3cmd mysql openssl bc"
        exit 1
    fi
}

# Main function
main() {
    local backup_file=""
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_backups
                exit 0
                ;;
            -d|--database)
                DB_NAME="$2"
                shift 2
                ;;
            -u|--user)
                DB_USER="$2"
                shift 2
                ;;
            -H|--host)
                DB_HOST="$2"
                shift 2
                ;;
            -p|--port)
                DB_PORT="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_RESTORE="true"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [ -z "$backup_file" ]; then
                    backup_file="$1"
                else
                    echo "Too many arguments"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check dependencies
    check_dependencies
    
    # If no backup file specified, show list
    if [ -z "$backup_file" ]; then
        echo "Backup file not specified."
        echo ""
        list_backups
        exit 1
    fi
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    trap cleanup EXIT
    
    log_message "Starting restore process for file: $backup_file"
    
    # Download backup from S3
    if ! download_backup "$backup_file"; then
        exit 1
    fi
    
    # If dry-run, only check file
    if [ "$dry_run" = true ]; then
        log_message "DRY RUN: File downloaded and checked successfully"
        local backup_type=$(detect_backup_type "$backup_file")
        log_message "Backup type: $backup_type"
        
        # Try to determine data size
        case "$backup_type" in
            "compressed"|"encrypted")
                echo "Preliminary check of compressed/encrypted file..."
                ;;
            "plain")
                local sql_size=$(wc -l < "$TEMP_DIR/$backup_file")
                echo "SQL file contains $sql_size lines"
                ;;
        esac
        
        exit 0
    fi
    
    # Check database connection
    if ! check_database_connection; then
        exit 1
    fi
    
    # Check database existence
    if check_database_exists "$DB_NAME"; then
        if ! confirm_action "WARNING: Database '$DB_NAME' exists and will be overwritten!"; then
            log_message "Operation cancelled by user"
            exit 0
        fi
    else
        log_message "Database '$DB_NAME' does not exist and will be created"
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
    fi
    
    # Restore database
    if restore_database "$backup_file" "$DB_NAME"; then
        log_message "Restore completed successfully"
        
        # Check restored data
        local table_count=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" 2>/dev/null)
        if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
            log_message "Restored tables: $table_count"
        fi
        
        exit 0
    else
        log_message "Restore completed with errors"
        exit 1
    fi
}

# Run main function
main "$@"