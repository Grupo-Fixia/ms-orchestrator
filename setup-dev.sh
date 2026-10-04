#!/usr/bin/env bash

set -e

# Colores para salida en consola
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}    Iniciando Setup del Entorno Local para Devs${NC}"
echo -e "${BLUE}====================================================${NC}"

# Si se ejecuta desde dentro de ms-orchestrator, subir un nivel al workspace raíz
CURRENT_DIR=$(basename "$PWD")
if [ "$CURRENT_DIR" = "ms-orchestrator" ]; then
    echo -e "${GREEN}Cambiando al directorio raíz del workspace...${NC}"
    cd ..
fi

# 1. Clonación de repositorios si no existen
REPOS=(
    "https://github.com/Grupo-Fixia/ms-orchestrator.git"
    "https://github.com/Grupo-Fixia/ms-matching-geo.git"
    "https://github.com/Grupo-Fixia/md-intake-lakehouse.git"
    "https://github.com/Grupo-Fixia/ms-users.git"
    "https://github.com/Grupo-Fixia/ms-payments.git"
    "https://github.com/Grupo-Fixia/ms-apigateway.git"
    "https://github.com/Grupo-Fixia/ms-frontend.git"
    "https://github.com/Grupo-Fixia/ms-services.git"
)

echo -e "\n${BLUE}---> 1. Verificando y clonando repositorios...${NC}"
for URL in "${REPOS[@]}"; do
    REPO_NAME=$(basename "$URL" .git)
    if [ -d "$REPO_NAME" ]; then
        echo -e "${GREEN}El directorio ${REPO_NAME} ya existe. Omitiendo clonación.${NC}"
    else
        echo -e "${BLUE}Clonando ${REPO_NAME}...${NC}"
        git clone "$URL"
    fi
done

# 2. Generación del archivo .env en ms-orchestrator
echo -e "\n${BLUE}---> 2. Generando archivo .env en ms-orchestrator...${NC}"
ENV_FILE="ms-orchestrator/.env"

if [ -f "$ENV_FILE" ]; then
    echo -e "${GREEN}El archivo .env ya existe. Omitiendo creación.${NC}"
else
    cat << 'EOF' > "$ENV_FILE"
# Configuración del entorno de desarrollo generada por setup-dev.sh

POSTGRES_USER=user
POSTGRES_PASSWORD=password
POSTGRES_DB=users_db

MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadminpassword

SPRING_PROFILES_ACTIVE=dev
EOF
    echo -e "${GREEN}Archivo .env generado correctamente en ms-orchestrator.${NC}"
fi

# 3. Levantar los microservicios
echo -e "\n${BLUE}---> 3. Levantando los microservicios...${NC}"
cd ms-orchestrator || exit 1

# Se levantan todos los perfiles de servicios e infraestructura 
if command -v docker compose &> /dev/null; then
    docker compose --profile full up -d --build
elif command -v docker-compose &> /dev/null; then
    docker-compose --profile full up -d --build
else
    echo -e "${RED}ERROR: Docker Compose no está instalado.${NC}"
    exit 1
fi

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}    ¡Entorno configurado y ejecutándose con éxito!${NC}"
echo -e "${GREEN}====================================================${NC}"
