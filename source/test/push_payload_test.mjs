// Node >= 22.13 : test hors réseau du véritable générateur de requêtes FCM.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';

function load(fetchMock, user = null) {
  const source = readFileSync(new URL('../supabase/functions/send-push/index.ts', import.meta.url), 'utf8')
    .replace(/^import .*\n/, '');
  let handler;
  const context = vm.createContext({
    TextEncoder, URLSearchParams, Response, console, fetch: fetchMock,
    createClient: () => ({ auth: { getUser: async () => ({ data: { user }, error: null }) } }),
    Deno: { env: { get: (key) => key === 'FCM_SERVICE_ACCOUNT_JSON' ? '{}' : 'test' }, serve: (fn) => { handler = fn; } },
  });
  vm.runInContext(stripTypeScriptTypes(source), context);
  return { send: context.sendFcm, handler };
}
const data = { title: 'Garde', body: 'Nouvelle demande', kind: 'exchange_created', resourceId: 'test-id' };
test('Android : notification système, priorité et canal identiques au client', async () => {
  let request;
  const { send } = load(async (url, init) => { request = { url, ...init }; return new Response('{}'); });
  await send({ project_id: 'test-project' }, 'test-access', 'test-token', 'android', data);
  const message = JSON.parse(request.body).message;
  assert.deepEqual(message.notification, { title: data.title, body: data.body });
  assert.deepEqual(message.data, data);
  assert.equal(message.android.priority, 'HIGH');
  const dart = readFileSync(new URL('../lib/services/notification_service.dart', import.meta.url), 'utf8');
  assert.ok(dart.includes(`pushChannelId = '${message.android.notification.channel_id}'`));
  assert.equal(message.android.notification.icon, 'ic_stat_huim6');
  assert.equal(message.webpush, undefined);
  assert.equal(request.headers.Authorization, 'Bearer test-access');
});
test('Web : conserver data-only pour éviter le double affichage par le service worker', async () => {
  let message;
  const { send } = load(async (_, init) => { message = JSON.parse(init.body).message; return new Response('{}'); });
  await send({ project_id: 'test' }, 'test', 'test', 'web', data);
  assert.deepEqual(message.data, data);
  assert.equal(message.notification, undefined);
  assert.equal(message.android, undefined);
  assert.equal(message.webpush.headers.Urgency, 'high');
});
test('Les erreurs FCM sont retournées au traitement des tokens', async () => {
  const { send } = load(async () => new Response('{"error":"UNREGISTERED"}', { status: 404 }));
  const result = await send({ project_id: 'test' }, 'test', 'test', 'android', data);
  assert.equal(result.ok, false);
  assert.equal(result.status, 404);
  assert.match(result.text, /UNREGISTERED/);
});
test('Un appel sans utilisateur authentifié est refusé avant tout envoi', async () => {
  const { handler } = load(() => { throw new Error('Aucun appel réseau attendu'); });
  const result = await handler(new Request('https://example.invalid', { method: 'POST', body: '{}' }));
  assert.equal(result.status, 401);
});
test('Un utilisateur authentifié ne peut pas envoyer un payload libre', async () => {
  const { handler } = load(() => { throw new Error('Aucun appel réseau attendu'); }, { id: 'test-user' });
  const result = await handler(new Request('https://example.invalid', { method: 'POST', body: '{"token":"arbitrary"}' }));
  assert.equal(result.status, 400);
});
