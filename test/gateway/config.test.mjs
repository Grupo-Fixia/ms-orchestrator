import assert from 'node:assert/strict';
import { test } from 'node:test';
import { apiRoutes, composeConfig, labels } from './config.mjs';

const config = composeConfig();
const services = config.services;

test('Compose válido: APIs precisas, puertos y prioridades; sin reescritura del prefijo', () => {
  for (const [name, [prefix, port]] of Object.entries(apiRoutes)) {
    const tags = labels(services[name]);
    assert.equal(tags['traefik.enable'], 'true');
    assert.equal(tags[`traefik.http.routers.${name}.rule`],
      `Path(\`${prefix}\`) || PathPrefix(\`${prefix}/\`)`);
    assert.equal(tags[`traefik.http.services.${name}.loadbalancer.server.port`], String(port));
    assert.equal(tags[`traefik.http.routers.${name}.entrypoints`], 'web');
    assert.equal(tags[`traefik.http.routers.${name}.priority`], '10');
    assert.ok(!Object.keys(tags).some(key => /middlewares|stripprefix|replacepath/i.test(key)));
    assert.ok(!services[name].ports?.length, `${name} no debe publicar puertos al host`);
    assert.ok(Object.hasOwn(services[name].networks, 'fixia-net'));
  }
});

test('Frontend usa 8080 y reserva /api* e /internal* al gateway', () => {
  const tags = labels(services['ms-frontend']);
  assert.equal(tags['traefik.http.services.ms-frontend.loadbalancer.server.port'], '8080');
  assert.equal(tags['traefik.http.routers.ms-frontend.rule'],
    'PathPrefix(`/`) && !PathPrefix(`/api`) && !PathPrefix(`/internal`)');
  assert.equal(tags['traefik.http.routers.ms-frontend.priority'], '1');
});

test('Dashboard DEV solo en loopback; backend y lakehouse sin rutas internas públicas', () => {
  const dashboard = services.traefik.ports.filter(port => port.target === 8080);
  assert.equal(dashboard.length, 1);
  assert.equal(dashboard[0].host_ip, '127.0.0.1');
  assert.ok(services.traefik.command.includes('--providers.docker.exposedbydefault=false'));
  assert.equal(labels(services['ms-intake-lakehouse'])?.['traefik.enable'], undefined);
  for (const [name, service] of Object.entries(services)) {
    const tags = labels(service) ?? {};
    for (const [key, value] of Object.entries(tags)) {
      if (key.endsWith('.rule') && name !== 'ms-frontend') assert.ok(!value.includes('/internal'));
    }
  }
});

for (const project of ['fixia', 'gc475-config-isolated']) {
  test(`La red seleccionada por Traefik coincide con Compose para proyecto ${project}`, () => {
    const rendered = composeConfig(project, true);
    const network = rendered.networks['fixia-net'].name;
    assert.equal(network, `${project}_fixia-net`);
    assert.ok(rendered.services.traefik.command.includes(`--providers.docker.network=${network}`));
  });
}

test('Matching conserva claves y DNS internos; services conserva conexión con users', () => {
  const geo = services['ms-matching-geo'].environment;
  assert.equal(geo.USERS_BASE_URL, 'http://ms-users:8080');
  assert.ok(geo.JWT_PUBLIC_KEY);
  assert.equal(geo.INTERNAL_API_KEY, services['ms-users'].environment.INTERNAL_API_KEY);
  assert.equal(geo.INTERNAL_API_KEY, services['ms-services'].environment.INTERNAL_API_KEY);
  assert.equal(services['ms-services'].environment.USERS_BASE_URL, 'http://ms-users:8080');
});
