# Diseño de Alto Nivel (HLD) — Arquitectura e Infraestructura de Fixia

Este documento presenta el **Diseño de Alto Nivel (HLD)** de la **Arquitectura Lógica de Software** y de la **Distribución Física en Clústeres Kubernetes (K3s)** de **Fixia** en el ambiente de QA, especificando de manera explícita el **lenguaje de programación**, **framework** y **rol exacto** de cada componente para evitar ambigüedades al generar diagramas o imágenes.

---

## 0. Catálogo Oficial de Microservicios y Lenguajes de Programación (Únicos 6 Componentes de Aplicación)

> [!IMPORTANT]
> **Fixia cuenta exclusivamente con 6 componentes de aplicación** (`1 Frontend SPA + 5 Microservicios de Backend`) desplegados en el namespace `apps`:
> - **NO existen otros microservicios de negocio.**
> - `ms-orchestrator` **NO es un microservicio en ejecución**: es únicamente el repositorio de **Infraestructura como Código (Ansible + Manifiestos Kubernetes)**.
> - `traefik` es el **API Gateway / Ingress Controller** (infraestructura de borde).
> - `kafka-exporter` y `promtail` son **agentes recolectores de observabilidad** (no microservicios de negocio).
> - `vault-0` y `mongodb-0` son pods de infraestructura base aprovisionados en el clúster pero **no son consumidos por ningún microservicio de Fixia**.

| # | Nombre del Componente | Tipo | Lenguaje de Programación | Framework / Runtime | Logo Oficial Recomendado | Puerto / Réplicas | Base de Datos / Almacenamiento |
| :-: | :--- | :--- | :--- | :--- | :--- | :---: | :--- |
| **1** | **`ms-frontend`** (`deployment/frontend`) | Frontend Web SPA | **Dart 3** | **Flutter Web 3.22** (servido por **Nginx 1.31 Alpine**) | **Flutter / Dart + Nginx** | `:8080` (2 réplicas) | N/A (Consume APIs REST vía Traefik) |
| **2** | **`ms-users`** (`deployment/ms-users`) | Microservicio Backend | **Java 21 (OpenJDK 21)** | **Spring Boot 3.3** (Maven, Spring Security, JPA) | **Java + Spring Boot** | `:8080` (2 réplicas) | PostgreSQL 16 (`ms_users`) + Kafka (`fixia.users.evaluations`) |
| **3** | **`ms-services`** (`deployment/ms-services`) | Microservicio Backend | **Java 21 (OpenJDK 21)** | **Spring Boot 3.3** (Maven, JPA, AWS SDK S3) | **Java + Spring Boot** | `:8080` (2 réplicas) | PostgreSQL 16 (`ms_services`) + RustFS S3 (`evidences`) + Kafka (`fixia.services.service-requests`) |
| **4** | **`ms-matching-geo`** (`deployment/ms-matching-geo`) | Microservicio Backend | **Python 3.12** | **FastAPI** + **Uvicorn** + **Pydantic v2** + **httpx** | **Python + FastAPI** | `:8000` (2 réplicas) | Stateless (Consulta `ms-users` por HTTP interno) |
| **5** | **`ms-payments`** (`deployment/ms-payments`) | Microservicio Backend | **C# 12** | **.NET 8 (ASP.NET Core 8.0 Web API + EF Core 8)** | **C# / .NET 8** | `:8080` (2 réplicas) | PostgreSQL 16 (`ms_payments`) + Kafka (`fixia.payments.events`) |
| **6** | **`ms-intake-lakehouse`** (`deployment/ms-intake-lakehouse`) | Microservicio Worker | **Go (Golang) 1.22** | **Go Standard Library (`net/http`) + `kafka-go` + `aws-sdk-go-v2`** | **Go (Golang Gopher)** | `:8080` (1 réplica) | Consume los 3 tópicos de Kafka + escribe en RustFS S3 (`lakehouse`) |

---

## 1. HLD de Arquitectura Lógica (Con Lenguajes y Frameworks Explícitos)

