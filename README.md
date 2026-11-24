# ms-orchestrator — Orquestación Multi-Ambiente (Producción, QA, Observabilidad y Desarrollo Local) — Fixia

Este repositorio centraliza la **Infraestructura como Código (Ansible + Kubernetes K3s HA)**, la **Observabilidad Multi-Ambiente (Prometheus, Grafana, Loki, Promtail)**, la **Seguridad de Borde (Traefik v3.3 OWASP + Cloudflare Zero-Trust Tunnels)** y el entorno de **Desarrollo Local (`docker-compose.yml`)** de la plataforma **Fixia**.

---

## 📚 Documentación Oficial de Arquitectura e Infraestructura (`docs/`)

Toda la documentación técnica actualizada se encuentra organizada en la carpeta [`docs/`](./docs/README.md):

1. **[Índice Maestro y Galería de Diagramas HLD (`docs/README.md`)](./docs/README.md)**
2. **[Diseño de Alto Nivel (HLD) — Arquitectura Lógica, Malla de Eventos Kafka y Topología Física (`docs/HLD-Arquitectura-e-Infraestructura.md`)](./docs/HLD-Arquitectura-e-Infraestructura.md)**
3. **[Estado Operativo e Inventario en Vivo de Producción, QA y Observabilidad (`docs/Estado-Infraestructura-Arquitectura-V4.md`)](./docs/Estado-Infraestructura-Arquitectura-V4.md)**
4. **[Runbook Operativo: Ansible IaC, CI/CD Runners, Kafka, Seguridad y Cloudflare (`docs/Runbook-Operacion-IaC-y-CICD.md`)](./docs/Runbook-Operacion-IaC-y-CICD.md)**
5. **[Visor HTML Interactivo de Diagramas HLD (`docs/hld-arquitectura-interactivo.html`)](./docs/hld-arquitectura-interactivo.html)**

---

## 🌐 Endpoints Activos por Ambiente

| Ambiente | Servicio | URL Pública HTTPS (Cloudflare) | URL Interna LAN (`10.43.98.0/22`) |
| :--- | :--- | :--- | :--- |
| **Producción** | **Frontend Web SPA (`ms-frontend`)** | https://hook-excellence-champion-wallet.trycloudflare.com | `http://10.43.98.231` / `http://10.43.98.244` |
| **Producción** | **API Gateway (`traefik`)** | https://fits-descending-section-constant.trycloudflare.com | `http://10.43.98.231/api/...` |
| **Observabilidad** | **Grafana (Dashboards Multi-Ambiente)** | https://logging-districts-beautiful-loose.trycloudflare.com | `http://10.43.98.217:3000` |
| **Observabilidad** | **Prometheus (47/47 Targets UP)** | https://europe-cattle-stays-ntsc.trycloudflare.com | `http://10.43.98.217:9090` |
| **QA** | **Frontend & API Gateway QA** | — *(Red interna LAN)* | `http://10.43.98.211` / `.253` / `10.43.99.6` |

---

## 💻 Entorno de Desarrollo Local (Docker Compose)

Para levantar toda la plataforma localmente (PostgreSQL x3, Apache Kafka 3.9 KRaft con inicialización automática de los **9 tópicos** en `kafka-init` con `cleanup.policy=compact`, RustFS S3 con `rustfs-init`, Traefik v3.6 y los 6 microservicios):

1. Ejecuta el script de inicialización:
   ```bash
   ./setup-dev.sh
   ```
   *(Clona los repositorios faltantes, genera `.env` con las claves RSA `JWT_PRIVATE_KEY` y `JWT_PUBLIC_KEY`, y levanta `docker compose --profile full up -d --build`).*

2. Para detener los contenedores:
   ```bash
   docker compose --profile full down
   ```
