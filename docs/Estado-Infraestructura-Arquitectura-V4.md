# Documentación de Infraestructura y Estado Operativo — Plataforma Fixia (Producción, QA y Observabilidad)

> **Fecha de Corte y Verificación en Vivo:** 2026-11-24  
> **Ambientes Documentados:**
> 1. **Clúster K3s HA de Producción:** `prod-k3s-01` (`10.43.98.231` / `nbig37`), `prod-k3s-02` (`10.43.98.244` / `nbig50`), `prod-k3s-03` (`10.43.100.155` / `nbig452`).
> 2. **Clúster K3s HA de QA:** `qa-k3s-01` (`10.43.98.211` / `nbig17`), `qa-k3s-02` (`10.43.98.253` / `nbig59`), `qa-k3s-03` (`10.43.99.6` / `nbig65`).
> 3. **Nodo Central de Orquestación, CI/CD y Observabilidad:** `qa-obs-01` (`10.43.98.217` / `nbig23`).
> **Estado General:** **100% Operativo** — Todos los nodos `Ready`, todos los pods en `Running`, las migraciones Flyway `V14` (`ms_users`) y `V19` (`ms_services`) aplicadas, los 9 tópicos de Kafka activos (5 con `cleanup.policy=compact`), y **47 de 47 targets de Prometheus en estado `UP`**.

---

## 1. Endpoints Públicos y Internos por Ambiente

| Ambiente | Servicio / Punto de Entrada | URL / Endpoint | Protocolo y Seguridad |
| :--- | :--- | :--- | :--- |
| **Producción (Público)** | **Frontend Web SPA (`ms-frontend`)** | `https://hook-excellence-champion-wallet.trycloudflare.com` | HTTPS (`TLS 1.3` vía Cloudflare Tunnel → `service/frontend:80`) |
| **Producción (Público)** | **API Gateway (`traefik`)** | `https://fits-descending-section-constant.trycloudflare.com` | HTTPS (`TLS 1.3` vía Cloudflare Tunnel → `service/traefik:80`) |
| **Producción (LAN)** | **API Gateway & Frontend (LAN)** | `http://10.43.98.231` / `http://10.43.98.244` | HTTP interno balanceado por `ServiceLB` |
| **QA (LAN)** | **API Gateway & Frontend (LAN)** | `http://10.43.98.211` / `http://10.43.98.253` / `http://10.43.99.6` | HTTP interno balanceado por `ServiceLB` |
| **Observabilidad (Público)** | **Grafana (Dashboards Multi-Ambiente)** | `https://logging-districts-beautiful-loose.trycloudflare.com` | HTTPS (`TLS 1.3` vía Cloudflare Tunnel → `service/grafana:3000`) |
| **Observabilidad (Público)** | **Prometheus (Métricas Multi-Clúster)** | `https://europe-cattle-stays-ntsc.trycloudflare.com` | HTTPS (`TLS 1.3` vía Cloudflare Tunnel → `service/prometheus:9090`) |
| **Observabilidad (LAN)** | **Grafana (Dashboards Multi-Ambiente)** | `http://10.43.98.217:3000` | Selector dinámico `$environment` (`qa` / `production`) |
| **Observabilidad (LAN)** | **Prometheus (Métricas Multi-Clúster)** | `http://10.43.98.217:9090` | 47 Targets activos (`UP`) |
| **Observabilidad (LAN)** | **Grafana Loki (Agregación de Logs)** | `http://10.43.98.217:3100` | Recibe logs de los 6 DaemonSets `promtail` |

---

## 2. Estado en Vivo del Clúster de PRODUCCIÓN (`v1.37.1+k3s1`)

### 2.1 Nodos del Clúster y Aislamiento de Cargas (`workload=apps` vs. `workload=data`)
En Producción se implementó **aislamiento físico de cargas**:
* Los nodos `nbig37` (`10.43.98.231`) y `nbig50` (`10.43.98.244`) tienen la etiqueta **`workload=apps`** y alojan exclusivamente los microservicios stateless y el borde.
* El nodo `nbig452` (`10.43.100.155`) tiene la etiqueta **`workload=data`** y el taint **`workload=data:NoSchedule`**, garantizando que sólo los 5 StatefulSets de persistencia (`postgres-0`, `kafka-0`, `rustfs-0`, `mongodb-0`, `vault-0`) se ejecuten en él.

