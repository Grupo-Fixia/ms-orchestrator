# Diseño de Alto Nivel (HLD) — Arquitectura e Infraestructura Multi-Ambiente (Producción, QA y Observabilidad) de Fixia

> **Última Actualización:** 2026-11-24  
> **Ambientes Activos:** **Producción** (Clúster K3s HA con Aislamiento Físico Apps/Data + Túneles Cloudflare HTTPS), **QA** (Clúster K3s HA) y **Nodo Central de Orquestación y Observabilidad** (`10.43.98.217` / `nbig23`).  
> **Arquitectura de Comunicación:** **Cero Dependencias HTTP Síncronas entre Microservicios (`GC-547`)** — Replicación de estado mediante 5 tópicos compactados en Apache Kafka (`cleanup.policy=compact`), lista local de sesiones revocadas (`fixia.users.sessions`) y Patrón Transactional Outbox hacia el Data Lakehouse (`RustFS S3`).

---

## 0. Catálogo Oficial de Microservicios y Lenguajes de Programación (6 Componentes de Aplicación)

> [!IMPORTANT]
> **Fixia cuenta exclusivamente con 6 componentes de aplicación** (`1 Frontend SPA + 5 Microservicios de Backend`) desplegados en el namespace `apps`:
> - **`ms-orchestrator`** **NO es un microservicio en ejecución**: es el repositorio de **Infraestructura como Código (Ansible + Vault + Manifiestos Kubernetes + Docker Compose)**.
> - **`traefik`** es el **API Gateway / Ingress Controller** (infraestructura de borde en el namespace `traefik`, con middlewares OWASP ZAP, CORS, Rate Limiting y bloqueo de `/internal/**`).
> - **`cloudflared-frontend`** y **`cloudflared-api`** son los conectores Zero-Trust de Cloudflare que exponen el Frontend y el API Gateway de Producción por HTTPS (`TLS 1.3`).
> - **`kafka-exporter`** (`:9308`) y **`promtail`** (DaemonSet) son agentes recolectores de observabilidad que reportan al clúster central en `10.43.98.217`.

| # | Componente (`namespace: apps`) | Tipo | Lenguaje / Runtime | Framework y Librerías Clave | Puertos (App / Métricas) | Réplicas (QA / Prod) | Persistencia y Tópicos Kafka |
| :-: | :--- | :--- | :--- | :--- | :---: | :---: | :--- |
| **1** | **`ms-frontend`** (`deployment/frontend`) | Frontend Web SPA | **Dart 3.4** | **Flutter Web 3.22** + **Nginx 1.27 Alpine** (Cabeceras OWASP + Interceptor `window.fetch`/XHR con cifrado `ENC:v1`) | `:8080` (Service `:80`) | `2 / 2` | Stateless (Consume el API Gateway por HTTPS en Prod y HTTP en QA) |
| **2** | **`ms-users`** (`deployment/ms-users`) | Microservicio Backend | **Java 21 LTS (OpenJDK 21)** | **Spring Boot 3.2.5**, Spring Security OAuth2 JWT (RS256), BCrypt costo 12, `CredentialCipher` (`ENC:v1`), JPA, Flyway (`V14`), Micrometer | `:8080` / `:9101` (`/actuator/prometheus`) | `2 / 2` | **PostgreSQL 16 (`ms_users`)**.<br/>**Produce:** `fixia.users.evaluations`, `fixia.users.technician-states` (compact), `fixia.users.company-states` (compact), `fixia.users.sessions`.<br/>**Consume:** `fixia.services.participations`, `fixia.services.executor-workloads`, `fixia.payments.held-services`. |
| **3** | **`ms-services`** (`deployment/ms-services`) | Microservicio Backend | **Java 21 LTS (OpenJDK 21)** | **Spring Boot 3.2.5**, JPA, Flyway (`V19`), AWS SDK S3 v2 (`evidences`, `max-swallow-size: -1`), Spring Kafka, Micrometer | `:8080` / `:9102` (`/actuator/prometheus`) | `2 / 2` | **PostgreSQL 16 (`ms_services`)** + **RustFS S3 (`evidences`)**.<br/>**Produce:** `fixia.services.service-requests`, `fixia.services.participations` (compact), `fixia.services.executor-workloads` (compact).<br/>**Consume:** `fixia.payments.events`, `fixia.users.technician-states`, `fixia.users.company-states`, `fixia.users.sessions`. |
| **4** | **`ms-matching-geo`** (`deployment/ms-matching-geo`) | Microservicio Backend | **Python 3.12** | **FastAPI 0.111**, Uvicorn, `confluent-kafka 2.6.1`, PyJWT (RS256), Middleware Prometheus nativo | `:8000` / `:9104` (`/actuator/prometheus`, `/metrics`) | `2 / 2` | **In-Memory State Replica (Stateless)**.<br/>**Consume:** `fixia.users.technician-states` (directorio local de técnicos) y `fixia.users.sessions` (lista local de tokens revocados). |
| **5** | **`ms-payments`** (`deployment/ms-payments`) | Microservicio Backend | **C# 12 / .NET 8.0** | **ASP.NET Core 8.0 Web API**, EF Core 8, Npgsql, `Confluent.Kafka`, `PrometheusMetricsMiddleware` | `:8080` / `:9103` (`/actuator/prometheus`, `/metrics`) | `2 / 2` | **PostgreSQL 16 (`ms_payments`)**.<br/>**Produce:** `fixia.payments.events`, `fixia.payments.held-services` (compact).<br/>**Consume:** `fixia.services.service-requests`, `fixia.users.sessions`. |
| **6** | **`ms-intake-lakehouse`** (`deployment/ms-intake-lakehouse`) | Microservicio Worker | **Go (Golang) 1.22** | `segmentio/kafka-go` (`SessionTimeout: 6s`, `LeaveGroup` limpio), `minio-go/v7`, `santhosh-tekuri/jsonschema/v5` (Draft 2020-12) | `:8080` (`/health`, `/metrics`) | `1 / 1` | **RustFS S3 (`lakehouse`)**.<br/>**Consume:** `fixia.services.service-requests`, `fixia.payments.events`, `fixia.users.evaluations`. Escribe en `events/` o `quarantine/`. |

