// Traefik real con backends de prueba. No usa Docker socket, secretos ni servicios compartidos.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { apiRoutes, composeConfig, labels } from './config.mjs';

function run(args) {
  return execFileSync('docker', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

try { run(['info', '--format', '{{.OSType}}']); }
catch { console.error('Motor Docker no disponible. Inicie Docker Desktop con contenedores Linux y repita.'); process.exit(1); }

const source = composeConfig();
const tempRoot = resolve(tmpdir());
const directory = mkdtempSync(join(tempRoot, 'gc475-gateway-'));
const project = `gc475-${Date.now()}-${process.pid}`;
const fixture = join(directory, 'compose.json');
const composeArgs = ['compose', '--project-name', project, '--file', fixture];
const dynamic = { http: { routers: {}, services: {} } };
const backends = {};
const routes = { 'ms-frontend': ['/', 8080], ...apiRoutes };

for (const [name, [, port]] of Object.entries(routes)) {
  const tags = labels(source.services[name]);
  const nginx = `server { listen ${port}; location / { default_type text/plain; add_header X-GC475-Service ${name} always; return 200 "$request_method $request_uri"; } }`;
  const path = join(directory, `${name}.conf`);
  writeFileSync(path, nginx);
  backends[name] = {
    image: 'nginx:alpine',
    volumes: [{ type: 'bind', source: path, target: '/etc/nginx/conf.d/default.conf', read_only: true }],
  };
  dynamic.http.routers[name] = {
    rule: tags[`traefik.http.routers.${name}.rule`],
    priority: Number(tags[`traefik.http.routers.${name}.priority`]),
    entryPoints: ['web'], service: name,
  };
  dynamic.http.services[name] = { loadBalancer: { servers: [{ url: `http://${name}:${port}` }] } };
}

// JSON es un subconjunto de YAML; Traefik exige extensión .yml/.yaml o .toml.
const dynamicPath = join(directory, 'routes.yml');
writeFileSync(dynamicPath, JSON.stringify(dynamic));
writeFileSync(fixture, JSON.stringify({
  services: {
    gateway: {
      image: source.services.traefik.image,
      command: ['--entrypoints.web.address=:80', '--api=false',
        '--providers.file.filename=/etc/traefik/routes.yml', '--log.level=INFO'],
      ports: [{ target: 80, published: '0', host_ip: '127.0.0.1' }],
      volumes: [{ type: 'bind', source: dynamicPath, target: '/etc/traefik/routes.yml', read_only: true }],
    }, ...backends,
  },
}));

let started = false;
let keep = false;
try {
  started = true;
  run([...composeArgs, 'up', '-d', '--wait', '--wait-timeout', '60']);
  const binding = run([...composeArgs, 'port', 'gateway', '80']).trim();
  assert.match(binding, /^127\.0\.0\.1:\d+$/);
  const base = `http://${binding}`;
  let ready = false;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      const response = await fetch(base, { signal: AbortSignal.timeout(1000) });
      ready = response.status === 200;
      await response.text();
      if (ready) break;
    } catch { /* Esperar únicamente al stack de prueba. */ }
    await new Promise(done => setTimeout(done, 250));
  }
  assert.ok(ready, 'Traefik y frontend de prueba deben responder');
  let count = 0;
  async function check(path, service, method = 'GET') {
    const response = await fetch(base + path, { method, signal: AbortSignal.timeout(5000) });
    const body = await response.text();
    assert.equal(response.status, service ? 200 : 404, `${method} ${path}`);
    assert.equal(response.headers.get('x-gc475-service'), service ?? null, path);
    if (service) assert.equal(body, `${method} ${path}`, 'Se conserva método, ruta y query');
    count++;
  }
  await check('/', 'ms-frontend');
  await check('/client/requests', 'ms-frontend');
  for (const [name, [prefix]] of Object.entries(apiRoutes)) {
    await check(prefix, name);
    await check(`${prefix}/`, name);
    await check(`${prefix}/probe?limit=2&cursor=abc`, name, 'POST');
    await check(`${prefix}XYZ`, null);
  }
  await check('/api/geo/matching/technicians', 'ms-matching-geo', 'POST');
  await check('/api/services/requests/example/compatible-technicians', 'ms-services');
  for (const path of ['/api', '/api/', '/api/desconocida', '/apiXYZ', '/internal',
    '/internal/tokens/example/status', '/internal/matching/technicians']) await check(path, null);
  console.log(`PASS: ${count} comprobaciones HTTP con Traefik real y backends de prueba.`);
  console.log('No acredita autenticación ni disponibilidad de los microservicios reales.');
  if (process.argv.includes('--keep')) {
    keep = true;
    console.log(`Prueba manual: ${base}`);
    console.log(`Proyecto aislado: ${project}`);
    console.log(`Limpieza obligatoria: docker compose --project-name ${project} --file "${fixture}" down --volumes`);
    console.log(`Después puede eliminar solo la carpeta temporal: ${directory}`);
  }
} catch (error) {
  console.error(error instanceof assert.AssertionError ? error.message : 'Falló el stack de prueba; revise Docker y la descarga de imágenes.');
  process.exitCode = 1;
} finally {
  if (!keep) {
    let cleaned = !started;
    if (started) {
      try { run([...composeArgs, 'down', '--volumes', '--remove-orphans']); cleaned = true; }
      catch { console.error(`No se pudo limpiar. Ejecute docker compose --project-name ${project} --file "${fixture}" down --volumes`); process.exitCode = 1; }
    }
    // Solo borrar el directorio exacto creado por mkdtemp; conservarlo si falta limpiar Docker.
    if (cleaned && dirname(resolve(directory)) === tempRoot && basename(directory).startsWith('gc475-gateway-')) {
      rmSync(directory, { recursive: true });
    }
  }
}