```text
NAME      STATUS   ROLES                VERSION        INTERNAL-IP     OS-IMAGE             CONTAINER-RUNTIME         WORKLOAD LABEL & TAINT
nbig37    Ready    control-plane,etcd   v1.37.1+k3s1   10.43.98.231    Ubuntu 22.04.5 LTS   containerd://2.3.4-k3s1   workload=apps
nbig50    Ready    control-plane,etcd   v1.37.1+k3s1   10.43.98.244    Ubuntu 22.04.5 LTS   containerd://2.3.4-k3s1   workload=apps
nbig452   Ready    control-plane,etcd   v1.37.1+k3s1   10.43.100.155   Ubuntu 22.04.5 LTS   containerd://2.3.4-k3s1   workload=data (Taint: workload=data:NoSchedule)
```

### 2.2 Microservicios y Frontend en Producción (`namespace: apps`)

#### Deployments e Imágenes Activas (Rama `main`)
| Deployment | Imagen Desplegada (GHCR) | Réplicas Listas | Nodo Réplica 1 | Nodo Réplica 2 |
| :--- | :--- | :---: | :---: | :---: |
| **`frontend`** | `ghcr.io/grupo-fixia/ms-frontend:bafc723f4d51` | **2/2** | `nbig37` (`10.244.0.38`) | `nbig50` (`10.244.1.43`) |
| **`ms-users`** | `ghcr.io/grupo-fixia/ms-users:236f5a7d0119` | **2/2** | `nbig37` (`10.244.0.35`) | `nbig50` (`10.244.1.41`) |
| **`ms-services`** | `ghcr.io/grupo-fixia/ms-services:197642a78537` | **2/2** | `nbig37` (`10.244.0.39`) | `nbig50` (`10.244.1.44`) |
| **`ms-payments`** | `ghcr.io/grupo-fixia/ms-payments:cd15779e1de1` | **2/2** | `nbig37` (`10.244.0.33`) | `nbig50` (`10.244.1.39`) |
| **`ms-matching-geo`** | `ghcr.io/grupo-fixia/ms-matching-geo:202e0e2ed403` | **2/2** | `nbig37` (`10.244.0.31`) | `nbig50` (`10.244.1.37`) |
| **`ms-intake-lakehouse`** | `ghcr.io/grupo-fixia/ms-intake-lakehouse:fd6f248ce16e` | **1/1** | `nbig37` (`10.244.0.36`) | — |
| **`cloudflared-frontend`** | `cloudflare/cloudflared:latest` | **1/1** | `nbig50` (`10.244.1.25`) | — |
| **`kafka-exporter`** | `danielqsj/kafka-exporter:v1.8.0` | **1/1** | `nbig50` (`10.244.1.6`) | — |

#### Servicios de Red y Exposición de Métricas en Producción (`namespace: apps`)
```text
NAME                              TYPE           CLUSTER-IP       EXTERNAL-IP                 PORT(S)          SELECTOR
service/frontend                  ClusterIP      10.245.96.205    <none>                      80/TCP           app=frontend
service/ms-users                  ClusterIP      10.245.224.138   <none>                      8080/TCP         app=ms-users
service/ms-users-metrics          LoadBalancer   10.245.106.68    10.43.98.231,10.43.98.244   9101:30776/TCP   app=ms-users
service/ms-services               ClusterIP      10.245.177.49    <none>                      8080/TCP         app=ms-services
service/ms-services-metrics       LoadBalancer   10.245.160.231   10.43.98.231,10.43.98.244   9102:30458/TCP   app=ms-services
service/ms-payments               ClusterIP      10.245.138.40    <none>                      8080/TCP         app=ms-payments
service/ms-payments-metrics       LoadBalancer   10.245.193.209   10.43.98.231,10.43.98.244   9103:32063/TCP   app=ms-payments
service/ms-matching-geo           ClusterIP      10.245.124.137   <none>                      8000/TCP         app=ms-matching-geo
service/ms-matching-geo-metrics   LoadBalancer   10.245.16.249    10.43.98.231,10.43.98.244   9104:30450/TCP   app=ms-matching-geo
service/ms-intake-lakehouse       ClusterIP      10.245.211.228   <none>                      8080/TCP         app=ms-intake-lakehouse
service/kafka-exporter            LoadBalancer   10.245.39.22     10.43.98.231,10.43.98.244   9308:31924/TCP   app=kafka-exporter
```

