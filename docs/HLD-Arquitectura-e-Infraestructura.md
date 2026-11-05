# Diseño de Alto Nivel (HLD) — Arquitectura e Infraestructura de Fixia

Este documento presenta los diagramas de **Alto Nivel (HLD)** tanto de la **Arquitectura Lógica de Software y Datos** como de la **Infraestructura Física / Clústeres Kubernetes (K3s)** desplegados en el ambiente de QA.

---

## 1. HLD de Arquitectura Lógica (Microservicios, Datos, Mensajería y Observabilidad)

```mermaid
flowchart TB
    subgraph Clientes["Capa de Presentación y Usuarios"]
        USR["Usuarios (Cliente / Técnico / Empresa / Admin)"]
        FE["ms-frontend (Flutter Web SPA - Nginx :8080 x2)"]
    end

    subgraph Gateway["Capa de Borde y Enrutamiento (namespace: traefik)"]
        TR["API Gateway Traefik v3.0 (:80 HTTP / :8080 Metrics x2)"]
    end

    subgraph Microservicios["Capa de Microservicios de Dominio (namespace: apps)"]
        MSU["ms-users (Java 21 / Spring Boot :8080 x2)"]
        MSS["ms-services (Java 21 / Spring Boot :8080 x2)"]
        MSG["ms-matching-geo (Python 3.12 / FastAPI :8000 x2)"]
        MSP["ms-payments (.NET 8 / ASP.NET Core :8080 x2)"]
        MSL["ms-intake-lakehouse (Go 1.22 Worker :8080 x1)"]
    end

    subgraph Datos["Capa de Persistencia, Eventos y Objetos (namespace: data)"]
        PG["PostgreSQL 16 (Bases: ms_users, ms_services, ms_payments)"]
        KF["Apache Kafka 3.9 KRaft (:9092 - Tópicos de Dominio)"]
        RFS["RustFS S3 (:9000 - Buckets: evidences, lakehouse)"]
        VLT["HashiCorp Vault 1.15 (:8200 - Gestión de Secretos)"]
        MDB["MongoDB 7.0 (:27017 - Almacenamiento NoSQL)"]
    end

    subgraph Observabilidad["Capa de Observabilidad Centralizada (qa-obs-01 : 10.43.98.217)"]
        PRM["Promtail DaemonSet (Agentes de Logs en cada nodo)"]
        KEX["Kafka Exporter (:9308)"]
        PRO["Prometheus (:9090 - 23 Targets UP)"]
        LOK["Grafana Loki (:3100 - Agregación de Logs)"]
        GRA["Grafana (:3000 - Dashboards de Arquitectura)"]
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
    MSU -->|"JDBC (ms_users + outbox_events)"| PG
    MSS -->|"JDBC (ms_services + outbox_events)"| PG
    MSP -->|"EF Core (ms_payments + outbox_events)"| PG
    MSS -->|"API S3 (Fotos de Evidencia)"| RFS

    %% Coreografía Asíncrona por Kafka (Patrón Outbox)
    MSS ==>|"Outbox Relay -> fixia.services.service-requests"| KF
    MSP ==>|"Outbox Relay -> fixia.payments.events"| KF
    MSU ==>|"Outbox -> fixia.users.evaluations"| KF

    KF ==>|"Consume servicio.contratado / servicio.cerrado"| MSP
    KF ==>|"Consume pago.procesado / pago.fallido"| MSS
    KF ==>|"Consume los 3 tópicos (GroupTopics)"| MSL
    MSL ==>|"Valida JSON Schema y persiste idempotente"| RFS

    %% Observabilidad
    KEX -->|"Métricas de Tópicos y Lag"| KF
    PRO -->|"Scrape /actuator/prometheus y /metrics"| Microservicios
    PRO -->|"Scrape :8080/metrics"| TR
    PRO -->|"Scrape :9308"| KEX
    PRM -->|"Push de Logs de Contenedores"| LOK
    GRA -->|"Consultas PromQL"| PRO
    GRA -->|"Consultas LogQL"| LOK
```

---

## 2. HLD de Infraestructura y Topología de Clústeres (Despliegue en QA)

