#!/bin/bash

# Script Linux com menu simples para sincronização e status de logs

SOURCE_DIR="/var/logs_centralizados/windows"
DEST_DIR="/var/logs_centralizados/central"
LOGFILE="/var/log/rsync_logs_sync.log"

install_rsync() {
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y rsync
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y rsync
    else
        echo "Gerenciador de pacotes não suportado. Instale rsync manualmente."
        exit 1
    fi
}

check_rsync() {
    if ! command -v rsync >/dev/null 2>&1; then
        echo "rsync não encontrado. Instalando..."
        install_rsync
    else
        echo "rsync encontrado."
    fi
}

show_menu() {
    clear
    echo "=== Sincronização de Logs Linux ==="
    echo "1) Iniciar sincronização de logs"
    echo "2) Visualizar último log de sincronização (últimas 20 linhas)"
    echo "0) Sair"
}

sync_logs() {
    chmod 750 "$DEST_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Iniciando sincronização de logs." >> "$LOGFILE"
    rsync -avz --checksum --delete --log-file="$LOGFILE" "$SOURCE_DIR/" "$DEST_DIR/"
    if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Sincronização concluída com sucesso." >> "$LOGFILE"
        echo "Sincronização concluída com sucesso."
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Erro durante sincronização." >> "$LOGFILE"
        echo "Erro durante sincronização."
    fi
    read -p "Pressione Enter para continuar..."
}

view_log() {
    if [ -f "$LOGFILE" ]; then
        tail -n 20 "$LOGFILE"
    else
        echo "Arquivo de log não encontrado."
    fi
    read -p "Pressione Enter para continuar..."
}

# Programa principal
check_rsync

while true; do
    show_menu
    read -p "Escolha uma opção: " opt
    case $opt in
        1) sync_logs ;;
        2) view_log ;;
        0) echo "Saindo..."; exit 0 ;;
        *) echo "Opção inválida." ; read -p "Pressione Enter para continuar...";;
    esac
done
