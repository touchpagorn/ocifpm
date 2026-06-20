#!/bin/sh
read -p "Please enter Database name: " db_name
echo ""
read -p "Please enter Database root Password: " root_password
echo ""
read -p "Please enter Database user Password: " user_password

# Configurable paths
SSL_DIR="./config/ssl"
KEY_FILE="$SSL_DIR/private.key"
CERT_FILE="$SSL_DIR/certificate.crt"
DAYS_VALID=365

# Create directory if it doesn't exist
mkdir -p "$SSL_DIR"

# Generate cert only if not already present
if [ -f "$KEY_FILE" ] && [ -f "$CERT_FILE" ]; then
    echo "[INFO] SSL certificate already exists. Skipping generation."
else
    echo "[INFO] Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -days "$DAYS_VALID" \
        -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=TH/ST=Chonburi/L=Na Kluea/O=Touchpagorn/OU=Dev/CN=localhost"
    echo "[INFO] Certificate generated at: $CERT_FILE"
fi

# Create secrets folder if not exists
mkdir -p ./config/secrets
# เขียนค่าลงไฟล์
printf "%s\n" "$root_password" > ./config/secrets/db_root_password.txt
printf "%s\n" "$user_password" > ./config/secrets/db_user_password.txt
printf "%s\n" "$db_name"       > ./config/secrets/db_name.txt

## check if docker-compose exist?
chmod 400 ./config/secrets/db_root_password.txt
chmod 400 ./config/secrets/db_user_password.txt
chmod 400 ./config/secrets/db_name.txt

#sed -i "s/MARIADB_ROOT_PASSWORD=.*/MARIADB_ROOT_PASSWORD=$mypassword/" docker-compose.yml
#sed -i "s/MARIADB_PASSWORD=.*/MARIADB_PASSWORD=$mypassword/" docker-compose.yml

# ตรวจสอบว่า Docker ติดตั้งอยู่หรือไม่
if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed."
  echo "Please install Docker first: https://docs.docker.com/engine/install/"
  exit 1
fi

# ตรวจสอบว่า docker compose เป็น version 2 ขึ้นไป
compose_version=$(
  docker compose version --short 2>/dev/null || \
  docker compose version 2>/dev/null | awk '{print $3}'
)

if [ -z "$compose_version" ]; then
  echo "docker compose (v2) is not available."
  echo "Follow this to install/enable it: https://docs.docker.com/compose/install/"
  exit 1
fi

compose_major=$(echo "$compose_version" | cut -d. -f1 | tr -cd '0-9')

if [ -z "$compose_major" ] || [ "$compose_major" -lt 2 ]; then
  echo "docker compose version 2 or higher is required (found: $compose_version)."
  echo "Please upgrade Docker / Docker Compose: https://docs.docker.com/compose/install/"
  exit 1
fi
echo "Download latest CodeIgniter v4.7.3..."
wget -O codeigniter.zip https://api.github.com/repos/codeigniter4/framework/zipball/v4.7.3
unzip -q codeigniter.zip
mv codeigniter4-framework-* html
rm codeigniter.zip

# Configure CodeIgniter .env file
if [ -f "html/env" ]; then
    echo "Configuring CodeIgniter .env file..."
    cp html/env html/.env
    sed -i 's/# CI_ENVIRONMENT = production/CI_ENVIRONMENT = development/' html/.env
    sed -i 's/# database.default.hostname = localhost/database.default.hostname = db/' html/.env
    sed -i "s|# database.default.database = ci4|database.default.database = $db_name|" html/.env
    sed -i "s|# database.default.username = root|database.default.username = $db_name|" html/.env
    sed -i "s|# database.default.password = |database.default.password = $user_password|" html/.env
    sed -i 's/# database.default.DBDriver = MySQLi/database.default.DBDriver = MySQLi/' html/.env
    echo "CodeIgniter .env configured successfully."
else
    echo "[WARNING] env template not found. Skipping auto-configuration."
fi

echo "Create a CodeIgniter service."
docker compose up -d

docker exec web sh -c "chown -R www-data:www-data /var/www/html"
docker exec web sh -c "chmod -R 775 /var/www/html/writable"

echo "done..."

echo "====================="
echo "CodeIgniter site: https://$(hostname -I | awk '{print $1}')"
echo "[Database info]"
echo "db:   $db_name"
echo "host: db"
echo "user: $db_name"
echo "pass: $user_password"
echo "====================="

echo "Remove install.sh script."
#rm -f ./install.sh
