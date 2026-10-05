# ms-orchestrator

Este repositorio contiene la orquestación principal (Docker Compose) y los scripts de inicialización para el entorno de desarrollo local de la plataforma Fixia.

## Entorno de Desarrollo (Devs)

Para configurar todo el entorno desde cero (clonar repositorios faltantes, generar variables de entorno y levantar los microservicios), hemos creado un script automatizado.

### Pasos para iniciar:

1. Abre una terminal y dirígete al directorio `ms-orchestrator`:
   ```bash
   cd ms-orchestrator
   ```

2. Ejecuta el script de configuración:
   ```bash
   ./setup-dev.sh
   ```

**¿Qué hace este script?**
- Verifica que estés en el directorio correcto.
- Clona automáticamente los siguientes repositorios en la carpeta raíz (si no existen):
  - `ms-matching-geo`
  - `md-intake-lakehouse`
  - `ms-users`
  - `ms-payments`
  - `ms-apigateway`
  - `ms-frontend`
- Genera el archivo `.env` necesario con las credenciales por defecto (Bases de datos, MinIO, etc.).
- Genera un par de claves RSA para firmar los tokens de `ms-users` (`JWT_PRIVATE_KEY` y `JWT_PUBLIC_KEY`) y lo añade al `.env`. Si tu `.env` ya existía, solo agrega las claves que falten y no toca lo demás. Requiere `openssl`.
- Construye y levanta toda la infraestructura usando `docker-compose`.

### Detener los servicios

Para detener todos los contenedores levantados, puedes usar el siguiente comando estando en el directorio `ms-orchestrator`:

```bash
docker compose --profile full down
```