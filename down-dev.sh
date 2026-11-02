#!/usr/bin/env bash

set -e

# Colores para salida en consola
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}    Deteniendo y limpiando el Entorno Local${NC}"
echo -e "${BLUE}====================================================${NC}"

# Si se ejecuta desde el directorio padre, entrar a ms-orchestrator
if [ -f "ms-orchestrator/docker-compose.yml" ]; then
    cd ms-orchestrator
elif [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}ERROR: No se encontró docker-compose.yml. Ejecuta este script desde ms-orchestrator o la raíz del workspace.${NC}"
    exit 1
fi

echo -e "\n${BLUE}---> Bajando los microservicios e infraestructura...${NC}"

if command -v docker compose &> /dev/null; then
    docker compose --profile full down
elif command -v docker-compose &> /dev/null; then
    docker-compose --profile full down
else
    echo -e "${RED}ERROR: Docker Compose no está instalado.${NC}"
    exit 1
fi

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}    ¡Arquitectura detenida correctamente!${NC}"
echo -e "${GREEN}====================================================${NC}"