---

## 1. Topología General Multi-Ambiente (Red LAN Institucional `10.43.98.0/22`)

Todos los **7 servidores Linux (Ubuntu 22.04.5 LTS)** conviven bajo la misma red institucional y son gobernados centralmente por el nodo **`nbig23` (`10.43.98.217`)**, que actúa simultáneamente como **Orquestador Ansible**, **Coordinador de Runners CI/CD (`nbig23-qa` y `nbig23-prod`)** y **Clúster de Observabilidad Central (`47/47 Targets UP`)**.

| Ambiente | Hostname | Nombre Inventario | Dirección IP | Rol en Kubernetes (K3s) | Etiquetas / Taints de Carga | Cargas Alojadas |
| :--- | :--- | :--- | :---: | :--- | :--- | :--- |
| **Orquestación & Observabilidad** | **`nbig23`** | `qa-obs-01` | `10.43.98.217` | K3s Single-Node (`observability`) + Ansible + GitHub Runners | `node-role.kubernetes.io/control-plane` | `prometheus` (`:9090`), `grafana` (`:3000`), `loki-0` (`:3100`), `promtail`, Runners `nbig23-qa` y `nbig23-prod` |
| **PRODUCCIÓN** | **`nbig37`** | `prod-k3s-01` (`produccion_1`) | `10.43.98.231` | K3s Server HA (`control-plane,etcd`) + App Worker 1 | `workload=apps` | Réplica 1 de `frontend`, `ms-users`, `ms-services`, `ms-payments`, `ms-matching-geo`, `ms-intake-lakehouse`, `promtail` |
| **PRODUCCIÓN** | **`nbig50`** | `prod-k3s-02` (`produccion_2`) | `10.43.98.244` | K3s Server HA (`control-plane,etcd`) + App Worker 2 | `workload=apps` | Réplica 2 de `frontend`, `ms-users`, `ms-services`, `ms-payments`, `ms-matching-geo`, `traefik` (x2), `cloudflared-frontend`, `cloudflared-api`, `kafka-exporter`, `promtail` |
| **PRODUCCIÓN** | **`nbig452`** | `prod-k3s-03` (`produccion_3`) | `10.43.100.155` | K3s Server HA (`control-plane,etcd`) + **Data Node Exclusivo** | `workload=data` + **Taint `workload=data:NoSchedule`** | **Exclusivo Capa de Datos (`namespace: data`):** `postgres-0` (5Gi), `kafka-0` (8Gi), `rustfs-0` (5Gi), `mongodb-0` (5Gi), `vault-0` (1Gi), `promtail` |
| **QA** | **`nbig17`** | `qa-k3s-01` | `10.43.98.211` | K3s Server HA (`control-plane,etcd`) + Worker Mixto 1 | Mixto (`apps` + `data`) | `kafka-0`, `traefik`, pods de `apps`, `promtail` |
| **QA** | **`nbig59`** | `qa-k3s-02` | `10.43.98.253` | K3s Server HA (`control-plane,etcd`) + Worker Mixto 2 | Mixto (`apps` + `data`) | `postgres-0`, `kafka-exporter`, pods de `apps`, `promtail` |
| **QA** | **`nbig65`** | `qa-k3s-03` | `10.43.99.6` | K3s Server HA (`control-plane,etcd`) + Worker Mixto 3 | Mixto (`apps` + `data`) | `rustfs-0`, `mongodb-0`, `vault-0`, `traefik`, pods de `apps`, `promtail` |

