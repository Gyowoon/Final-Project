#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# setup_bastion.sh
#
# This script simplifies the manual steps you previously performed on the bastion
# host by automating the creation of the shopping mall database and user in
# Amazon RDS, and by creating (or updating) the Kubernetes secret used by the
# application.  It relies on the MySQL client and kubectl being available on
# the bastion host.  You can install the MySQL client via your package
# manager; for example, on Amazon Linux 2023: `sudo yum install -y mysql`.
#
# Usage:
#   bash setup_bastion.sh
#
# The script expects the following environment variables to be set.  You can
# export them before running the script or modify the defaults below:
#   DB_MASTER_USER  - master user for RDS (default: admin)
#   DB_MASTER_PASS  - master password for RDS
#   SHOPUSER_PASS   - password for the application database user (shopuser)
#   DB_NAME         - name of the application database (default: shopdb)
#   JWT_SECRET      - JWT secret for the application (default: abcdefg)
#
# The script uses `terraform output` to retrieve the RDS and Redis endpoints.
# Make sure you run `terraform apply` beforehand so that outputs are available.
# -----------------------------------------------------------------------------

set -euo pipefail

# Load outputs from Terraform
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint)

# Default configuration
DB_MASTER_USER="${DB_MASTER_USER:-${TF_VAR_db_master_username:-admin}}"
DB_MASTER_PASS="${DB_MASTER_PASS:-${TF_VAR_db_master_password:-}}"
SHOPUSER_PASS="${SHOPUSER_PASS:-StrongPassword123!}"
DB_NAME="${DB_NAME:-${TF_VAR_db_name:-shopdb}}"
JWT_SECRET="${JWT_SECRET:-abcdefg}"

if [[ -z "${DB_MASTER_PASS}" ]]; then
  echo "Error: DB_MASTER_PASS (or TF_VAR_db_master_password) must be set to connect to RDS." >&2
  exit 1
fi

echo "[*] Creating database \"$DB_NAME\" and user \"shopuser\" in RDS instance $RDS_ENDPOINT ..."

mysql -h "$RDS_ENDPOINT" -u "$DB_MASTER_USER" -p"$DB_MASTER_PASS" <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'shopuser'@'%' IDENTIFIED BY '$SHOPUSER_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'shopuser'@'%';
FLUSH PRIVILEGES;
SQL

echo "[+] Database and user created successfully.\n"

echo "[*] Creating or updating Kubernetes secret \"shop-secrets\" in namespace \"shop\"..."

kubectl create namespace shop --dry-run=client -o yaml | kubectl apply -f - || true

kubectl create secret generic shop-secrets \
  --namespace shop \
  --from-literal=DB_URI="mysql+pymysql://shopuser:$SHOPUSER_PASS@$RDS_ENDPOINT:3306/$DB_NAME" \
  --from-literal=REDIS_URL="redis://$REDIS_ENDPOINT:6379/0" \
  --from-literal=JWT_SECRET_KEY="$JWT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[+] Kubernetes secret created/updated successfully."

echo "[*] Setup complete."