# Documentación de Infraestructura y Arquitectura — Fixia Proyecto V4

> **Fecha y Hora de Extracción:** 2026-11-05 17:59 (Hora Local)  
> **Ambiente:** QA (Clúster K3s Multi-Nodo) + Servidor Central de Observabilidad  
> **Coordinador K3s:** `qa-k3s-01` (`10.43.98.211`) | **Observabilidad:** `qa-obs-01` (`10.43.98.217`)  
> **Estado General:** 100% Operativo — Todos los microservicios, bases de datos, bus Kafka y observabilidad en estado `Running` / `UP`.

---

## 1. Verificación del Despliegue de Frontend (`frontend-dfbb99586`)

### ¿Hubo Rollback o Error al reconstruir el Frontend?
**NO hubo rollback ni error.**
El deployment `frontend` se actualizó exitosamente a la revisión 12 (`Revision: 12`) con la imagen recién compilada desde la rama `Qa`:
- **Commit en Qa:** `26c4337f7157` (`promocion/GC-515-GC-514-front`: cancelar solicitud y cambiar dirección exacta).
- **Imagen Desplegada:** `ghcr.io/grupo-fixia/ms-frontend:26c4337f7157`
- **Estado de Pods:**
  - `pod/frontend-dfbb99586-h2ntc`: `1/1 Running`, `0 Restarts`, IP `10.244.1.57`, Nodo `nbig59`.
  - `pod/frontend-dfbb99586-zrrj4`: `1/1 Running`, `0 Restarts`, IP `10.244.1.56`, Nodo `nbig59`.
- **Réplicas Deseadas / Listas:** `2 / 2` (`UPDATED: 2`, `READY: 2`).

---

## 2. Microservicios y Frontend (`namespace: apps`)

### Pods en Ejecución
```text
NAME                                       READY   STATUS    RESTARTS   AGE     IP            NODE     NOMINATED NODE   READINESS GATES
pod/frontend-dfbb99586-h2ntc               1/1     Running   0          18m     10.244.1.57   nbig59   <none>           <none>
pod/frontend-dfbb99586-zrrj4               1/1     Running   0          18m     10.244.1.56   nbig59   <none>           <none>
pod/kafka-exporter-64d9bc5547-knnp4        1/1     Running   0          14d     10.244.1.16   nbig59   <none>           <none>
pod/ms-intake-lakehouse-7bddb8cd86-26bbv   1/1     Running   0          6h7m    10.244.1.53   nbig59   <none>           <none>
pod/ms-matching-geo-576ddfd96d-8wgql       1/1     Running   0          25h     10.244.3.47   nbig65   <none>           <none>
pod/ms-matching-geo-576ddfd96d-ks4tq       1/1     Running   0          25h     10.244.1.43   nbig59   <none>           <none>
pod/ms-payments-674fb45849-c9m69           1/1     Running   0          4h56m   10.244.0.53   nbig17   <none>           <none>
pod/ms-payments-674fb45849-jscbz           1/1     Running   0          4h56m   10.244.1.54   nbig59   <none>           <none>
pod/ms-services-5d5f56dbbc-ghzjw           1/1     Running   0          4h41m   10.244.0.54   nbig17   <none>           <none>
pod/ms-services-5d5f56dbbc-p9vs9           1/1     Running   0          4h43m   10.244.3.57   nbig65   <none>           <none>
pod/ms-users-b84c95c6b-dvqpj               1/1     Running   0          4h24m   10.244.0.55   nbig17   <none>           <none>
pod/ms-users-b84c95c6b-t5f96               1/1     Running   0          4h22m   10.244.1.55   nbig59   <none>           <none>
```

