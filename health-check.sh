#!/bin/bash

# Diretório do projeto
PROJECT_DIR="/root/ERP/projeto_novo"
LOG_FILE="/var/log/photostudio-erp-health.log"
MAX_RETRIES=3
RETRY_DELAY=10

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

cd $PROJECT_DIR || {
    log "ERRO: Não foi possível acessar o diretório $PROJECT_DIR"
    exit 1
}

# Função para verificar se um container está rodando
check_container() {
    local container_name=$1
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if ! docker ps | grep -q "$container_name"; then
            log "AVISO: Container $container_name não está rodando. Tentativa $((retries + 1))/$MAX_RETRIES"
            docker-compose up -d "$container_name"
            sleep $RETRY_DELAY
            retries=$((retries + 1))
        else
            log "INFO: Container $container_name está rodando"
            return 0
        fi
    done
    
    log "ERRO: Container $container_name falhou após $MAX_RETRIES tentativas"
    return 1
}

# Função para verificar a saúde de um serviço
check_health() {
    local service=$1
    local url=$2
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if curl -s -f "$url" > /dev/null; then
            log "INFO: $service está respondendo em $url"
            return 0
        else
            log "AVISO: $service não está respondendo em $url. Tentativa $((retries + 1))/$MAX_RETRIES"
            docker-compose restart "$service"
            sleep $RETRY_DELAY
            retries=$((retries + 1))
        fi
    done
    
    log "ERRO: $service falhou após $MAX_RETRIES tentativas"
    return 1
}

# Verifica se o Docker está rodando
if ! systemctl is-active --quiet docker; then
    log "ERRO: Docker não está rodando. Tentando reiniciar..."
    systemctl restart docker
    sleep 10
fi

# Verifica cada container
check_container "projeto_novo_db_1"
check_container "projeto_novo_backend_1"
check_container "projeto_novo_frontend_1"

# Verifica a saúde dos serviços
check_health "backend" "http://localhost:3001/api/health"
check_health "frontend" "http://localhost:3000"

# Verifica o uso de memória e CPU dos containers
log "INFO: Status dos containers:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | tee -a "$LOG_FILE"

log "Verificação de saúde concluída" 