```mermaid
flowchart LR
    subgraph GitHub["GitHub Cloud & GHCR"]
        GHA["GitHub Actions CI (Build & Test en rama Qa)"]
        GHCR["GitHub Container Registry (ghcr.io/grupo-fixia/*)"]
        GHA -->|"Push Docker Image"| GHCR
    end

    subgraph NodoCoord["Nodo Coordinador y Observabilidad: qa-obs-01 / nbig23 (10.43.98.217)"]
        ANS["Ansible Playbooks (ms-orchestrator)"]
        RUNNER["GitHub Self-Hosted Runner (Workflow CD)"]
        subgraph K3sObs["Clúster K3s Observabilidad (namespace: observability)"]
            P_PROM["Pod: prometheus (:9090)"]
            P_LOKI["StatefulSet: loki-0 (:3100)"]
            P_GRAF["Pod: grafana (:3000)"]
            P_PROMT0["DaemonSet: promtail (local)"]
        end
    end

    subgraph ClusterQA["Clúster K3s Principal de QA (Red 10.43.98.0/23 - Flannel VXLAN)"]
        subgraph Node1["qa-k3s-01 / nbig17 (10.43.98.211) — Control Plane & Worker"]
            API["K3s API Server (:6443) & ServiceLB"]
            T1["traefik (1 réplica)"]
            S1["ms-services (1 réplica)"]
            PROMT1["promtail (DaemonSet)"]
        end

        subgraph Node2["qa-k3s-02 / nbig59 (10.43.98.253) — Worker"]
            T2["traefik (1 réplica)"]
            FE1["frontend (1 réplica)"]
            U1["ms-users (1 réplica)"]
            S2["ms-services (1 réplica)"]
            P1["ms-payments (1 réplica)"]
            G1["ms-matching-geo (1 réplica)"]
            L1["ms-intake-lakehouse (1 réplica)"]
            KE["kafka-exporter (1 réplica)"]
            PG0["StatefulSet: postgres-0 (PVC 5Gi)"]
            KF0["StatefulSet: kafka-0 (PVC 5Gi)"]
            RFS0["StatefulSet: rustfs-0 (PVC 5Gi)"]
            PROMT2["promtail (DaemonSet)"]
        end

        subgraph Node3["qa-k3s-03 / nbig65 (10.43.99.6) — Worker"]
            FE2["frontend (1 réplica)"]
            U2["ms-users (1 réplica)"]
            P2["ms-payments (1 réplica)"]
            G2["ms-matching-geo (1 réplica)"]
            MDB0["StatefulSet: mongodb-0 (PVC 5Gi)"]
            VLT0["StatefulSet: vault-0 (PVC 2Gi)"]
            PROMT3["promtail (DaemonSet)"]
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
    participant TR as Traefik Gateway
    participant MSU as ms-users
    participant MSG as ms-matching-geo
    participant MSS as ms-services
    participant KF as Apache Kafka
    participant MSP as ms-payments
    participant MSL as ms-intake-lakehouse
    participant RFS as RustFS (S3)

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

---

## 4. Resumen de Componentes de la Arquitectura

| Capa | Componente | Tecnología | Réplicas / Tipo | Responsabilidad Principal |
| :--- | :--- | :--- | :---: | :--- |
| **Borde** | `traefik` | Traefik v3.0 | 2 (`Deployment`) | Enrutamiento HTTP (`:80`), prioridades por prefijo (`/api/*` vs `/`) y métricas (`:8080`). |
| **Presentación** | `frontend` | Flutter Web 3.22 + Nginx | 2 (`Deployment`) | SPA multi-rol (Cliente, Técnico, Empresa) servida sin caché de Service Worker. |
| **Dominio** | `ms-users` | Java 21 / Spring Boot 3 | 2 (`Deployment`) | Autenticación JWT (RS256), perfiles, zonas, horarios, empresas (`seed-qa`), evaluaciones y reputación. |
| **Dominio** | `ms-services` | Java 21 / Spring Boot 3 | 2 (`Deployment`) | Solicitudes, oportunidades, postulaciones, cotizaciones, contratos, evidencias S3 y Outbox Relay. |
| **Dominio** | `ms-matching-geo` | Python 3.12 / FastAPI | 2 (`Deployment`) | Emparejamiento geoespacial (Haversine) y filtro horario coordinado con `ms-users`. |
| **Dominio** | `ms-payments` | C# / .NET 8 ASP.NET Core | 2 (`Deployment`) | Billetera digital, recargas, retiros, comisiones (15%), retención/liquidación por Kafka y reembolsos Admin. |
| **Analítica** | `ms-intake-lakehouse` | Go 1.22 | 1 (`Deployment`) | Consumidor multi-tópico de Kafka con validación JSON Schema 2020-12 e ingesta idempotente en S3 (`lakehouse`). |
| **Datos** | `postgres-0` | PostgreSQL 16 | 1 (`StatefulSet`) | Persistencia relacional transaccional (`ms_users`, `ms_services`, `ms_payments`) y tablas `outbox_events`. |
| **Mensajería** | `kafka-0` | Apache Kafka 3.9 (KRaft) | 1 (`StatefulSet`) | Bus de eventos (`fixia.services.service-requests`, `fixia.payments.events`, `fixia.users.evaluations`). |
| **Objetos S3** | `rustfs-0` | RustFS (API S3) | 1 (`StatefulSet`) | Almacenamiento de objetos compatible con S3 para fotos de evidencia (`evidences`) y Data Lakehouse (`lakehouse`). |
| **Secretos / NoSQL** | `vault-0` / `mongodb-0` | Vault 1.15 / MongoDB 7.0 | 1 c/u (`StatefulSet`) | Gestión de secretos e infraestructura documental aprovisionada en la capa de datos. |
| **Observabilidad** | `prometheus` / `loki` / `grafana` | Stack Grafana / Prometheus | Nodo `qa-obs-01` | Monitoreo de 23 targets (cAdvisor, Kubelet, Spring Actuator, .NET, Traefik, Kafka) y logs centralizados vía Promtail. |

