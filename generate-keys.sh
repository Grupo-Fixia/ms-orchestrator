#!/usr/bin/env bash

set -e

# Colores para salida en terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}  Generador de Claves y Variables de Entorno Fixia  ${NC}"
echo -e "${BLUE}====================================================${NC}"

# Ubicar el directorio ms-orchestrator
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# 1. Validación de dependencias
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}ERROR: 'openssl' es obligatorio para generar las claves criptográficas.${NC}"
    exit 1
fi

FORCE=false
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    FORCE=true
fi

# 2. Generación de claves criptográficas
echo -e "${BLUE}---> Generando par de claves RSA 2048 para JWT (RS256)...${NC}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$TEMP_DIR/private.pem" 2>/dev/null
openssl pkey -in "$TEMP_DIR/private.pem" -pubout -out "$TEMP_DIR/public.pem" 2>/dev/null

# Formatear a una sola línea con saltos de línea explícitos como \n
PRIV_ONE_LINE=$(awk 'NF{printf "%s\\n",$0}' "$TEMP_DIR/private.pem")
PUB_ONE_LINE=$(awk 'NF{printf "%s\\n",$0}' "$TEMP_DIR/public.pem")

# Generar clave interna aleatoria para interoperabilidad entre microservicios
INTERNAL_KEY=$(openssl rand -hex 24)

# 3. Creación o actualización del archivo .env
if [ -f "$ENV_FILE" ] && [ "$FORCE" = false ]; then
    echo -e "${YELLOW}El archivo .env ya existe en $ENV_FILE.${NC}"
    echo -e "${BLUE}Actualizando/inyectando claves sin alterar el resto de variables...${NC}"

    # Si ya existen claves JWT y no se forzó, avisar
    if grep -q '^JWT_PRIVATE_KEY=' "$ENV_FILE"; then
        echo -e "${GREEN}✓ JWT_PRIVATE_KEY y JWT_PUBLIC_KEY ya están presentes.${NC}"
    else
        echo -e "${BLUE}Inyectando claves JWT faltantes...${NC}"
        {
            printf '\n# Claves JWT de ms-users (RS256, desarrollo local)\n'
            printf 'JWT_PRIVATE_KEY="%s"\n' "$PRIV_ONE_LINE"
            printf 'JWT_PUBLIC_KEY="%s"\n' "$PUB_ONE_LINE"
        } >> "$ENV_FILE"
        echo -e "${GREEN}✓ Claves JWT añadidas a .env.${NC}"
    fi

    # Verificar INTERNAL_API_KEY
    if ! grep -q '^INTERNAL_API_KEY=' "$ENV_FILE"; then
        echo -e "${BLUE}Inyectando INTERNAL_API_KEY...${NC}"
        echo "INTERNAL_API_KEY=$INTERNAL_KEY" >> "$ENV_FILE"
        echo -e "${GREEN}✓ INTERNAL_API_KEY añadida a .env.${NC}"
    fi

    # Verificar RUSTFS_BUCKET_EVIDENCES (GC-456)
    if ! grep -q '^RUSTFS_BUCKET_EVIDENCES=' "$ENV_FILE"; then
        echo "RUSTFS_BUCKET_EVIDENCES=evidences" >> "$ENV_FILE"
        echo -e "${GREEN}✓ RUSTFS_BUCKET_EVIDENCES añadida a .env.${NC}"
    fi

    # Verificar SERVICES_DB_NAME
    if ! grep -q '^SERVICES_DB_NAME=' "$ENV_FILE"; then
        echo "SERVICES_DB_NAME=services_db" >> "$ENV_FILE"
        echo -e "${GREEN}✓ SERVICES_DB_NAME añadida a .env.${NC}"
    fi

else
    echo -e "${BLUE}Escribiendo nuevo archivo .env en $ENV_FILE...${NC}"
    cat << EOF > "$ENV_FILE"
# ====================================================
# Entorno de Desarrollo Local Fixia (ms-orchestrator)
# ====================================================

# Bases de datos PostgreSQL
POSTGRES_USER=user
POSTGRES_PASSWORD=password
USERS_DB_NAME=users_db
PAYMENTS_DB_NAME=payments_db
SERVICES_DB_NAME=services_db

# Almacenamiento de Objetos RustFS (S3 compatible - GC-456)
RUSTFS_ACCESS_KEY=rustfsadmin
RUSTFS_SECRET_KEY=rustfsadmin
RUSTFS_BUCKET=lakehouse
RUSTFS_BUCKET_EVIDENCES=evidences
RUSTFS_IMAGE=rustfs/rustfs:latest
RC_IMAGE=rustfs/rc:latest

# Clave interna para comunicación inter-microservicio (X-Internal-Api-Key)
INTERNAL_API_KEY=$INTERNAL_KEY

# Claves JWT (RS256)
JWT_PRIVATE_KEY="$PRIV_ONE_LINE"
JWT_PUBLIC_KEY="$PUB_ONE_LINE"
EOF
    echo -e "${GREEN}✓ Archivo .env generado exitosamente con todas las claves.${NC}"
fi

# Restringir permisos de lectura del archivo de secretos
chmod 600 "$ENV_FILE"
echo -e "${GREEN}✓ Permisos restringidos (chmod 600) para .env.${NC}"

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}  ¡Generación de claves completada correctamente!   ${NC}"
echo -e "${GREEN}====================================================${NC}"