```mermaid
flowchart TB
    subgraph Clientes["Capa de Presentación y Usuarios"]
        USR["Usuarios Finales (Cliente / Técnico / Empresa / Admin)"]
        FE["1. ms-frontend (deployment/frontend)<br/>LENGUAJE: Dart 3 | FRAMEWORK: Flutter Web 3.22 + Nginx 1.31<br/>Puerto :8080 (2 Réplicas)"]
    end

    subgraph Gateway["Capa de Borde / API Gateway (namespace: traefik)"]
        TR["API Gateway: Traefik v3.0 (Reverse Proxy)<br/>LENGUAJE DE MOTOR: Go | Puerto :80 HTTP / :8080 Metrics (2 Réplicas)"]
    end

    subgraph Microservicios["Capa de los 5 Microservicios de Backend (namespace: apps)"]
        MSU["2. ms-users<br/>LENGUAJE: Java 21 | FRAMEWORK: Spring Boot 3.3 (Maven)<br/>Puerto :8080 (2 Réplicas - perfil seed-qa)"]
        MSS["3. ms-services<br/>LENGUAJE: Java 21 | FRAMEWORK: Spring Boot 3.3 (Maven)<br/>Puerto :8080 (2 Réplicas)"]
        MSG["4. ms-matching-geo<br/>LENGUAJE: Python 3.12 | FRAMEWORK: FastAPI + Uvicorn<br/>Puerto :8000 (2 Réplicas - Stateless)"]
        MSP["5. ms-payments<br/>LENGUAJE: C# 12 | FRAMEWORK: .NET 8 (ASP.NET Core 8.0 + EF Core)<br/>Puerto :8080 (2 Réplicas)"]
        MSL["6. ms-intake-lakehouse<br/>LENGUAJE: Go (Golang) 1.22 | LIBRERÍAS: kafka-go + aws-sdk-go-v2<br/>Puerto :8080 (1 Réplica Worker)"]
    end

    subgraph Datos["Capa de Persistencia y Eventos Activos (namespace: data)"]
        PG["PostgreSQL 16 (StatefulSet postgres-0 :5432)<br/>3 Bases de Datos: ms_users | ms_services | ms_payments"]
        KF["Apache Kafka 3.9 KRaft (StatefulSet kafka-0 :9092)<br/>3 Tópicos: fixia.services.service-requests | fixia.payments.events | fixia.users.evaluations"]
        RFS["RustFS S3 Storage (StatefulSet rustfs-0 :9000)<br/>2 Buckets S3: evidences (fotos) | lakehouse (eventos JSON)"]
    end

    subgraph Observabilidad["Capa de Observabilidad Centralizada (Nodo qa-obs-01 : 10.43.98.217)"]
        PRM["Agente Promtail (DaemonSet en cada nodo K3s)"]
        KEX["Agente Kafka Exporter (:9308)"]
        PRO["Prometheus (:9090 - 23 Targets UP)"]
        LOK["Grafana Loki (:3100 - Agregación de Logs)"]
        GRA["Grafana (:3000 - Dashboards de Métricas y Logs)"]
    end

    %% Flujo de Entrada
    USR -->|"HTTP :80"| TR
    TR -->|"Path: / (priority 1)"| FE
    TR -->|"PathPrefix: /api/users (priority 10)"| MSU
    TR -->|"PathPrefix: /api/services (priority 10)"| MSS
    TR -->|"PathPrefix: /api/geo (priority 10)"| MSG
    TR -->|"PathPrefix: /api/payments (priority 10)"| MSP

    %% Comunicación Interna Síncrona (X-Internal-Api-Key)
    MSS -->|"HTTP Interno /internal/* (Perfiles, Elegibilidad, Empresas)"| MSU
    MSS -->|"HTTP Interno /api/geo/matching/technicians"| MSG
    MSG -->|"HTTP Interno /internal/technicians/search"| MSU
    MSU -.->|"JWKS / Clave Pública RS256"| MSS
    MSU -.->|"JWKS / Clave Pública RS256"| MSG
    MSU -.->|"JWKS / Clave Pública RS256"| MSP

    %% Persistencia Relacional y Objetos
    MSU -->|"JDBC / JPA (BD: ms_users + outbox_events)"| PG
    MSS -->|"JDBC / JPA (BD: ms_services + outbox_events)"| PG
    MSP -->|"EF Core 8 / Npgsql (BD: ms_payments + outbox_events)"| PG
    MSS -->|"AWS SDK S3 (Bucket: evidences)"| RFS

    %% Coreografía Asíncrona por Kafka (Patrón Outbox)
    MSS ==>|"Outbox Relay -> fixia.services.service-requests"| KF
    MSP ==>|"Outbox Relay -> fixia.payments.events"| KF
    MSU ==>|"Outbox -> fixia.users.evaluations"| KF

    KF ==>|"Consume servicio.contratado / servicio.cerrado"| MSP
    KF ==>|"Consume pago.procesado / pago.fallido"| MSS
    KF ==>|"Consume los 3 tópicos (GroupTopics)"| MSL
    MSL ==>|"Valida JSON Schema 2020-12 y guarda en Bucket: lakehouse"| RFS

    %% Observabilidad
    KEX -->|"Métricas de Tópicos y Consumer Lag"| KF
    PRO -->|"Scrape /actuator/prometheus y /metrics"| Microservicios
    PRO -->|"Scrape :8080/metrics"| TR
    PRO -->|"Scrape :9308"| KEX
    PRM -->|"Push de Logs de Contenedores"| LOK
    GRA -->|"Consultas PromQL"| PRO
    GRA -->|"Consultas LogQL"| LOK
```