### 2.3 Capa de Datos Aislada en Producción (`namespace: data` en nodo `nbig452`)
```text
NAME                    READY   STATUS      RESTARTS   IP            NODE      PVC ASOCIADO          CAPACIDAD   STORAGECLASS
pod/postgres-0          1/1     Running     0          10.244.2.7    nbig452   data-postgres-0       5Gi         local-path
pod/kafka-0             1/1     Running     0          10.244.2.11   nbig452   data-kafka-0          8Gi         local-path
pod/rustfs-0            1/1     Running     0          10.244.2.14   nbig452   data-rustfs-0         5Gi         local-path
pod/mongodb-0           1/1     Running     0          10.244.2.9    nbig452   data-mongodb-0        5Gi         local-path
pod/vault-0             1/1     Running     0          10.244.2.5    nbig452   data-vault-0          1Gi         local-path
pod/rustfs-init-k2ckf   0/1     Completed   0          10.244.2.12   nbig452   (Job inicializador)   —           —
```

### 2.4 Borde, API Gateway y Seguridad OWASP (`namespace: traefik`)
```text
NAME                                  READY   STATUS    RESTARTS   IP            NODE     ROL
pod/traefik-8cb8956fb-hjw2j           1/1     Running   0          10.244.1.27   nbig50   API Gateway Réplica 1
pod/traefik-8cb8956fb-pnf8w           1/1     Running   0          10.244.1.28   nbig50   API Gateway Réplica 2
pod/cloudflared-api-795b96668-gvg6v   1/1     Running   0          10.244.1.26   nbig50   Túnel HTTPS API Gateway
```
* **Endurecimiento de Seguridad Activo en Producción y QA:**
  1. **Cifrado de Credenciales en Payload (`ENC:v1:<nonce_hex>:<ciphertext_b64>`):** El interceptor en `ms-frontend/web/index.html` intercepta tanto `window.fetch` (cuerpos `Uint8Array` y `string`) como `XMLHttpRequest.prototype.send`, cifrando el campo `password` con SHA-256 CTR y nonce aleatorio de 128 bits antes de salir del navegador. `ms-users` (`CredentialCipher.java`) lo descifra en memoria antes de validar el hash **BCrypt costo 12**.
  2. **Cabeceras OWASP ZAP en Traefik (`ConfigMap/traefik-dynamic-config`) y Nginx (`ms-frontend/nginx.conf`):** `Content-Security-Policy`, `Strict-Transport-Security` (HSTS), `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`, `Cache-Control: no-store`, ocultación de versión (`server_tokens off`) y CORS restringido a orígenes autorizados.
  3. **Bloqueo Perimetral de Rutas Internas:** La regla `PathPrefix('/internal')` en Traefik tiene prioridad `1000` y aplica el middleware `block-internal` (rechazo inmediato en el borde).

---

## 3. Malla de Eventos Apache Kafka (9 Tópicos) y Migraciones Flyway

### 3.1 Los 9 Tópicos en Producción y QA (`kafka-0`)
| Tópico | Particiones | Política (`cleanup.policy`) | Productor | Consumidores | Propósito |
| :--- | :---: | :---: | :--- | :--- | :--- |
| `fixia.users.technician-states` | `1` | **`compact`** | `ms-users` | `ms-services`, `ms-matching-geo` | Réplica del perfil, categorías, zona, horario, reputación y empresa de cada técnico (`GC-547`). |
| `fixia.users.company-states` | `1` | **`compact`** | `ms-users` | `ms-services` | Réplica del estado, nombre comercial y reputación de cada empresa (`GC-547`). |
| `fixia.services.participations` | `1` | **`compact`** | `ms-services` | `ms-users` | Réplica de contratos cerrados (`clientId`, `providerId`, `executorId`) para validar quién puede evaluar (`GC-547`). |
| `fixia.services.executor-workloads` | `1` | **`compact`** | `ms-services` | `ms-users` | Réplica de carga activa de técnicos de empresa para validar desvinculaciones (`GC-547`). |
| `fixia.payments.held-services` | `1` | **`compact`** | `ms-payments` | `ms-users` | Réplica de servicios con saldo retenido por prestador (`GC-547`). |
| `fixia.users.sessions` | `1` | `delete` (`24h`) | `ms-users` (`500ms` relay) | `ms-services`, `ms-payments`, `ms-matching-geo` | Propagación inmediata de `sesion.revocada` (`jti` y `expiresAt`) para revocación local sin llamar a `ms-users`. |
| `fixia.services.service-requests` | `3` | `delete` (`1GB`) | `ms-services` | `ms-payments`, `ms-intake-lakehouse` | Eventos de dominio del ciclo de vida del servicio (`solicitud.publicada`, `solicitud.cancelada`, `cotizacion.enviada`, `servicio.contratado`, `servicio.iniciado`, `servicio.finalizado`, `servicio.cerrado`, etc.). |
| `fixia.payments.events` | `3` | `delete` (`1GB`) | `ms-payments` | `ms-services`, `ms-intake-lakehouse` | Eventos de dominio de pagos (`pago.creado`, `pago.procesado`, `pago.fallido`, `pago.completado`, `pago.reembolsado`). |
| `fixia.users.evaluations` | `3` | `delete` (`1GB`) | `ms-users` | `ms-intake-lakehouse` | Eventos de dominio de usuarios (`evaluacion.registrada`, `empresa.tecnico_vinculado`, `empresa.tecnico_desvinculado`). |