---

## 2. HLD de Arquitectura Lógica y Malla de Eventos (Kafka State Replication + Outbox + Lakehouse)

```mermaid
flowchart TB
    subgraph Clientes["1. Canales de Acceso y Seguridad de Transporte"]
        USR["Usuarios Finales (Cliente / Técnico / Empresa / Admin)"]
        CF_FE["Túnel HTTPS Cloudflare Frontend<br/>https://hook-excellence-champion-wallet.trycloudflare.com"]
        CF_API["Túnel HTTPS Cloudflare API Gateway<br/>https://fits-descending-section-constant.trycloudflare.com"]
        FE["1. ms-frontend (Dart 3 / Flutter Web 3.22 + Nginx)<br/>Interceptor window.fetch/XHR: Cifrado de Payload ENC:v1 (SHA-256 CTR + Nonce 128-bit)"]
    end

    subgraph Gateway["2. Capa de Borde / API Gateway (namespace: traefik)"]
        TR["Traefik v3.3 Reverse Proxy (:80 / :8080)<br/>Middlewares OWASP ZAP (CSP, HSTS, X-Frame-Options, nosniff)<br/>CORS Dinámico + RateLimit (100 req/s) + Bloqueo /internal/** (403)"]
    end

    subgraph Microservicios["3. Capa de Microservicios de Negocio (namespace: apps — Nodos workload=apps)"]
        MSU["2. ms-users (Java 21 / Spring Boot 3.2.5)<br/>:8080 | Métricas :9101 | Flyway V14<br/>Descifrado ENC:v1 + BCrypt-12 + Emisor JWT RS256"]
        MSS["3. ms-services (Java 21 / Spring Boot 3.2.5)<br/>:8080 | Métricas :9102 | Flyway V19<br/>Solicitudes, Postulaciones, Cotizaciones, Contratos, Chat y Evidencias"]
        MSG["4. ms-matching-geo (Python 3.12 / FastAPI)<br/>:8000 | Métricas :9104<br/>Matching Geoespacial Haversine sobre Réplica Local en Memoria"]
        MSP["5. ms-payments (C# 12 / .NET 8 ASP.NET Core)<br/>:8080 | Métricas :9103 | EF Core 8<br/>Billeteras, Retenciones (Escrow), Comisiones, Reembolsos y Auditoría"]
        MSL["6. ms-intake-lakehouse (Go 1.22)<br/>:8080 | Rebalanceo rápido (SessionTimeout 6s + LeaveGroup)<br/>Validador JSON Schema Draft 2020-12"]
    end

    subgraph KafkaMesh["4. Malla de Eventos Asíncrona — Apache Kafka 3.8 KRaft (kafka-0 :9092)"]
        KF_STATE["5 Tópicos Compactados de Replicación de Estado (cleanup.policy=compact)<br/>• fixia.users.technician-states<br/>• fixia.users.company-states<br/>• fixia.services.participations<br/>• fixia.services.executor-workloads<br/>• fixia.payments.held-services"]
        KF_SESS["Tópico de Revocación de Sesiones en Tiempo Real<br/>• fixia.users.sessions (Relay 500ms)"]
        KF_DOM["3 Tópicos de Eventos de Dominio (3 Particiones c/u)<br/>• fixia.services.service-requests<br/>• fixia.payments.events<br/>• fixia.users.evaluations"]
    end

    subgraph Datos["5. Capa de Persistencia Aislada (namespace: data — Nodo nbig452 workload=data)"]
        PG["PostgreSQL 16 (postgres-0 :5432)<br/>3 Bases de Datos: ms_users | ms_services | ms_payments"]
        RFS["RustFS S3 Storage (rustfs-0 :9000)<br/>2 Buckets: evidences (privado) | lakehouse (events/ y quarantine/)"]
        VLT["HashiCorp Vault 1.17 (vault-0 :8200) & MongoDB 7.0 (mongodb-0 :27017)"]
    end

    USR -->|"HTTPS TLS 1.3"| CF_FE --> FE
    FE -->|"HTTPS REST + Payload ENC:v1 + Bearer JWT"| CF_API --> TR
    TR -->|"/api/users/**"| MSU
    TR -->|"/api/services/**"| MSS
    TR -->|"/api/geo/**"| MSG
    TR -->|"/api/payments/**"| MSP

    %% Replicación de Estado sin llamadas HTTP entre servicios (GC-547)
    MSU <==>|"Publica estados de técnicos/empresas y consume participaciones/cargas/retenciones"| KF_STATE
    MSS <==>|"Publica participaciones/cargas y consume estados de técnicos/empresas"| KF_STATE
    MSP ==>|"Publica held-services"| KF_STATE
    KF_STATE ==>|"Alimenta directorio local de técnicos"| MSG

    %% Revocación de sesiones
    MSU ==>|"Publica sesion.revocada (500ms)"| KF_SESS
    KF_SESS ==>|"Actualiza lista local de JTI revocados"| MSS & MSG & MSP

    %% Eventos de dominio y Lakehouse
    MSU & MSS & MSP ==>|"Outbox Relay"| KF_DOM
    KF_DOM <==>|"Coreografía Saga: servicio.contratado / pago.procesado / servicio.cerrado"| MSS & MSP
    KF_DOM ==>|"Consume los 3 tópicos"| MSL
    MSL ==>|"Persistencia Idempotente / Cuarentena"| RFS

    %% Base de datos y objetos
    MSU & MSS & MSP --> PG
    MSS -->|"S3 PutObject / GetObject (bucket: evidences)"| RFS
```