### Servicios de Red (`Service`) en `apps`
```text
NAME                          TYPE           CLUSTER-IP       EXTERNAL-IP                            PORT(S)          AGE   SELECTOR
service/frontend              ClusterIP      10.245.16.71     <none>                                 80/TCP           28d   app=frontend
service/kafka-exporter        LoadBalancer   10.245.15.32     10.43.98.211,10.43.98.253,10.43.99.6   9308:30142/TCP   14d   app=kafka-exporter
service/ms-intake-lakehouse   ClusterIP      10.245.81.117    <none>                                 8080/TCP         27h   app=ms-intake-lakehouse
service/ms-matching-geo       ClusterIP      10.245.231.101   <none>                                 8000/TCP         26h   app=ms-matching-geo
service/ms-payments           ClusterIP      10.245.49.24     <none>                                 8080/TCP         27h   app=ms-payments
service/ms-payments-metrics   LoadBalancer   10.245.245.148   10.43.98.211,10.43.98.253,10.43.99.6   9103:30666/TCP   27h   app=ms-payments
service/ms-services           ClusterIP      10.245.7.156     <none>                                 8080/TCP         14d   app=ms-services
service/ms-services-metrics   LoadBalancer   10.245.24.57     10.43.98.211,10.43.98.253,10.43.99.6   9102:30659/TCP   14d   app=ms-services
service/ms-users              ClusterIP      10.245.122.235   <none>                                 8080/TCP         28d   app=ms-users
service/ms-users-metrics      LoadBalancer   10.245.31.246    10.43.98.211,10.43.98.253,10.43.99.6   9101:30993/TCP   14d   app=ms-users
```

### Reglas de Enrutamiento Ingress (Traefik) en `apps`
```text
NAME                                        CLASS     HOSTS   ADDRESS   PORTS   AGE
ingress.networking.k8s.io/frontend          traefik   *                 80      28d
ingress.networking.k8s.io/ms-matching-geo   traefik   *                 80      26h
ingress.networking.k8s.io/ms-payments       traefik   *                 80      27h
ingress.networking.k8s.io/ms-services       traefik   *                 80      14d
ingress.networking.k8s.io/ms-users          traefik   *                 80      28d
```

### Imágenes y Versiones Desplegadas (`Deployments`)
| Nombre del Microservicio | Imagen Oficial en GHCR | Réplicas Listas |
| :--- | :--- | :---: |
| **`frontend`** | `ghcr.io/grupo-fixia/ms-frontend:26c4337f7157` | **2/2** |
| **`ms-users`** | `ghcr.io/grupo-fixia/ms-users:60477861caaf` | **2/2** |
| **`ms-services`** | `ghcr.io/grupo-fixia/ms-services:1218b914cbda` | **2/2** |
| **`ms-payments`** | `ghcr.io/grupo-fixia/ms-payments:e5511e93f732` | **2/2** |
| **`ms-matching-geo`** | `ghcr.io/grupo-fixia/ms-matching-geo:dab3928747b2` | **2/2** |
| **`ms-intake-lakehouse`** | `ghcr.io/grupo-fixia/ms-intake-lakehouse:41eb263888f1` | **1/1** |
| **`kafka-exporter`** | `danielqsj/kafka-exporter:v1.8.0` | **1/1** |

---

## 3. Capa de Datos: Persistencia, Eventos y Objetos (`namespace: data`)

### Pods de Datos
```text
NAME                    READY   STATUS      RESTARTS   AGE    IP            NODE     NOMINATED NODE   READINESS GATES
pod/kafka-0             1/1     Running     0          28d    10.244.0.15   nbig17   <none>           <none>
pod/mongodb-0           1/1     Running     0          28d    10.244.3.9    nbig65   <none>           <none>
pod/postgres-0          1/1     Running     0          28d    10.244.1.6    nbig59   <none>           <none>
pod/rustfs-0            1/1     Running     0          2d4h   10.244.3.37   nbig65   <none>           <none>
pod/rustfs-init-zjgdj   0/1     Completed   0          2d4h   10.244.3.38   nbig65   <none>           <none>
pod/vault-0             1/1     Running     0          28d    10.244.3.7    nbig65   <none>           <none>
```

### Servicios de Datos
```text
NAME               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE    SELECTOR
service/kafka      ClusterIP   None             <none>        9092/TCP            28d    app=kafka
service/mongodb    ClusterIP   10.245.144.247   <none>        27017/TCP           28d    app=mongodb
service/postgres   ClusterIP   10.245.8.207     <none>        5432/TCP            28d    app=postgres
service/rustfs     ClusterIP   10.245.216.63    <none>        9000/TCP,9001/TCP   2d4h   app=rustfs
service/vault      ClusterIP   10.245.29.138    <none>        8200/TCP            28d    app=vault
```