---

## 2. HLD de Infraestructura y Distribución Física por Nodos y Pods (Clúster K3s QA)

```mermaid
flowchart LR
    subgraph GitHub["GitHub Cloud & GHCR"]
        GHA["GitHub Actions CI (Build & Test en rama Qa)"]
        GHCR["GitHub Container Registry (ghcr.io/grupo-fixia/*)"]
        GHA -->|"Push Docker Image"| GHCR
    end

    subgraph NodoCoord["Nodo Coordinador y Observabilidad: qa-obs-01 / nbig23 (10.43.98.217)"]
        ANS["ms-orchestrator: Playbooks Ansible (IaC - No es un microservicio)"]
        RUNNER["GitHub Self-Hosted Runner (Workflow CD)"]
        subgraph K3sObs["Clúster K3s Observabilidad (namespace: observability)"]
            P_PROM["Pod: prometheus (:9090)"]
            P_LOKI["StatefulSet: loki-0 (:3100)"]
            P_GRAF["Pod: grafana (:3000)"]
            P_PROMT0["DaemonSet: promtail (local)"]
        end
    end

    subgraph ClusterQA["Clúster K3s Principal de QA (Red 10.43.98.0/23 - Flannel VXLAN 10.244.0.0/16)"]
        subgraph Node1["qa-k3s-01 / nbig17 (10.43.98.211) — Control Plane & Worker (10.244.0.0/24)"]
            API["K3s Control Plane (:6443), CoreDNS, Local-Path, Metrics-Server & ServiceLB (x5)"]
            T1["Pod Gateway: traefik-7bbb4dc5c-h845r (10.244.0.46) — Réplica 1/2"]
            S1["Pod [JAVA 21 / SPRING BOOT 3]: ms-services-5f58c77b65-ch77f (10.244.0.52) — Réplica 1/2"]
            KF0["StatefulSet Broker: kafka-0 (10.244.0.15 | PVC data-kafka-0 8Gi)"]
            PROMT1["Agente Logs: promtail-2lst2 (10.244.0.20)"]
        end

        subgraph Node2["qa-k3s-02 / nbig59 (10.43.98.253) — Worker 1 (10.244.1.0/24)"]
            FE1["Pod [DART / FLUTTER WEB + NGINX]: frontend-d5df9cfdc-r8p6g (10.244.1.44) — Réplica 1/2"]
            U1["Pod [JAVA 21 / SPRING BOOT 3]: ms-users-866d86db84-mbm9h (10.244.1.50 | seed-qa) — Réplica 1/2"]
            S2["Pod [JAVA 21 / SPRING BOOT 3]: ms-services-5f58c77b65-rszs2 (10.244.1.52) — Réplica 2/2"]
            P1["Pod [C# 12 / .NET 8]: ms-payments-6496744d9d-2md54 (10.244.1.51) — Réplica 1/2"]
            G1["Pod [PYTHON 3.12 / FASTAPI]: ms-matching-geo-576ddfd96d-ks4tq (10.244.1.43) — Réplica 1/2"]
            L1["Pod [GO / GOLANG 1.22]: ms-intake-lakehouse-7bddb8cd86-26bbv (10.244.1.53) — Réplica 1/1"]
            PG0["StatefulSet BD: postgres-0 (10.244.1.6 | PVC data-postgres-0 5Gi)"]
            KE["Agente Métricas: kafka-exporter-64d9bc5547-knnp4 (10.244.1.16)"]
            PROMT2["Agente Logs: promtail-b6dhn (10.244.1.14) & ServiceLB (x5)"]
        end

        subgraph Node3["qa-k3s-03 / nbig65 (10.43.99.6) — Worker 2 (10.244.3.0/24)"]
            T2["Pod Gateway: traefik-7bbb4dc5c-9h8rl (10.244.3.50) — Réplica 2/2"]
            FE2["Pod [DART / FLUTTER WEB + NGINX]: frontend-d5df9cfdc-rn49z (10.244.3.48) — Réplica 2/2"]
            U2["Pod [JAVA 21 / SPRING BOOT 3]: ms-users-866d86db84-jc4b9 (10.244.3.55 | seed-qa) — Réplica 2/2"]
            P2["Pod [C# 12 / .NET 8]: ms-payments-6496744d9d-d6wlc (10.244.3.56) — Réplica 2/2"]
            G2["Pod [PYTHON 3.12 / FASTAPI]: ms-matching-geo-576ddfd96d-8wgql (10.244.3.47) — Réplica 2/2"]
            RFS0["StatefulSet S3: rustfs-0 (10.244.3.37 | PVC data-rustfs-0 5Gi) + Job rustfs-init"]
            UNUSED["Infraestructura Base sin uso activo: vault-0 (1Gi) & mongodb-0 (5Gi)"]
            PROMT3["Agente Logs: promtail-qn985 (10.244.3.18) & ServiceLB (x5)"]
        end
    end

    %% Relaciones de Despliegue y Monitoreo
    ANS -->|"Aprovisiona K3s, Datos, Secretos y Observabilidad (SSH)"| ClusterQA
    RUNNER -->|"kubectl apply & rollout (KUBECONFIG)"| API
    ClusterQA -->|"Pull con secret/ghcr-pull"| GHCR
    P_PROM -->|"Scrape Métricas (:9100-:9104, :9108, :9180, :10250)"| ClusterQA
    PROMT1 & PROMT2 & PROMT3 -->|"Envío de Logs HTTP :3100"| P_LOKI
```