### 3.2 Historial de Migraciones Flyway Verificado en Producción y QA (`postgres-0`)
* **Base de datos `ms_users`:** Hasta **`V14__state_replication` (`success = t`)**.
* **Base de datos `ms_services`:** Hasta **`V19__state_replication` (`success = t`)**.
* **Base de datos `ms_payments`:** Migraciones EF Core 8 aplicadas automáticamente al inicio (`DatabaseMigrator.ApplyMigrationsAsync`).

---

## 4. Estado en Vivo del Clúster de QA

### Deployments e Imágenes Activas en QA (Rama `Qa`)
| Deployment | Imagen Desplegada (GHCR) | Réplicas Listas |
| :--- | :--- | :---: |
| **`frontend`** | `ghcr.io/grupo-fixia/ms-frontend:bafc723f4d51` | **2/2** |
| **`ms-users`** | `ghcr.io/grupo-fixia/ms-users:556ccf63981f` | **2/2** |
| **`ms-services`** | `ghcr.io/grupo-fixia/ms-services:ac127d97f8a3` | **2/2** |
| **`ms-payments`** | `ghcr.io/grupo-fixia/ms-payments:fc71baaf2bf3` | **2/2** |
| **`ms-matching-geo`** | `ghcr.io/grupo-fixia/ms-matching-geo:552755ebfcd0` | **2/2** |
| **`ms-intake-lakehouse`** | `ghcr.io/grupo-fixia/ms-intake-lakehouse:b4e660fec8da` | **1/1** |
| **`kafka-exporter`** | `danielqsj/kafka-exporter:v1.8.0` | **1/1** |

---

## 5. Observabilidad Multi-Ambiente (`10.43.98.217:9090`) — 47 / 47 Targets `UP`

Todos los microservicios exponen métricas HTTP en formato Prometheus con plantillas de ruta normalizadas (sin `uri="UNKNOWN"`):

```text
TOTAL TARGETS: 47 | UP: 47 (100% Saludables)

STATE | ENVIRONMENT   | JOB                    | SCRAPE_URL
up    | observability | loki                   | http://loki.observability.svc.cluster.local:3100/metrics
up    | observability | obs-k3s-node           | https://kubernetes.default.svc:443/api/v1/nodes/nbig23/proxy/metrics/cadvisor
up    | observability | obs-k3s-pods           | http://10.246.0.15:3100/metrics
up    | observability | obs-k3s-pods           | http://10.246.0.30:9090/metrics
up    | observability | prometheus             | http://localhost:9090/metrics
up    | production    | prod-k3s-nodes-cadvisor| https://10.43.98.231:10250/metrics/cadvisor, https://10.43.98.244:10250/metrics/cadvisor, https://10.43.100.155:10250/metrics/cadvisor
up    | production    | prod-k3s-nodes-kubelet | https://10.43.98.231:10250/metrics, https://10.43.98.244:10250/metrics, https://10.43.100.155:10250/metrics
up    | production    | prod-traefik           | http://10.43.98.231:8080/metrics, http://10.43.98.244:8080/metrics
up    | production    | prod-kafka             | http://10.43.98.231:9308/metrics, http://10.43.98.244:9308/metrics
up    | production    | prod-ms-users          | http://10.43.98.231:9101/actuator/prometheus, http://10.43.98.244:9101/actuator/prometheus
up    | production    | prod-ms-services       | http://10.43.98.231:9102/actuator/prometheus, http://10.43.98.244:9102/actuator/prometheus
up    | production    | prod-ms-payments       | http://10.43.98.231:9103/actuator/prometheus, http://10.43.98.244:9103/actuator/prometheus
up    | production    | prod-ms-matching-geo   | http://10.43.98.231:9104/actuator/prometheus, http://10.43.98.244:9104/actuator/prometheus
up    | qa            | qa-k3s-nodes-cadvisor  | https://10.43.98.211:10250/metrics/cadvisor, https://10.43.98.253:10250/metrics/cadvisor, https://10.43.99.6:10250/metrics/cadvisor
up    | qa            | qa-k3s-nodes-kubelet   | https://10.43.98.211:10250/metrics, https://10.43.98.253:10250/metrics, https://10.43.99.6:10250/metrics
up    | qa            | qa-traefik             | http://10.43.98.211:8080/metrics, http://10.43.98.253:8080/metrics, http://10.43.99.6:8080/metrics
up    | qa            | qa-kafka               | http://10.43.98.211:9308/metrics, http://10.43.98.253:9308/metrics, http://10.43.99.6:9308/metrics
up    | qa            | qa-ms-users            | http://10.43.98.211:9101/actuator/prometheus, http://10.43.98.253:9101/actuator/prometheus, http://10.43.99.6:9101/actuator/prometheus
up    | qa            | qa-ms-services         | http://10.43.98.211:9102/actuator/prometheus, http://10.43.98.253:9102/actuator/prometheus, http://10.43.99.6:9102/actuator/prometheus
up    | qa            | qa-ms-payments         | http://10.43.98.211:9103/actuator/prometheus, http://10.43.98.253:9103/actuator/prometheus, http://10.43.99.6:9103/actuator/prometheus
up    | qa            | qa-ms-matching-geo     | http://10.43.98.211:9104/actuator/prometheus, http://10.43.98.253:9104/actuator/prometheus, http://10.43.99.6:9104/actuator/prometheus
```

