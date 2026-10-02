#!/usr/bin/env bash

set -e

# Colores para salida en consola
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}    Iniciando Setup del Entorno Fixia (DevOps)${NC}"
echo -e "${BLUE}====================================================${NC}"

# Si se ejecuta desde dentro de ms-orchestrator, subir un nivel al workspace raíz
CURRENT_DIR=$(basename "$PWD")

if [ "$CURRENT_DIR" = "ms-orchestrator" ]; then
    echo -e "${GREEN}Ejecutando dentro de ms-orchestrator. Cambiando al directorio raíz del workspace...${NC}"
    cd ..
fi

# Matriz de repositorios: "URL|STACK"
REPOS=(
    "https://github.com/Grupo-Fixia/ms-orchestrator.git|orchestrator"
    "https://github.com/Grupo-Fixia/ms-matching-geo.git|python"
    "https://github.com/Grupo-Fixia/md-intake-lakehouse.git|go"
    "https://github.com/Grupo-Fixia/ms-users.git|java"
    "https://github.com/Grupo-Fixia/ms-payments.git|java"
    "https://github.com/Grupo-Fixia/ms-apigateway.git|gateway"
    "https://github.com/Grupo-Fixia/ms-frontend.git|flutter"
)

# -----------------------------------------------------------------
# 1. CLONACIÓN Y ESTRUCTURACIÓN DE REPOSITORIOS
# -----------------------------------------------------------------

for ENTRY in "${REPOS[@]}"; do
    URL="${ENTRY%%|*}"
    STACK="${ENTRY##*|}"
    REPO_NAME=$(basename "$URL" .git)

    echo -e "\n${BLUE}---> Procesando repositorio: ${REPO_NAME} (${STACK})${NC}"

    if [ -d "$REPO_NAME" ]; then
        echo -e "${GREEN}El directorio ${REPO_NAME} ya existe. Omitiendo clone...${NC}"
    else
        git clone "$URL"
    fi

    case "$STACK" in

        java)
            mkdir -p \
                "${REPO_NAME}/src/main/java" \
                "${REPO_NAME}/src/main/resources" \
                "${REPO_NAME}/src/test/java"

            if [ ! -f "${REPO_NAME}/Dockerfile" ]; then
                cat << 'EOF' > "${REPO_NAME}/Dockerfile"
FROM eclipse-temurin:21-jdk-alpine AS build

WORKDIR /app

COPY . .

RUN ./gradlew bootJar --no-daemon || mvn clean package -DskipTests

FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