### Volúmenes Persistentes (PVC)
```text
NAME                                    STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/data-kafka-0      Bound    pvc-b43f68fd-b857-4c8d-804a-bb227f18deb7   8Gi        RWO            local-path     28d
persistentvolumeclaim/data-mongodb-0    Bound    pvc-6a91b3d9-5e12-4e11-96e8-99d6876ef94a   5Gi        RWO            local-path     28d
persistentvolumeclaim/data-postgres-0   Bound    pvc-56fa2f28-d4c0-4113-a39f-44eef3bb4fe1   5Gi        RWO            local-path     28d
persistentvolumeclaim/data-rustfs-0     Bound    pvc-e0c40ea6-9ef2-4507-afbb-7ef6f9b9821b   5Gi        RWO            local-path     2d4h
persistentvolumeclaim/data-vault-0      Bound    pvc-c32900ef-dabb-471d-a018-ff275d420c8a   1Gi        RWO            local-path     28d
```

---

## 4. Borde y Enrutamiento: Traefik (`namespace: traefik`)

```text
NAME                          READY   STATUS    RESTARTS   AGE   IP            NODE     NOMINATED NODE   READINESS GATES
pod/traefik-7bbb4dc5c-9h8rl   1/1     Running   0          25h   10.244.3.50   nbig65   <none>           <none>
pod/traefik-7bbb4dc5c-h845r   1/1     Running   0          25h   10.244.0.46   nbig17   <none>           <none>

NAME              TYPE           CLUSTER-IP       EXTERNAL-IP                            PORT(S)                                     AGE   SELECTOR
service/traefik   LoadBalancer   10.245.138.244   10.43.98.211,10.43.98.253,10.43.99.6   80:30207/TCP,443:30516/TCP,8080:30565/TCP   28d   app=traefik
```

---

## 5. Observabilidad Centralizada y Agentes de Logs

### Agentes Promtail (DaemonSet en QA — `namespace: observability`)
```text
NAME             READY   STATUS    RESTARTS   AGE   IP            NODE     NOMINATED NODE   READINESS GATES
promtail-2lst2   1/1     Running   0          15d   10.244.0.20   nbig17   <none>           <none>
promtail-b6dhn   1/1     Running   0          15d   10.244.1.14   nbig59   <none>           <none>
promtail-qn985   1/1     Running   0          15d   10.244.3.18   nbig65   <none>           <none>
```

### Targets de Prometheus (`qa-obs-01:9090`) — 23 de 23 UP (100% Saludables)
```text
HEALTH  JOB                     SCRAPE_URL
up      loki                    http://loki.observability.svc.cluster.local:3100/metrics
up      obs-k3s-node            https://kubernetes.default.svc:443/api/v1/nodes/nbig23/proxy/metrics/cadvisor
up      obs-k3s-pods            http://10.246.0.15:3100/metrics
up      obs-k3s-pods            http://10.246.0.23:9090/metrics
up      prometheus              http://localhost:9090/metrics
up      qa-k3s-nodes-cadvisor   https://10.43.99.6:10250/metrics/cadvisor
up      qa-k3s-nodes-cadvisor   https://10.43.98.211:10250/metrics/cadvisor
up      qa-k3s-nodes-cadvisor   https://10.43.98.253:10250/metrics/cadvisor
up      qa-k3s-nodes-kubelet    https://10.43.98.253:10250/metrics
up      qa-k3s-nodes-kubelet    https://10.43.99.6:10250/metrics
up      qa-k3s-nodes-kubelet    https://10.43.98.211:10250/metrics
up      qa-kafka                http://10.43.99.6:9308/metrics
up      qa-kafka                http://10.43.98.211:9308/metrics
up      qa-kafka                http://10.43.98.253:9308/metrics
up      qa-ms-services          http://10.43.98.211:9102/actuator/prometheus
up      qa-ms-services          http://10.43.98.253:9102/actuator/prometheus
up      qa-ms-services          http://10.43.99.6:9102/actuator/prometheus
up      qa-ms-users             http://10.43.98.211:9101/actuator/prometheus
up      qa-ms-users             http://10.43.98.253:9101/actuator/prometheus
up      qa-ms-users             http://10.43.99.6:9101/actuator/prometheus
up      qa-traefik              http://10.43.98.211:8080/metrics
up      qa-traefik              http://10.43.98.253:8080/metrics
up      qa-traefik              http://10.43.99.6:8080/metrics
```

---

## 6. Bus de Eventos Kafka, Grupos de Consumidores y Persistencia

### Tópicos Creados en Kafka
```text
__consumer_offsets
fixia.payments.events
fixia.services.service-requests
fixia.users.evaluations
test
```

