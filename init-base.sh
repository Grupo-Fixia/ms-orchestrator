#!/usr/bin/env bash

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}  Inicializando Código Base (Sin MVC - Solo Build)${NC}"
echo -e "${BLUE}====================================================${NC}"

# ---------------------------------------------------------
# 0. VALIDACIONES BÁSICAS
# ---------------------------------------------------------

command -v docker >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: Docker no está instalado o no está en PATH.${NC}"
    exit 1
}

docker info >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: Docker está instalado pero el daemon no está disponible.${NC}"
    exit 1
}

# ---------------------------------------------------------
# 1. ASEGURAR QUE ESTAMOS EN LA RAÍZ DEL WORKSPACE
# ---------------------------------------------------------

CURRENT_DIR=$(basename "$PWD")

if [ "$CURRENT_DIR" = "ms-orchestrator" ]; then
    echo -e "${YELLOW}Ejecutando desde ms-orchestrator. Subiendo al workspace raíz...${NC}"
    cd ..
fi

WORKSPACE_ROOT="$PWD"

echo -e "${GREEN}Workspace: ${WORKSPACE_ROOT}${NC}"

# ---------------------------------------------------------
# 2. VALIDAR REPOSITORIOS ESPERADOS
# ---------------------------------------------------------

REQUIRED_DIRS=(
    "ms-users"
    "ms-payments"
    "ms-matching-geo"
    "md-intake-lakehouse"
    "ms-frontend"
)

for DIR in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$DIR" ]; then
        echo -e "${RED}ERROR: No existe el directorio requerido: ${DIR}${NC}"
        echo -e "${YELLOW}Clona/configura primero los repositorios.${NC}"
        exit 1
    fi
done

# ---------------------------------------------------------
# 3. JAVA (SPRING BOOT)
# ---------------------------------------------------------

for MS in ms-users ms-payments; do

    echo -e "\n${GREEN}Configurando ${MS} (Java 21 + JPA/PostgreSQL)...${NC}"

    mkdir -p \
        "$MS/src/main/java/com/fixia" \
        "$MS/src/main/resources"

    PACKAGE_NAME="${MS#ms-}"

    mkdir -p "$MS/src/main/java/com/fixia/$PACKAGE_NAME"

    # -----------------------------------------------------
    # pom.xml
    # -----------------------------------------------------

    cat <<EOF > "$MS/pom.xml"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         https://maven.apache.org/xsd/maven-4.0.0.xsd">

    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.5</version>
        <relativePath/>
    </parent>

    <groupId>com.fixia</groupId>
    <artifactId>${MS}</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>${MS}</name>
    <description>Microservicio ${MS} - Fixia</description>

    <properties>
        <java.version>21</java.version>
    </properties>

    <dependencies>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>

        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <scope>runtime</scope>
        </dependency>

    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>

</project>
EOF

    # -----------------------------------------------------
    # Application.java
    # -----------------------------------------------------

    cat <<EOF > "$MS/src/main/java/com/fixia/$PACKAGE_NAME/Application.java"
package com.fixia.$PACKAGE_NAME;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
        System.out.println(
            "Microservicio ${MS} iniciado correctamente."
        );
    }
}
EOF

    # -----------------------------------------------------
    # application.yml
    # -----------------------------------------------------

    cat <<EOF > "$MS/src/main/resources/application.yml"
server:
  port: 8080

