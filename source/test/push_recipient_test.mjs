// Exercise the current root Edge Function without connecting to Supabase/FCM.
// The historical source/ function is covered separately by push_payload_test.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';

function fixture(callerId = 'sender') {
  const sent = [];
  const tables = {
    profiles: ['sender', 'recipient', 'unrelated'].map(id => ({
      id, phone: 'test', nom: 'Exemple', prenom: 'Test',
      hospital: 'Test hospital', role: 'medecin', account_status: 'active',
    })),
    exchange_requests: [{ id: 'exchange-test', from_id: 'sender', to_id: 'recipient',
      from_name: 'Dr Exemple', to_name: 'Dr Test', type: 'exchange', status: 'pendingB' }],
    push_tokens: [
      { token: 'recipient-android', owner_id: 'recipient', platform: 'android' },
      { token: 'recipient-ios', owner_id: 'recipient', platform: 'ios' },
      { token: 'unrelated-android', owner_id: 'unrelated', platform: 'android' },
      { token: 'sender-android', owner_id: 'sender', platform: 'android' },
    ],
  };
  const db = {
    auth: { getUser: async () => ({ data: { user: { id: callerId } }, error: null }) },
    from(table) {
      let rows = tables[table] ?? [];
      const query = {
        select() { return query; },
        eq(key, value) { rows = rows.filter(row => row[key] === value); return query; },
        in(key, values) { rows = rows.filter(row => values.includes(row[key])); return query; },
        async single() { return { data: rows[0] ?? null, error: null }; },
        then(resolve, reject) { return Promise.resolve({ data: rows, error: null }).then(resolve, reject); },
      };
      return query;
    },
  };
  let handler;
  const context = vm.createContext({
    TextEncoder, URLSearchParams, Response,
    console: { log() {}, error() {} },
    fetch: async (_url, init) => { sent.push(JSON.parse(init.body).message); return new Response('{}'); },
    createClient: () => db,
    Deno: {
      env: { get: key => key === 'FCM_SERVICE_ACCOUNT_JSON' ? '{"project_id":"test"}' : 'test' },
      serve: fn => { handler = fn; },
    },
  });
  const code = readFileSync(new URL('../../supabase/functions/send-push/index.ts', import.meta.url), 'utf8')
    .replace(/^import .*\n/, '');
  vm.runInContext(stripTypeScriptTypes(code), context);
  context.googleAccessToken = async () => 'test-access';
  return { handler, sent, send: context.sendFcm };
}

for (const platform of ['android', 'ios']) {
  test(`${platform}: account-scoped data payload, no automatic native display`, async () => {
    const { send, sent } = fixture();
    await send({ project_id: 'test' }, 'test-access', 'test-token', platform,
      { title: 'Test', body: 'Test', kind: 'exchange_created', resourceId: 'test', recipientId: 'recipient' });
    assert.equal(sent[0].data.recipientId, 'recipient');
    assert.equal(sent[0].notification, undefined);
    assert.equal(sent[0].android?.notification, undefined);
    assert.equal(sent[0].apns?.payload.aps.alert, undefined);
    if (platform === 'android') assert.equal(sent[0].android.priority, 'HIGH');
    else assert.equal(sent[0].apns.payload.aps['content-available'], 1);
  });
}

test('a request reaches only the recipient’s registered devices', async () => {
  const { handler, sent } = fixture();
  const response = await handler(new Request('https://example.invalid', {
    method: 'POST', body: JSON.stringify({ kind: 'exchange_created', resourceId: 'exchange-test' }),
  }));
  assert.equal(response.status, 200);
  assert.deepEqual(sent.map(message => message.token), ['recipient-android', 'recipient-ios']);
  assert.ok(sent.every(message => message.data.recipientId === 'recipient'));
});

test('an unrelated account cannot trigger that request notification', async () => {
  const { handler, sent } = fixture('unrelated');
  const response = await handler(new Request('https://example.invalid', {
    method: 'POST', body: JSON.stringify({ kind: 'exchange_created', resourceId: 'exchange-test' }),
  }));
  assert.equal(response.status, 400);
  assert.equal(sent.length, 0);
});
