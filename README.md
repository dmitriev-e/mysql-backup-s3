# MySQL Backup and Restore Scripts for S3

A set of scripts for automated MySQL database backup and restore operations with Amazon S3 storage.

## Features

- **Centralized configuration** - all parameters stored in one file
- **Automated user creation** - bash script to create backup user with proper privileges
- **Backup to S3** with automatic compression
- **Restore from S3** with support for various formats
- **Encryption support** for additional security
- **Logging** of all operations
- **Integrity checking** of files

## File Structure

```
mysql-backup-s3/
├── mysql-backup-s3.sh       # Backup script
├── mysql-restore-s3.sh      # Restore script
├── create_backup_user.sh    # Script to create backup user
├── config.sh.example        # Configuration example
├── config.sh               # Your configuration (created by you)
└── README.md               # This file
```

## Quick Start

### 1. Configuration Setup

```bash
# Copy example configuration
cp config.sh.example config.sh

# Edit configuration
nano config.sh

# Set secure permissions
chmod 600 config.sh
```

### 2. Configure parameters in config.sh

Main parameters to change:

```bash
# Database
DB_NAME="your_database_name"          # Your DB name
DB_USER="backup_user"                 # User for backup
DB_PASSWORD="secure_password"         # User password
DB_ADMIN_USER="root"                  # Admin user for user creation

# S3 settings
S3_BUCKET="your-backup-bucket"        # S3 bucket name
SRV_FOLDER="your-server-name"         # Server/environment name
S3_PREFIX="mysql-backups/production"  # S3 path for restore
```

### 3. Create backup user

```bash
# Make the script executable
chmod +x create_backup_user.sh

# Run the script to create backup user
./create_backup_user.sh
```

The script will:
- Load configuration from config.sh
- Prompt for MySQL admin password
- Create the backup user with proper privileges
- Show granted privileges for verification

### 4. Configure s3cmd

```bash
# Configure s3cmd (if not already configured)
s3cmd --configure
```

## Usage

### Backup

```bash
# Make backup script executable
chmod +x mysql-backup-s3.sh

# Simple backup
./mysql-backup-s3.sh
```

The script automatically:
- Creates database dump
- Compresses it with gzip
- Uploads to S3 with timestamp
- Removes local temporary file

### Restore

```bash
# Make restore script executable
chmod +x mysql-restore-s3.sh

# Show available backups
./mysql-restore-s3.sh --list

# Restore specific backup
./mysql-restore-s3.sh your_database_backup_20231201_020000.sql.gz

# Restore to different database
./mysql-restore-s3.sh backup_file.sql.gz --database test_db

# Force restore without confirmation
./mysql-restore-s3.sh backup_file.sql.gz --force

# Only download and check file
./mysql-restore-s3.sh backup_file.sql.gz --dry-run
```

## Configuration Parameters

### Database
- `DB_NAME` - Database name
- `DB_USER` - MySQL user for backup
- `DB_PASSWORD` - User password
- `DB_RESTORE_USER` - User for restore (usually root)
- `DB_HOST` - MySQL host (default localhost)
- `DB_PORT` - MySQL port (default 3306)

### MySQL Administration
- `DB_ADMIN_USER` - Admin user for creating backup user (usually root)
- `BACKUP_USER_PRIVILEGES` - Privileges granted to backup user

### S3 settings
- `S3_BUCKET` - S3 bucket name
- `SRV_FOLDER` - Prefix for backup script
- `S3_PREFIX` - Prefix for restore script
- `STORAGE_CLASS` - S3 storage class

### Local settings
- `TEMP_DIR` - Temporary directory
- `LOG_FILE` - Log file for restore operations
- `ENCRYPTION_KEY` - Encryption key (optional)

### Backup options
- `MYSQLDUMP_OPTIONS` - Additional options for mysqldump

## Backup User Privileges

The backup user is created with the following privileges:
- **SELECT** - Read data from tables
- **LOCK TABLES** - Lock tables during backup for consistency
- **SHOW VIEW** - Access to view definitions
- **EVENT** - Access to scheduled events
- **TRIGGER** - Access to triggers
- **PROCESS** - See running processes for consistent backups

## Automation

### Setting up cron for automatic backups

```bash
# Edit crontab
crontab -e

# Daily backup at 2:00 AM
0 2 * * * /path/to/mysql-backup-s3.sh

# Weekly backup on Sundays at 3:00 AM
0 3 * * 0 /path/to/mysql-backup-s3.sh
```

## Security

1. **File permissions**: Set correct permissions on configuration file
   ```bash
   chmod 600 config.sh
   ```

2. **Database user**: The `create_backup_user.sh` script creates a separate user with minimal privileges

3. **Password security**: Admin passwords are not stored in configuration files

4. **S3 security**: Use IAM policies to restrict access to S3 bucket

5. **Encryption**: Consider encrypting backups for additional security

## Scripts Overview

### create_backup_user.sh
- Creates MySQL backup user with proper privileges
- Uses variables from config.sh
- Prompts for admin password securely
- Verifies user creation and shows granted privileges

### mysql-backup-s3.sh
- Creates compressed database dumps
- Uploads to S3 with timestamp
- Uses backup user credentials from config

### mysql-restore-s3.sh
- Lists available backups from S3
- Downloads and restores backups
- Supports multiple backup formats (plain, compressed, encrypted)
- Uses restore user credentials from config

## Troubleshooting

### Configuration errors
```bash
# Check configuration
source config.sh
```

### User creation issues
```bash
# Verify MySQL admin access
mysql -h $DB_HOST -P $DB_PORT -u $DB_ADMIN_USER -p

# Check if backup user exists
mysql -h $DB_HOST -P $DB_PORT -u $DB_ADMIN_USER -p -e "SELECT User FROM mysql.user WHERE User='$DB_USER';"
```

### MySQL connection issues
```bash
# Check backup user connection
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p

# Check restore user connection
mysql -h $DB_HOST -P $DB_PORT -u $DB_RESTORE_USER -p
```

### S3 issues
```bash
# Check S3 access
s3cmd ls s3://$S3_BUCKET/
```

## Requirements

- **MySQL Client** - for mysqldump and mysql commands
- **s3cmd** - for working with Amazon S3
- **gzip** - for backup compression
- **openssl** - for encryption (optional)
- **bc** - for file size calculations

## Installing Dependencies

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install mysql-client s3cmd gzip openssl bc
```

### CentOS/RHEL
```bash
sudo yum install mysql s3cmd gzip openssl bc
```

### macOS
```bash
brew install mysql-client s3cmd
```

## License

MIT License - use freely for any purpose.
