#!/bin/bash

set -euo pipefail

# ---------- CONFIG DEFAULTS ----------
MONGO_VERSION="7.0"
ROOT_USERNAME="root"
ROOT_PASSWORD=""
MONGO_PORT=27017
REPO_UBUNTU_CODENAME="jammy"
# --------------------------------------

log() {
  echo -e "[\e[32mINFO\e[0m] $1"
}

error_exit() {
  echo -e "[\e[31mERROR\e[0m] $1" >&2
  exit 1
}

trap 'error_exit "Something went wrong. Exiting."' ERR

# --- Parse CLI args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-user)
      ROOT_USERNAME="$2"
      shift 2
      ;;
    --admin-pass)
      ROOT_PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# --- Prompt for password if not provided ---
if [[ -z "$ROOT_PASSWORD" ]]; then
  read -srp "🔑 Admin password: " ROOT_PASSWORD
  echo
fi

# --- Install MongoDB and Dependencies ---
log "🧹 Cleaning up MongoDB repo if exists..."
rm -f /etc/apt/sources.list.d/mongodb-org-*.list || true

log "📦 Installing prerequisites..."
apt-get update -y
apt-get install -y gnupg curl ca-certificates

log "🔐 Importing MongoDB GPG key..."
curl -fsSL https://pgp.mongodb.com/server-${MONGO_VERSION}.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server.gpg

log "📁 Adding MongoDB repo..."
echo "deb [signed-by=/usr/share/keyrings/mongodb-server.gpg] https://repo.mongodb.org/apt/ubuntu ${REPO_UBUNTU_CODENAME}/mongodb-org/${MONGO_VERSION} multiverse" \
  | tee /etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list

log "🔄 Updating package index..."
apt-get update -y

log "⬇️ Installing MongoDB..."
apt-get install -y mongodb-org

MONGOSH_BIN=$(command -v mongosh || echo "/usr/bin/mongosh")

log "🚀 Starting mongod..."
systemctl enable mongod
systemctl start mongod
sleep 5

# --- Try to create admin user if not exists ---
log "👤 Attempting to create admin user '${ROOT_USERNAME}'..."
"${MONGOSH_BIN}" admin --quiet --eval "
try {
  db.createUser({user: '${ROOT_USERNAME}', pwd: '${ROOT_PASSWORD}', roles: [{role: 'root', db: 'admin'}]});
  print('✅ Admin user created.');
} catch (e) {
  if (e.code === 11000 || e.codeName === 'DuplicateKey') {
    print('ℹ️ Admin user already exists.');
  } else {
    print('⚠️ Error creating admin user:', e);
  }
}
"

log "🔐 Enabling authentication in mongod.conf..."
sed -i '/#security:/a\security:\n  authorization: "enabled"' /etc/mongod.conf
sed -i 's/^\s*bindIp: .*/  bindIp: 0.0.0.0/' /etc/mongod.conf

log "♻️ Restarting mongod with auth..."
systemctl restart mongod
sleep 3

# --- Configure firewall ---
log "🛡️ Checking firewall configuration to allow remote access on port ${MONGO_PORT}..."

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  log "ufw detected. Allowing port ${MONGO_PORT}..."
  sudo ufw allow ${MONGO_PORT}/tcp
elif command -v iptables >/dev/null 2>&1; then
  log "iptables detected. Adding rule to allow port ${MONGO_PORT}..."
  sudo iptables -C INPUT -p tcp --dport ${MONGO_PORT} -j ACCEPT 2>/dev/null || sudo iptables -A INPUT -p tcp --dport ${MONGO_PORT} -j ACCEPT
else
  log "No known firewall tool detected or firewall inactive. Skipping port configuration."
fi

# --- Print connection string ---
PUBLIC_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
CONN_STR="mongodb://${ROOT_USERNAME}:${ROOT_PASSWORD}@${PUBLIC_IP}:${MONGO_PORT}/admin?authSource=admin"

log "✅ MongoDB ${MONGO_VERSION} instalado y configurado correctamente."
log "🔗 String de conexión listo para usar:"
echo -e "\n\e[36m$CONN_STR\e[0m\n"