COPY --from=build /app/build/libs/*.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
EOF
            fi
            ;;

        python)
            mkdir -p \
                "${REPO_NAME}/src/app" \
                "${REPO_NAME}/src/tests"

            if [ ! -f "${REPO_NAME}/Dockerfile" ]; then
                cat << 'EOF' > "${REPO_NAME}/Dockerfile"
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src

EXPOSE 8000

CMD ["python", "src/app/main.py"]
EOF
            fi

            touch "${REPO_NAME}/requirements.txt"

            if [ ! -f "${REPO_NAME}/src/app/main.py" ]; then
                echo 'print("Servicio Geo iniciado")' > "${REPO_NAME}/src/app/main.py"
            fi
            ;;

        go)
            mkdir -p \
                "${REPO_NAME}/cmd/server" \
                "${REPO_NAME}/internal" \
                "${REPO_NAME}/pkg"

            if [ ! -f "${REPO_NAME}/Dockerfile" ]; then
                cat << 'EOF' > "${REPO_NAME}/Dockerfile"
FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY . .

RUN go build -o main ./cmd/server

FROM alpine:latest

WORKDIR /app

COPY --from=builder /app/main .

EXPOSE 8080

CMD ["./main"]
EOF
            fi

            if [ ! -f "${REPO_NAME}/cmd/server/main.go" ]; then
                echo -e 'package main\n\nfunc main() {\n\tprintln("Lakehouse Intake en marcha")\n}' \
                    > "${REPO_NAME}/cmd/server/main.go"
            fi
            ;;

        flutter)
            mkdir -p \
                "${REPO_NAME}/lib" \
                "${REPO_NAME}/web"

            if [ ! -f "${REPO_NAME}/Dockerfile" ]; then
                cat << 'EOF' > "${REPO_NAME}/Dockerfile"
FROM ghcr.io/cirrusci/flutter:3.22.0 AS build

WORKDIR /app

COPY . .

RUN flutter config --no-analytics

RUN flutter pub get

RUN flutter build web --release

FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF
            fi

            if [ ! -f "${REPO_NAME}/pubspec.yaml" ]; then
                cat << 'EOF' > "${REPO_NAME}/pubspec.yaml"
name: ms_frontend
description: App Frontend para la plataforma Fixia
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
EOF
            fi

            if [ ! -f "${REPO_NAME}/lib/main.dart" ]; then
                cat << 'EOF' > "${REPO_NAME}/lib/main.dart"
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text('Fixia Platform Frontend'),
      ),
    ),
  ));
}
EOF
            fi
            ;;

        gateway)
            mkdir -p "${REPO_NAME}/config"
            ;;

        orchestrator)
            mkdir -p \
                "${REPO_NAME}/compose" \
                "${REPO_NAME}/config/traefik" \
                "${REPO_NAME}/config/prometheus"
            ;;

    esac

    if [ ! -f "${REPO_NAME}/.dockerignore" ]; then
        cat << 'EOF' > "${REPO_NAME}/.dockerignore"
.git
.gitignore
target/
build/
.idea/
.vscode/
.dart_tool/
*.log
EOF
    fi

done

# -----------------------------------------------------------------
# 2. GENERACIÓN DE ARCHIVOS DE ORQUESTACIÓN EN ms-orchestrator
# -----------------------------------------------------------------

echo -e "\n${BLUE}---> Configurando Docker Compose e Infraestructura en ms-orchestrator...${NC}"

ORCH_DIR="ms-orchestrator"

cat << 'EOF' > "${ORCH_DIR}/config/traefik/traefik.yml"
api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"

providers:
  docker:
    exposedByDefault: false
EOF

cat << 'EOF' > "${ORCH_DIR}/docker-compose.yml"
version: '3.8'

networks:
  fixia-net:
    driver: bridge

volumes:
  postgres_users_data:
  postgres_payments_data:
  kafka_data:
  minio_data:

services:

  traefik:
    image: traefik:v3.0
    container_name: fixia-apigateway
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - fixia-net
    profiles: ["infra", "full"]

  postgres-users:
    image: postgres:16-alpine
    container_name: fixia-db-users
    environment:
      POSTGRES_DB: users_db
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres_users_data:/var/lib/postgresql/data
    networks:
      - fixia-net
    profiles: ["infra", "full"]

  postgres-payments:
    image: postgres:16-alpine
    container_name: fixia-db-payments
    environment:
      POSTGRES_DB: payments_db
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    ports:
      - "5433:5432"
    volumes:
      - postgres_payments_data:/var/lib/postgresql/data
    networks:
      - fixia-net
    profiles: ["infra", "full"]

  kafka:
    image: apache/kafka:latest
    container_name: fixia-kafka
    ports:
      - "9092:9092"
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@localhost:9093
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
    volumes:
      - kafka_data:/var/lib/kafka/data
    networks:
      - fixia-net
    profiles: ["infra", "full"]

  minio:
    image: minio/minio
    container_name: fixia-minio
    ports:
      - "9000:9000"
      - "9801:9801"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadminpassword
    command: server /data --console-address ":9801"
    volumes:
      - minio_data:/data
    networks:
      - fixia-net
    profiles: ["infra", "full"]

  ms-frontend:
    build:
      context: ../ms-frontend
      dockerfile: Dockerfile
    container_name: ms-frontend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ms-frontend.rule=PathPrefix(`/`)"
      - "traefik.http.routers.ms-frontend.priority=1"
      - "traefik.http.services.ms-frontend.loadbalancer.server.port=80"
    networks:
      - fixia-net
    profiles: ["services", "full"]

  ms-users:
    build:
      context: ../ms-users
      dockerfile: Dockerfile
    container_name: ms-users
    environment:
      - SPRING_DATASOURCE_URL=jdbc:postgresql://postgres-users:5432/users_db
      - SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ms-users.rule=PathPrefix(`/api/users`)"
      - "traefik.http.services.ms-users.loadbalancer.server.port=8080"
    depends_on:
      - postgres-users
      - kafka
    networks:
      - fixia-net
    profiles: ["services", "full"]

  ms-payments:
    build:
      context: ../ms-payments
      dockerfile: Dockerfile
    container_name: ms-payments
    environment:
      - SPRING_DATASOURCE_URL=jdbc:postgresql://postgres-payments:5432/payments_db
      - SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ms-payments.rule=PathPrefix(`/api/payments`)"
      - "traefik.http.services.ms-payments.loadbalancer.server.port=8080"
    depends_on:
      - postgres-payments
      - kafka
    networks:
      - fixia-net
    profiles: ["services", "full"]

  ms-matching-geo:
    build:
      context: ../ms-matching-geo
      dockerfile: Dockerfile
    container_name: ms-matching-geo
    environment:
      - KAFKA_HOST=kafka:9092
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ms-matching-geo.rule=PathPrefix(`/api/geo`)"
      - "traefik.http.services.ms-matching-geo.loadbalancer.server.port=8000"
    depends_on:
      - kafka
    networks:
      - fixia-net
    profiles: ["services", "full"]

  md-intake-lakehouse:
    build:
      context: ../md-intake-lakehouse
      dockerfile: Dockerfile
    container_name: md-intake-lakehouse
    environment:
      - KAFKA_HOST=kafka:9092
      - MINIO_HOST=minio:9000
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.md-intake-lakehouse.rule=PathPrefix(`/api/intake`)"
      - "traefik.http.services.md-intake-lakehouse.loadbalancer.server.port=8080"
    depends_on:
      - kafka
      - minio
    networks:
      - fixia-net
    profiles: ["services", "full"]
EOF

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}    ¡Entorno y repositorios configurados con éxito!${NC}"
echo -e "${GREEN}====================================================${NC}"
```