---

## 6. Automatización IaC (Ansible) y Pipelines CI/CD Duales

### 6.1 Estructura de Ansible en `ms-orchestrator/ansible/`
* **Inventario de QA:** `ansible/inventory/hosts.yml` (`qa-k3s-01..03` + `qa-obs-01`).
* **Inventario de Producción:** `ansible/inventory/produccion/hosts.yml` (`prod-k3s-01..03` + `qa-obs-01`) con variables cifradas en `ansible/inventory/produccion/group_vars/all/vault.yml`.
* **Playbooks parametrizados (`01` a `12`):**
  * `01-base.yml`: Preparación del SO, módulos kernel, `sysctl`, swap off.
  * `02-k3s-bootstrap.yml`: Inicialización del clúster HA con `etcd` embebido, etiquetado de nodos (`workload=apps`, `workload=data`) y taints.
  * `04-observability.yml`: Despliegue de Prometheus, Grafana, Loki y DaemonSets Promtail multi-ambiente.
  * `05-traefik.yml` y `05b-cloudflared-api.yml`: API Gateway Traefik v3.3 con middlewares OWASP/CORS/RateLimit y túneles Cloudflare.
  * `06-storage.yml` a `10b-rustfs.yml`: Despliegue de Vault, PostgreSQL 16, MongoDB 7, Apache Kafka 3.8 KRaft (con creación de los 9 tópicos y `cleanup.policy=compact`) y RustFS S3.
  * `11-apps.yml` y `12-apps-bootstrap.yml`: Creación de bases de datos, secretos, claves RSA JWT y ServiceAccount RBAC `deployer` para CI/CD.

### 6.2 Flujo CI/CD por Ambiente en los 6 Repositorios
| Ambiente | Rama Git | Workflow CI | Quality Gate en CI | Workflow CD | Runner Self-Hosted (`10.43.98.217`) | Kubeconfig y Manifiesto |
| :--- | :---: | :---: | :--- | :---: | :--- | :--- |
| **QA** | `Qa` | `ci.yml` | • `ms-users`: `mvn -B verify` (JaCoCo `>= 80%`)<br/>• `ms-services`: `mvn -B verify` (JaCoCo `>= 85%`)<br/>• `ms-matching-geo`: `pytest --cov-fail-under=85`<br/>• `ms-intake-lakehouse`: `go test -cover` (`>= 80%`)<br/>• `ms-frontend`: `flutter test --coverage` (`>= 80%`)<br/>• `ms-payments`: `dotnet test` (xUnit + PostgreSQL 16) | `cd.yml` | `actions.runner.Grupo-Fixia.nbig23-qa.service` (`[self-hosted, qa]`) | `~/.kube/deployer.yaml` → `deploy/<servicio>.yaml` |
| **Producción** | `main` | `ci-prod.yml` | Mismo Quality Gate estricto + Build Docker multi-stage con `USERS_API_BASE_URL` apuntando al API Gateway HTTPS de Producción | `cd-prod.yml` | `actions.runner.Grupo-Fixia.nbig23-prod.service` (`[self-hosted, prod]`) | `~/.kube/deployer-prod.yaml` → `deploy/<servicio>-prod.yaml` |
