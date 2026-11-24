# Runbook Operativo — Infraestructura como Código (Ansible), CI/CD, Kafka, Seguridad y Cloudflare

Este manual documenta los procedimientos operativos estándar para aprovisionar, desplegar, monitorear y diagnosticar los ambientes de **Producción**, **QA**, **Observabilidad Central** y **Desarrollo Local** de la plataforma **Fixia**.

---

## 1. Mapa de Servidores yAccesos SSH

Desde el nodo coordinador **`nbig23` (`10.43.98.217`)**, el usuario `estudiante` cuenta con acceso SSH por llave (`~/.ssh/id_ed25519`) y `sudo` sin contraseña hacia los nodos de Producción:

| Ambiente | Hostname | IP | Alias Inventario Ansible | Comando Acceso Directo |
| :--- | :--- | :---: | :--- | :--- |
| **Coordinador / Observabilidad** | `nbig23` | `10.43.98.217` | `qa-obs-01` (grupo `observability`) | Local (`10.43.98.217`) |
| **Producción (App Worker 1)** | `nbig37` | `10.43.98.231` | `prod-k3s-01` (`k3s_servers[0]`) | `ssh estudiante@10.43.98.231` |
| **Producción (App Worker 2)** | `nbig50` | `10.43.98.244` | `prod-k3s-02` (`k3s_servers[1]`) | `ssh estudiante@10.43.98.244` |
| **Producción (Data Node)** | `nbig452` | `10.43.100.155` | `prod-k3s-03` (`k3s_servers[2]`) | `ssh estudiante@10.43.100.155` |
| **QA (Worker 1)** | `nbig17` | `10.43.98.211` | `qa-k3s-01` (`k3s_servers[0]`) | `ssh estudiante@10.43.98.211` |
| **QA (Worker 2)** | `nbig59` | `10.43.98.253` | `qa-k3s-02` (`k3s_servers[1]`) | `ssh estudiante@10.43.98.253` |
| **QA (Worker 3)** | `nbig65` | `10.43.99.6` | `qa-k3s-03` (`k3s_servers[2]`) | `ssh estudiante@10.43.99.6` |

---

## 2. Ejecución de Playbooks Ansible (`ms-orchestrator/ansible/`)

El directorio `ansible/` cuenta con dos inventarios completamente separados:
* **Producción:** `ansible/inventory/produccion/hosts.yml` (con variables en `ansible/inventory/produccion/group_vars/all/main.yml` y secretos cifrados con Ansible Vault en `vault.yml`).
* **QA:** `ansible/inventory/qa/hosts.yml` (o `ansible/inventory/qa.yml`).

### Orden Oficial de Ejecución de Playbooks (`01` a `12`)
```bash
cd /home/estudiante/arqui/ms-orchestrator/ansible

# 1. Preparación de nodos Ubuntu (paquetes, swap off, módulos kernel, sysctl)
ansible-playbook -i inventory/produccion/hosts.yml playbooks/01-prepare.yml

# 2. Bootstrap del clúster K3s HA (3 servidores con etcd embebido, labels workload=apps|data y taints)
ansible-playbook -i inventory/produccion/hosts.yml playbooks/02-k3s-bootstrap.yml

# 3. Stack de Observabilidad Central (Prometheus, Grafana, Loki, Promtail multi-ambiente y túneles Cloudflare)
ansible-playbook -i inventory/produccion/hosts.yml playbooks/04-observability.yml

# 4. API Gateway Traefik v3.3 (Middlewares OWASP ZAP, CORS, RateLimit, bloqueo /internal/**) y Túneles Cloudflare
ansible-playbook -i inventory/produccion/hosts.yml playbooks/05-traefik.yml
ansible-playbook -i inventory/produccion/hosts.yml playbooks/05b-cloudflared-api.yml

# 5. Almacenamiento y Capa de Datos Aislada en prod-k3s-03 (nbig452 - workload=data)
ansible-playbook -i inventory/produccion/hosts.yml playbooks/06-storage.yml
ansible-playbook -i inventory/produccion/hosts.yml playbooks/07-vault.yml
ansible-playbook -i inventory/produccion/hosts.yml playbooks/08-postgresql.yml
ansible-playbook -i inventory/produccion/hosts.yml playbooks/09-mongodb.yml
ansible-playbook -i inventory/produccion/hosts.yml playbooks/10-kafka.yml
ansible-playbook -i inventory/produccion/hosts.yml playbooks/10b-rustfs.yml

# 6. Namespace apps, ServiceAccount RBAC deployer, bases de datos y secretos JWT/S3
ansible-playbook -i inventory/produccion/hosts.yml playbooks/11-apps.yml
ansible-playbook -i inventory/produccion/hosts.yml playbooks/12-apps-bootstrap.yml
```

---

## 3. Operación de Despliegue Continuo (GitHub Actions Self-Hosted Runners)

En el servidor coordinador `10.43.98.217` corren dos servicios `systemd` independientes registrados a nivel de la organización `Grupo-Fixia`:

| Runner Systemd Service | Etiquetas GitHub Actions | Rama que Despliega | Kubeconfig Utilizado | Manifiesto Aplicado |
| :--- | :--- | :---: | :--- | :--- |
| `actions.runner.Grupo-Fixia.nbig23-qa.service` | `[self-hosted, qa]` | `Qa` (`cd.yml`) | `/home/estudiante/.kube/deployer.yaml` | `deploy/<servicio>.yaml` |
| `actions.runner.Grupo-Fixia.nbig23-prod.service` | `[self-hosted, prod]` | `main` (`cd-prod.yml`) | `/home/estudiante/.kube/deployer-prod.yaml` | `deploy/<servicio>-prod.yaml` |

