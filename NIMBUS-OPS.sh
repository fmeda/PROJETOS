#!/bin/bash

# ░█▀▄░█▀█░█▀▄░█▀▀░█▀▀░▀█▀░█▀█░█▀▀
# ░█░█░█░█░█░█░█░█░█░█░░█░░█░█░▀▀█
# ░▀▀░░▀▀▀░▀▀░░▀▀▀░▀▀▀░░▀░░▀░▀░▀▀▀

# Central Monitoring Setup for Hybrid Environment (Cloud + On-Prem)
# Author: Fabiano Aparecido
# Version: 2.5 (CMNI 5/5 ready)
# Requirements: Rocky Linux 9 / AlmaLinux 9

set -euo pipefail
trap 'echo "[!] Erro na linha $LINENO. Abortando." | tee -a "$LOGFILE"' ERR

### VARIÁVEIS GLOBAIS
INSTALL_DIR="/opt/hybrid-monitoring"
CONFIG_FILE="$INSTALL_DIR/config.env"
LOGFILE="$INSTALL_DIR/logs/install_$(date +%Y%m%d_%H%M%S).log"
ROLLBACK_FILE="$INSTALL_DIR/logs/rollback_$(date +%Y%m%d_%H%M%S).log"
AUDIT_LOG="$INSTALL_DIR/logs/audit_$(date +%Y%m%d_%H%M%S).json"
mkdir -p "$INSTALL_DIR/logs"
chmod 700 "$INSTALL_DIR/logs"

### FUNÇÕES DE UTILIDADE
function log() {
  echo -e "[$(date '+%F %T')] $1" | tee -a "$LOGFILE"
  echo "{\"timestamp\": \"$(date '+%F %T')\", \"event\": \"$1\"}" >> "$AUDIT_LOG"
}

function rollback() {
  log "Executando rollback parcial do ambiente..."
  systemctl stop graylog-server || true
  systemctl stop opensearch || true
  systemctl stop mongod || true
  systemctl stop grafana-server || true
  systemctl stop zabbix-server || true
  systemctl stop zabbix-agent || true
  dnf remove -y graylog-server opensearch mongodb* grafana zabbix* || true
  rm -rf /etc/zabbix /etc/grafana /etc/graylog /etc/opensearch /etc/mongod* /var/lib/zabbix /var/lib/grafana /var/lib/graylog
  log "Rollback concluído."
}

function check_prereqs() {
  if [[ $EUID -ne 0 ]]; then
    echo "Este script deve ser executado como root."; exit 1
  fi
  if ! grep -qE "Rocky|AlmaLinux" /etc/os-release; then
    echo "Distribuição incompatível. Use Rocky Linux ou AlmaLinux."; exit 1
  fi
  if ! ping -c 1 8.8.8.8 &>/dev/null; then
    echo "Sem acesso à internet. Verifique a conexão."; exit 1
  fi
  command -v openssl &>/dev/null || { echo "openssl não encontrado. Instalando..."; dnf install -y openssl; }
  command -v pwgen &>/dev/null || dnf install -y pwgen
  command -v curl &>/dev/null || dnf install -y curl
}

function first_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[+] Configuração inicial do ambiente"
    read -p "Hostname da instância: " HOSTNAME
    read -p "Diretório de instalação [/opt/hybrid-monitoring]: " INSTALL_CUSTOM
    INSTALL_DIR="${INSTALL_CUSTOM:-$INSTALL_DIR}"
    read -s -p "Senha para Graylog admin: " GRAYLOG_ADMIN_PASS
    echo
    GRAFANA_PORT=3000
    GRAYLOG_PORT=9000
    SYSLOG_PORT=514
    cat <<EOF > "$CONFIG_FILE"
HOSTNAME=$HOSTNAME
INSTALL_DIR=$INSTALL_DIR
GRAFANA_PORT=$GRAFANA_PORT
GRAYLOG_PORT=$GRAYLOG_PORT
SYSLOG_PORT=$SYSLOG_PORT
GRAYLOG_ADMIN_PASS="$GRAYLOG_ADMIN_PASS"
EOF
    chmod 600 "$CONFIG_FILE"
  fi
  source "$CONFIG_FILE"
}

function send_logs_to_siemplify() {
  SIEM_ENDPOINT="https://your-siem-endpoint.example/api/logs"
  [[ -f "$AUDIT_LOG" ]] && curl -X POST -H "Content-Type: application/json" --data-binary "@$AUDIT_LOG" "$SIEM_ENDPOINT" || log "Arquivo de auditoria não encontrado."
}

