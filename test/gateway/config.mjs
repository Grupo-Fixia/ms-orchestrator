import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../../', import.meta.url));

export function composeConfig(project = 'fixia', interpolate = false) {
  const args = ['compose', '--file', 'docker-compose.yml', '--project-name', project, '--env-file', '.env.example',
    '--profile', 'full', 'config', '--format', 'json'];
  if (!interpolate) args.push('--no-interpolate');
  try {
    return JSON.parse(execFileSync('docker', args, {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
      // Solo valores ficticios para validar interpolación; nunca se lee .env.
      env: { ...process.env, JWT_PRIVATE_KEY: 'gc475-config-only', JWT_PUBLIC_KEY: 'gc475-config-only' },
    }));
  } catch {
    throw new Error('No se pudo validar Compose. Requiere Docker Compose v2; no se muestra configuración ni credenciales.');
  }
}

export function labels(service) {
  return Array.isArray(service.labels)
    ? Object.fromEntries(service.labels.map(label => {
      const i = label.indexOf('=');
      return [label.slice(0, i), label.slice(i + 1)];
    })) : service.labels;
}

export const apiRoutes = {
  'ms-users': ['/api/users', 8080],
  'ms-services': ['/api/services', 8080],
  'ms-matching-geo': ['/api/geo', 8000],
  'ms-payments': ['/api/payments', 8080],
};