### Estado de los Grupos de Consumidores (LAG = 0 en todos)
```text
GROUP               TOPIC                           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG  CLIENT-ID
ms-intake-lakehouse fixia.users.evaluations         0          13              13              0    kafka-go
ms-intake-lakehouse fixia.users.evaluations         1          6               6               0    kafka-go
ms-intake-lakehouse fixia.users.evaluations         2          3               3               0    kafka-go
ms-intake-lakehouse fixia.payments.events           0          126             126             0    kafka-go
ms-intake-lakehouse fixia.services.service-requests 0          485             485             0    kafka-go
ms-payments         fixia.services.service-requests 0          485             485             0    rdkafka
ms-services         fixia.payments.events           0          126             126             0    consumer-ms-services
```

### Bases de Datos en PostgreSQL 16
```text
    Name     |    Owner    | Encoding | Collate    | Ctype      | Access privileges
-------------+-------------+----------+------------+------------+-------------------
 ms_payments | ms_payments | UTF8     | en_US.utf8 | en_US.utf8 | 
 ms_services | ms_services | UTF8     | en_US.utf8 | en_US.utf8 | 
 ms_users    | ms_users    | UTF8     | en_US.utf8 | en_US.utf8 | 
 postgres    | postgres    | UTF8     | en_US.utf8 | en_US.utf8 | 
```

### Métricas de Ingesta del Data Lakehouse (`ms-intake-lakehouse`)
```json
{
  "processed_total": 633,
  "stored_total": 630,
  "duplicates_total": 0,
  "quarantined_total": 3,
  "errors_total": 0
}
```

---

## 7. Muestras de Logs Recientes por Microservicio (Estado Saludable)

### `ms-users`
```text
INFO 1 --- [ms-users] o.s.b.w.embedded.tomcat.TomcatWebServer : Tomcat started on port 8080 (http)
INFO 1 --- [ms-users] com.fixia.users.Application : Started Application in 17.456 seconds
WARN 1 --- [ms-users] com.fixia.users.config.QaSeedLoader : Perfil seed-qa activo: se cargan cuentas de QA con contraseña conocida.
INFO 1 --- [ms-users] com.fixia.users.config.QaSeedLoader : Datos de QA de empresas y técnicos cargados (seed/qa_empresas.sql).
Microservicio ms-users iniciado correctamente.
```

### `ms-services`
```text
INFO 1 --- [ms-services] o.s.b.w.embedded.tomcat.TomcatWebServer : Tomcat started on port 8080 (http)
INFO 1 --- [ms-services] c.fixia.services.ServicesApplication : Started ServicesApplication in 16.294 seconds
INFO 1 --- [ms-services] o.a.k.c.c.internals.ConsumerCoordinator : [Consumer clientId=consumer-ms-services-1] Subscribed to topic(s): fixia.payments.events
Microservicio ms-services iniciado correctamente.
```

### `ms-payments`
```text
info: Microsoft.AspNetCore.Hosting.Diagnostics[2]
      Request finished HTTP/1.1 GET http://10.244.1.54:8080/health - 200 - application/json;+charset=utf-8 0.2652ms
info: Microsoft.AspNetCore.Hosting.Diagnostics[2]
      Request finished HTTP/1.1 GET http://10.244.0.53:8080/health - 200 - application/json;+charset=utf-8 0.7625ms
```

### `ms-matching-geo`
```text
INFO: 10.244.3.1:49688 - "GET /health HTTP/1.1" 200 OK
INFO: 10.244.1.1:55434 - "GET /health HTTP/1.1" 200 OK
```

### `ms-intake-lakehouse`
```text
2026/11/05 22:57:02 Evento persistido exitosamente en RustFS: eventId=4dda202a-..., tipo=servicio.contratado, seq=7, partition=0, offset=481
2026/11/05 22:57:02 Evento persistido exitosamente en RustFS: eventId=293d48b8-..., tipo=pago.procesado, seq=2, partition=0, offset=124
2026/11/05 22:57:29 Evento persistido exitosamente en RustFS: eventId=9086960e-..., tipo=servicio.iniciado, seq=8, partition=0, offset=482
2026/11/05 22:57:38 Evento persistido exitosamente en RustFS: eventId=c3010a24-..., tipo=servicio.finalizado, seq=9, partition=0, offset=483
2026/11/05 22:57:47 Evento persistido exitosamente en RustFS: eventId=c542acff-..., tipo=pago.completado, seq=3, partition=0, offset=125
2026/11/05 22:57:47 Evento persistido exitosamente en RustFS: eventId=c10f9e98-..., tipo=servicio.cerrado, seq=10, partition=0, offset=484
```