### FUNÇÕES DE INSTALAÇÃO
function install_zabbix() {
  log "Instalando Zabbix Server e Agent"
  dnf install -y https://repo.zabbix.com/zabbix/6.5/rhel/9/x86_64/zabbix-release-6.5-1.el9.noarch.rpm
  dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-agent mariadb-server
  systemctl enable --now mariadb
  ZBX_DB_PASS=$(openssl rand -base64 16)
  mysql -e "CREATE DATABASE zabbix character set utf8mb4 collate utf8mb4_bin;"
  mysql -e "CREATE USER zabbix@localhost IDENTIFIED BY '$ZBX_DB_PASS';"
  mysql -e "GRANT ALL PRIVILEGES ON zabbix.* TO zabbix@localhost;"
  zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -uzabbix -p"$ZBX_DB_PASS" zabbix
  sed -i "s/# DBPassword=/DBPassword=$ZBX_DB_PASS/" /etc/zabbix/zabbix_server.conf
  systemctl enable --now zabbix-server zabbix-agent httpd php-fpm
  firewall-cmd --add-service={http,https} --permanent
  firewall-cmd --reload
  log "Zabbix instalado com sucesso"
}

function install_grafana() {
  log "Instalando Grafana"
  dnf install -y https://dl.grafana.com/oss/release/grafana-10.4.2-1.x86_64.rpm
  systemctl enable --now grafana-server
  firewall-cmd --add-port=${GRAFANA_PORT}/tcp --permanent
  firewall-cmd --reload
  log "Grafana disponível em http://$HOSTNAME:$GRAFANA_PORT"
}

function install_graylog() {
  log "Instalando Graylog + OpenSearch + MongoDB"
  dnf install -y java-17-openjdk wget pwgen mongodb mongodb-server
  systemctl enable --now mongod
  cat <<EOF | tee /etc/yum.repos.d/opensearch.repo
[opensearch]
name=OpenSearch repo
baseurl=https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.rpm
enabled=1
gpgcheck=1
EOF
  dnf install -y opensearch
  echo "plugins.security.disabled: true" >> /etc/opensearch/opensearch.yml
  systemctl enable --now opensearch
  rpm -Uvh https://packages.graylog2.org/repo/packages/graylog-5.2-repository_latest.rpm
  dnf install -y graylog-server
  PASSWORD_SECRET=$(pwgen -N 1 -s 96)
  HASHED_PASS=$(echo -n "$GRAYLOG_ADMIN_PASS" | sha256sum | awk '{print $1}')
  sed -i "s/password_secret =/password_secret = $PASSWORD_SECRET/" /etc/graylog/server/server.conf
  sed -i "s/root_password_sha2 =/root_password_sha2 = $HASHED_PASS/" /etc/graylog/server/server.conf
  systemctl enable --now graylog-server
  firewall-cmd --add-port=${GRAYLOG_PORT}/tcp --permanent
  firewall-cmd --reload
  log "Graylog instalado em http://$HOSTNAME:$GRAYLOG_PORT"
}

function configure_pfsense() {
  log "Configuração para integração pfSense"
  echo "Configure o pfSense para enviar logs via syslog para $HOSTNAME porta $SYSLOG_PORT/UDP."
  echo "Crie um Input no Graylog do tipo Syslog/UDP usando essa porta."
}

### MENU PROFISSIONAL
function show_menu() {
  while true; do
    clear
    echo "[ Hybrid Monitoring Installer - CLI Profissional ]"
    echo "[1] Instalar Zabbix"
    echo "[2] Instalar Grafana"
    echo "[3] Instalar Graylog"
    echo "[4] Configurar pfSense"
    echo "[5] Executar Rollback"
    echo "[6] Enviar logs para SIEM"
    echo "[7] Sair"
    read -p "Escolha: " opt
    case $opt in
      1) install_zabbix ;;
      2) install_grafana ;;
      3) install_graylog ;;
      4) configure_pfsense ;;
      5) rollback ;;
      6) send_logs_to_siemplify ;;
      7) exit 0 ;;
      *) echo "Opção inválida"; sleep 2 ;;
    esac
  done
}

### EXECUÇÃO INICIAL
check_prereqs
first_config
show_menu
