#!/bin/bash

# Function to check if a package is installed
package_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

# Function to check if a PostgreSQL user exists
user_exists() {
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$1'" | grep -q 1
}

# Function to check if a PostgreSQL database exists
db_exists() {
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$1'" | grep -q 1
}

# Install PostgreSQL if it is not already installed
if ! package_installed postgresql; then
  sudo apt update
  sudo apt install -y postgresql
else
  echo "PostgreSQL is already installed."
fi

# Start PostgreSQL service and enable remote connections
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/12/main/postgresql.conf
sudo echo "host all all 0.0.0.0/0 md5" | sudo tee -a /etc/postgresql/12/main/pg_hba.conf
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Prompt for PostgreSQL user name if it doesn't exist
read -p "Enter PostgreSQL user name: " user
if [[ -z "$user" ]]; then
  echo "Error: PostgreSQL user name cannot be empty."
  exit 1
fi

if ! user_exists "$user"; then
  read -p "Enter PostgreSQL user password: " user_password
  sudo -u postgres psql -c "CREATE USER $user WITH PASSWORD '$user_password';"
else
  echo "PostgreSQL user '$user' already exists."
fi

# Prompt for new database name
read -p "Enter new PostgreSQL database name: " database_name
if [[ -z "$database_name" ]]; then
  echo "Error: Database name cannot be empty."
  exit 1
fi

if ! db_exists "$database_name"; then
  sudo -u postgres psql -c "CREATE DATABASE $database_name;"
fi

# Grant privileges on the existing database to the user
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $database_name TO $user;"

# Install pip3 if it is not already installed
if ! package_installed python3-pip; then
  sudo apt install -y python3-pip
else
  echo "pip3 is already installed."
fi

# Install AWS CLI if it is not already installed
if ! package_installed awscli; then
  sudo pip3 install --upgrade awscli
else
  echo "AWS CLI is already installed."
fi

# Configure AWS CLI with the provided credentials if they don't already exist
if ! aws configure get aws_access_key_id >/dev/null 2>&1; then
  read -p "Enter AWS Access Key ID: " aws_access_key
  if [[ -z "$aws_access_key" ]]; then
    echo "Error: AWS Access Key ID cannot be empty."
    exit 1
  fi

  read -p "Enter AWS Secret Access Key: " aws_secret_key
  if [[ -z "$aws_secret_key" ]]; then
    echo "Error: AWS Secret Access Key cannot be empty."
    exit 1
  fi

  read -p "Enter AWS Region: " aws_region
  if [[ -z "$aws_region" ]]; then
  echo "Error: AWS Region cannot be empty."
    exit 1
  fi

  aws configure set aws_access_key_id "$aws_access_key"
  aws configure set aws_secret_access_key "$aws_secret_key"
  aws configure set default.region "$aws_region"
else
  echo "AWS CLI credentials already exist."
fi

# Check if the cron job already exists
existing_cron=$(crontab -l | grep "pg_dump -U $user -d $database_name")
if [[ -z "$existing_cron" ]]; then
  # Prompt for S3 bucket name if the cron job doesn't exist
  read -p "Enter the S3 bucket name: " bucket_name
  if [[ -z "$bucket_name" ]]; then
    echo "Error: S3 bucket name cannot be empty."
    exit 1
  fi

  # Schedule daily backup to S3 using cron
  echo "0 0 * * * pg_dump -U $user -d $database_name -f /tmp/backup.sql && aws s3 cp /tmp/backup.sql s3://$bucket_name/\$(date +\%Y-\%m-\%d-\%H-\%M-\%S)_backup.sql && rm /tmp/backup.sql" | crontab -
  echo "Scheduled daily backup to S3 using cron."
else
  echo "Cron job already exists for daily backup."
fi

# Open the PostgreSQL default port (5432)
sudo ufw allow 5432

echo "PostgreSQL setup complete!"