---

## 3. Flujo Transaccional y Coreografía de Eventos (Outbox + Kafka + Lakehouse)

```mermaid
sequenceDiagram
    autonumber
    actor C as Cliente
    actor T as Técnico / Empresa
    participant TR as Traefik Gateway (Go)
    participant MSU as ms-users (Java 21 / Spring Boot 3)
    participant MSG as ms-matching-geo (Python 3.12 / FastAPI)
    participant MSS as ms-services (Java 21 / Spring Boot 3)
    participant KF as Apache Kafka 3.9
    participant MSP as ms-payments (C# 12 / .NET 8)
    participant MSL as ms-intake-lakehouse (Go 1.22)
    participant RFS as RustFS (S3 Storage)

    C->>TR: POST /api/services/requests
    TR->>MSS: Crea solicitud (PUBLISHED) + Outbox
    MSS-->>KF: Publica solicitud.publicada

    T->>TR: GET /api/services/opportunities
    TR->>MSS: Consulta oportunidades compatibles
    MSS->>MSG: POST /api/geo/matching/technicians
    MSG->>MSU: POST /internal/technicians/search (zona + horario)
    MSU-->>MSG: Técnicos elegibles
    MSG-->>MSS: Técnicos dentro del radio Haversine
    MSS-->>T: Lista de oportunidades

    T->>TR: POST /api/services/applications
    TR->>MSS: Registra postulación (APPLIED) + Outbox
    MSS-->>KF: Publica postulacion.registrada

    C->>TR: POST /requests/{id}/applications/{appId}/selection
    TR->>MSS: Selecciona prestador (PROVIDER_SELECTED) + Outbox
    MSS-->>KF: Publica prestador.seleccionado

    T->>TR: POST /api/services/quotations
    TR->>MSS: Envía cotización formal + Outbox
    MSS-->>KF: Publica cotizacion.enviada

    C->>TR: POST /requests/{id}/quotations/{quotId}/acceptance
    TR->>MSS: Formaliza contrato (CONTRACTED) + Outbox
    MSS-->>KF: Publica servicio.contratado

    KF->>MSP: Consume servicio.contratado
    MSP->>MSP: Retiene saldo (Precio + Comisión 15%) en Billetera + Outbox
    MSP-->>KF: Publica pago.creado y pago.procesado (o pago.fallido)

    KF->>MSS: Consume pago.procesado
    MSS->>MSS: Marca contrato con pago retenido (HELD) y habilita dirección exacta

    T->>TR: POST /api/services/contracts/{id}/start
    TR->>MSS: Valida pago retenido (GC-490) -> IN_PROGRESS + Outbox
    MSS-->>KF: Publica servicio.iniciado

    T->>TR: POST /api/services/contracts/{id}/evidences
    TR->>MSS: Valida y sube imagen
    MSS->>RFS: PUT Object (bucket: evidences)
    MSS-->>KF: Publica evidencia.registrada

    T->>TR: POST /api/services/contracts/{id}/finish
    TR->>MSS: Pasa a TECHNICIAN_FINISHED + Outbox
    MSS-->>KF: Publica servicio.finalizado

    C->>TR: POST /api/services/requests/{id}/closure
    TR->>MSS: Confirma cierre (CLOSED) + Outbox
    MSS-->>KF: Publica servicio.cerrado

    KF->>MSP: Consume servicio.cerrado
    MSP->>MSP: Liquida pago: acredita 100% del precio al técnico + Outbox
    MSP-->>KF: Publica pago.completado

    C->>TR: POST /api/users/evaluations
    TR->>MSU: Verifica participación en ms-services y guarda evaluación + Outbox
    MSU-->>KF: Publica evaluacion.registrada

    KF->>MSL: Consume fixia.services.*, fixia.payments.*, fixia.users.*
    MSL->>MSL: Valida sobre y JSON Schema (Draft 2020-12)
    MSL->>RFS: Persiste idempotente en bucket lakehouse (events/producer=.../type=.../)
```