---

## 3. HLD de Distribución Física del Clúster K3s de PRODUCCIÓN (Aislamiento Apps vs. Data)

```mermaid
flowchart LR
    subgraph GitHub["GitHub Cloud (CI/CD & GHCR)"]
        GHA["Workflows ci-prod.yml & cd-prod.yml (Rama: main)<br/>Quality Gate Cobertura: JaCoCo mvn verify (>=80-85%), Pytest (>=85%), Go Cover (>=80%), Flutter Test (>=80%)"]
        GHCR["GitHub Container Registry<br/>ghcr.io/grupo-fixia/*"]
        GHA -->|"Push Image :SHA-12"| GHCR
    end

    subgraph Coord["Nodo Central Orquestador y Observabilidad: nbig23 (10.43.98.217)"]
        ANS["ms-orchestrator (Ansible Playbooks 01..12 + Vault)<br/>Inventario: ansible/inventory/produccion/hosts.yml"]
        RUN["GitHub Runner: nbig23-prod.service<br/>KUBECONFIG: ~/.kube/deployer-prod.yaml"]
        OBS["Clúster K3s Observabilidad (namespace: observability)<br/>Prometheus (:9090 - 47/47 Targets UP) · Grafana (:3000) · Loki (:3100)"]
    end

    subgraph ProdCluster["Clúster K3s HA PRODUCCIÓN (v1.37.1+k3s1 — Flannel VXLAN 10.244.0.0/16)"]
        subgraph ProdNode1["prod-k3s-01 / nbig37 (10.43.98.231) — Server HA + Worker Apps [label: workload=apps]"]
            P1_FE["frontend (Réplica 1/2)"]
            P1_U["ms-users (Réplica 1/2)"]
            P1_S["ms-services (Réplica 1/2)"]
            P1_P["ms-payments (Réplica 1/2)"]
            P1_G["ms-matching-geo (Réplica 1/2)"]
            P1_L["ms-intake-lakehouse (1/1)"]
            P1_PR["promtail-dlh2v"]
        end

        subgraph ProdNode2["prod-k3s-02 / nbig50 (10.43.98.244) — Server HA + Worker Apps [label: workload=apps]"]
            P2_TR["traefik (2/2 Réplicas) + ConfigMap OWASP/CORS/RateLimit"]
            P2_CF["cloudflared-frontend & cloudflared-api (Túneles HTTPS)"]
            P2_FE["frontend (Réplica 2/2)"]
            P2_U["ms-users (Réplica 2/2)"]
            P2_S["ms-services (Réplica 2/2)"]
            P2_P["ms-payments (Réplica 2/2)"]
            P2_G["ms-matching-geo (Réplica 2/2)"]
            P2_KE["kafka-exporter (:9308)"]
            P2_PR["promtail-tks92"]
        end

        subgraph ProdNode3["prod-k3s-03 / nbig452 (10.43.100.155) — Server HA + Nodo Exclusivo Datos [label: workload=data | Taint: workload=data:NoSchedule]"]
            D_PG["postgres-0 (:5432 | PVC 5Gi)<br/>BDs: ms_users, ms_services, ms_payments"]
            D_KF["kafka-0 (:9092 | PVC 8Gi)<br/>9 Tópicos (5 compactados + 1 sesiones + 3 eventos)"]
            D_RF["rustfs-0 (:9000/:9001 | PVC 5Gi)<br/>Buckets: lakehouse, evidences"]
            D_MG["mongodb-0 (:27017 | PVC 5Gi)"]
            D_VL["vault-0 (:8200 | PVC 1Gi)"]
            P3_PR["promtail-lvpjg"]
        end
    end

    ANS -->|"Aprovisionamiento SSH + Sudo"| ProdCluster
    RUN -->|"RollingUpdate en namespace apps"| ProdCluster
    OBS -->|"Scrape :9101-:9104, :9308, :8080, :10250"| ProdCluster
    P1_PR & P2_PR & P3_PR -->|"Push Logs (environment=production)"| OBS
```