### Comandos Útiles para los Runners y Kubectl
```bash
# Verificar estado de los runners en 10.43.98.217
systemctl status actions.runner.Grupo-Fixia.nbig23-qa.service
systemctl status actions.runner.Grupo-Fixia.nbig23-prod.service

# Consultar pods de aplicaciones en QA desde el coordinador
kubectl --kubeconfig=/home/estudiante/.kube/deployer.yaml get deployments,pods,svc -n apps -o wide

# Consultar pods de aplicaciones en Producción desde el coordinador
kubectl --kubeconfig=/home/estudiante/.kube/deployer-prod.yaml get deployments,pods,svc -n apps -o wide
```

---

## 4. Administración de los 4 Túneles HTTPS de Cloudflare

Los túneles Quick Tunnel de Cloudflare corren como `Deployments` de Kubernetes:

1. **En el Clúster de Producción (`10.43.98.231`):**
   * **Frontend (`namespace: apps`):** `deployment/cloudflared-frontend` → apunta a `http://frontend.apps.svc.cluster.local:80`
   * **API Gateway (`namespace: traefik`):** `deployment/cloudflared-api` → apunta a `http://traefik.traefik.svc.cluster.local:80`
   * **Consultar URLs actuales en Producción:**
     ```bash
     ssh estudiante@10.43.98.231 "sudo k3s kubectl logs -n apps deployment/cloudflared-frontend | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -n 1"
     ssh estudiante@10.43.98.231 "sudo k3s kubectl logs -n traefik deployment/cloudflared-api | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -n 1"
     ```
   * **Importante:** Si el pod `cloudflared-api` se recrea y cambia su URL `*.trycloudflare.com`, se debe actualizar el argumento de compilación `USERS_API_BASE_URL` en `ms-frontend/.github/workflows/ci-prod.yml` (o la variable de repositorio `PROD_BASE_URL` en GitHub) y disparar el pipeline `ci-prod` para que Flutter compile el nuevo dominio.

2. **En el Clúster de Observabilidad (`10.43.98.217`):**
   * **Grafana (`namespace: observability`):** `deployment/cloudflared-grafana` → apunta a `http://grafana.observability.svc.cluster.local:3000`
   * **Prometheus (`namespace: observability`):** `deployment/cloudflared-prometheus` → apunta a `http://prometheus.observability.svc.cluster.local:9090`
   * **Consultar URLs actuales en Observabilidad:**
     ```bash
     k3s kubectl logs -n observability deployment/cloudflared-grafana | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -n 1
     k3s kubectl logs -n observability deployment/cloudflared-prometheus | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -n 1
     ```

---

## 5. Operación de Apache Kafka (9 Tópicos) y PostgreSQL (Flyway)

### 5.1 Verificar los 9 Tópicos y Políticas de Compactación en Producción
```bash
ssh estudiante@10.43.98.231 "sudo k3s kubectl exec -n data kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe"
```
* **Tópicos con `cleanup.policy=compact` (Replicación de estado `GC-547`):**
  1. `fixia.users.technician-states`
  2. `fixia.users.company-states`
  3. `fixia.services.participations`
  4. `fixia.services.executor-workloads`
  5. `fixia.payments.held-services`
* **Tópico de sesiones revocadas:** `fixia.users.sessions`
* **Tópicos de eventos de dominio (consumidos por `ms-intake-lakehouse`):** `fixia.services.service-requests`, `fixia.payments.events`, `fixia.users.evaluations`.

### 5.2 Verificar Migraciones Flyway en PostgreSQL (`postgres-0`)
```bash
# Producción
ssh estudiante@10.43.98.231 "sudo k3s kubectl exec -n data postgres-0 -- psql -U postgres -d ms_users -c 'SELECT installed_rank, version, description, success FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 5;'"
ssh estudiante@10.43.98.231 "sudo k3s kubectl exec -n data postgres-0 -- psql -U postgres -d ms_services -c 'SELECT installed_rank, version, description, success FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 5;'"
```

---

## 6. Quality Gates de Cobertura y Seguridad

* **`ms-users`:** `mvn -B verify` (JaCoCo `>= 80%`) + Cifrado de credenciales `CredentialCipher.java` (`ENC:v1:`) + BCrypt costo 12.
* **`ms-services`:** `mvn -B verify` (JaCoCo `>= 85%`) + `server.tomcat.max-swallow-size: -1` para cargas `> 10 MB`.
* **`ms-matching-geo`:** `pytest --cov=src/app --cov-fail-under=85` + consumidor `confluent-kafka==2.6.1` + métricas Prometheus en `:9104`.
* **`ms-payments`:** `dotnet test` (xUnit contra PostgreSQL 16) + `PrometheusMetricsMiddleware` en `:9103`.
* **`ms-intake-lakehouse`:** `go test -v -coverprofile=coverage.out ./internal/...` (`>= 80%`) + esquemas JSON Draft 2020-12 sincronizados y `SessionTimeout: 6s`.
* **`ms-frontend`:** `flutter analyze` + `flutter test --coverage` (`>= 80%`) + interceptor `window.fetch` (`Uint8Array` / `string`) y `XMLHttpRequest` en `web/index.html`.