spring:
  application:
    name: ${MS}

  datasource:
    url: \${SPRING_DATASOURCE_URL:jdbc:postgresql://localhost:5432/${MS}}
    username: \${SPRING_DATASOURCE_USERNAME:user}
    password: \${SPRING_DATASOURCE_PASSWORD:password}
    driver-class-name: org.postgresql.Driver

  jpa:
    hibernate:
      ddl-auto: update
    show-sql: false
EOF

    # -----------------------------------------------------
    # Dockerfile
    # -----------------------------------------------------

    cat <<'EOF' > "$MS/Dockerfile"
FROM maven:3.9.9-eclipse-temurin-21 AS build

WORKDIR /app

COPY pom.xml .

RUN mvn dependency:go-offline -B

COPY src ./src

RUN mvn clean package -DskipTests -B

FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

COPY --from=build /app/target/*.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
EOF

    echo -e "${GREEN}${MS}: archivos Java generados correctamente.${NC}"

done

# ---------------------------------------------------------
# 4. PYTHON (FASTAPI)
# ---------------------------------------------------------

echo -e "\n${GREEN}Configurando ms-matching-geo (FastAPI mínimo)...${NC}"

mkdir -p \
    ms-matching-geo/src/app \
    ms-matching-geo/src/tests

cat <<'EOF' > ms-matching-geo/requirements.txt
fastapi==0.111.0
uvicorn==0.29.0
EOF

cat <<'EOF' > ms-matching-geo/src/app/main.py
from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "Servicio ms-matching-geo inicializado correctamente."
    )
    yield
    logger.info(
        "Servicio ms-matching-geo detenido."
    )


app = FastAPI(
    title="Geo Matching Service",
    lifespan=lifespan,
)


@app.get("/health")
def health():
    return {
        "service": "ms-matching-geo",
        "status": "UP",
    }
EOF

cat <<'EOF' > ms-matching-geo/Dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src

EXPOSE 8000

CMD ["uvicorn", "src.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

echo -e "${GREEN}ms-matching-geo configurado correctamente.${NC}"

# ---------------------------------------------------------
# 5. GO - md-intake-lakehouse
# ---------------------------------------------------------

echo -e "\n${GREEN}Configurando md-intake-lakehouse (Go Server mínimo)...${NC}"

mkdir -p \
    md-intake-lakehouse/cmd/server \
    md-intake-lakehouse/internal \
    md-intake-lakehouse/pkg

cat <<'EOF' > md-intake-lakehouse/go.mod
module github.com/Grupo-Fixia/md-intake-lakehouse

go 1.22
EOF

cat <<'EOF' > md-intake-lakehouse/cmd/server/main.go
package main

import (
    "log"
    "net/http"
)

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusOK)
    _, _ = w.Write([]byte(`{"service":"md-intake-lakehouse","status":"UP"}`))
}

func main() {
    http.HandleFunc("/health", healthHandler)

    log.Println(
        "Servicio md-intake-lakehouse iniciado en puerto 8080..."
    )

    log.Fatal(
        http.ListenAndServe(":8080", nil),
    )
}
EOF

cat <<'EOF' > md-intake-lakehouse/Dockerfile
FROM golang:1.22-alpine AS build

WORKDIR /app

COPY go.mod ./

COPY . .

RUN go build -o server ./cmd/server

FROM alpine:3.20

WORKDIR /app

COPY --from=build /app/server .

EXPOSE 8080

CMD ["./server"]
EOF

echo -e "${GREEN}md-intake-lakehouse configurado correctamente.${NC}"

# ---------------------------------------------------------
# 6. FLUTTER WEB
# ---------------------------------------------------------

echo -e "\n${GREEN}Configurando ms-frontend (Flutter Web)...${NC}"

mkdir -p ms-frontend

if [ ! -f "ms-frontend/pubspec.yaml" ]; then

    echo -e "${YELLOW}No existe un proyecto Flutter. Creando proyecto base...${NC}"

    docker run --rm \
        -v "${WORKSPACE_ROOT}/ms-frontend:/app" \
        -w /tmp \
        ghcr.io/cirrusci/flutter:3.22.0 \
        sh -c '
            flutter create --project-name ms_frontend /app
            chown -R "$(stat -c "%u:%g" /app)" /app
        '

else

    echo -e "${GREEN}Proyecto Flutter existente detectado. No se sobrescribirá.${NC}"

fi

cat <<'EOF' > ms-frontend/Dockerfile
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

echo -e "${GREEN}ms-frontend configurado correctamente.${NC}"

# ---------------------------------------------------------
# 7. VALIDACIONES FINALES
# ---------------------------------------------------------

echo -e "\n${BLUE}Validando archivos generados...${NC}"

for MS in ms-users ms-payments; do

    test -f "$MS/pom.xml"
    test -f "$MS/Dockerfile"
    test -f "$MS/src/main/resources/application.yml"

done

test -f "ms-matching-geo/requirements.txt"
test -f "ms-matching-geo/Dockerfile"
test -f "ms-matching-geo/src/app/main.py"

test -f "md-intake-lakehouse/go.mod"
test -f "md-intake-lakehouse/Dockerfile"
test -f "md-intake-lakehouse/cmd/server/main.go"

test -f "ms-frontend/pubspec.yaml"
test -f "ms-frontend/Dockerfile"

echo -e "${GREEN}Todos los archivos base fueron generados correctamente.${NC}"

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${GREEN} ¡Código inicial listo para compilación!${NC}"
echo -e "${BLUE}====================================================${NC}"

echo
echo -e "${YELLOW}Siguientes pasos:${NC}"
echo "  1. Validar Java:"
echo "     docker build -t fixia-ms-users ./ms-users"
echo
echo "  2. Validar Payments:"
echo "     docker build -t fixia-ms-payments ./ms-payments"
echo
echo "  3. Validar Geo:"
echo "     docker build -t fixia-ms-matching-geo ./ms-matching-geo"
echo
echo "  4. Validar Lakehouse:"
echo "     docker build -t fixia-md-intake-lakehouse ./md-intake-lakehouse"
echo
echo "  5. Validar Frontend:"
echo "     docker build -t fixia-ms-frontend ./ms-frontend"

