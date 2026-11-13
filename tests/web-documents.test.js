import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { createWebServer } from '../src/web/server.js';
import { webConfig } from './fixtures/web-config.js';

const password = 'JenkinWoo';
const png = Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), Buffer.from('uploaded-proof')]);
const url = id => `https://services.sheerid.com/verify/aaaaaaaaaaaaaaaaaaaaaaaa/?verificationId=${id}`;

async function fixture(t, options = {}) {
  const { configFile } = await webConfig(t);
  const documentDir = await mkdtemp(join(tmpdir(), 'one-web-documents-'));
  t.after(() => rm(documentDir, { recursive: true, force: true }));
  const app = createWebServer({ port: 0, configFile, documentDir, ...options });
  const origin = await app.start();
  t.after(() => app.close());
  const call = (path, init = {}) => fetch(`${origin}${path}`, {
    ...init, headers: { 'X-Web-Password': password, ...init.headers },
  });
  const { token } = await (await call('/api/session')).json();
  const write = (path, init = {}) => call(path, {
    ...init, headers: { 'X-Local-Token': token, ...init.headers },
  });
  return { app, origin, documentDir, call, write };
}

test('Uploaded material is stored locally and becomes the queued task document', async t => {
  let received;
  const { app, documentDir, write } = await fixture(t, {
    workflow: async config => { received = config; return { status: 'pending' }; },
  });
  const upload = await write('/api/documents', { method: 'POST',
    headers: { 'Content-Type': 'image/png', 'X-Document-Name': encodeURIComponent('transcript.png') },
    body: png });
  assert.equal(upload.status, 201);
  const document = await upload.json();
  assert.equal(document.name, 'transcript.png');
  assert.equal(document.size, png.length);
  assert.ok(document.path.startsWith(`${resolve(documentDir)}${sep}`));
  assert.deepEqual(await readFile(document.path), png);

  const response = await write('/api/jobs', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url: url('eeeeeeeeeeeeeeeeeeeeeeee'), firstName: 'Upload', lastName: 'Fixture',
      birthDate: '2000-01-02', documentPath: document.path }) });
  assert.equal(response.status, 202);
  const { job } = await response.json();
  await app.jobs.jobs.get(job.id).done;
  assert.equal(received.document.path, document.path);
  assert.equal(received.document.url, '', 'the uploaded file replaces configured network material');
});

test('Uploads and task material paths are validated', async t => {
  let called = false;
  const { origin, documentDir, write } = await fixture(t, {
    workflow: async () => { called = true; return { status: 'pending' }; },
  });
  const upload = (body, name = 'proof.png') => write('/api/documents', { method: 'POST',
    headers: { 'Content-Type': 'image/png', 'X-Document-Name': encodeURIComponent(name) }, body });
  assert.equal((await upload(Buffer.from('<html>login</html>'))).status, 400);
  assert.equal((await upload(png, 'proof.html')).status, 400);
  assert.equal((await upload(png, '../proof.png')).status, 400);
  const oversized = Buffer.alloc(20 * 1024 * 1024 + 1);
  oversized.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.equal((await upload(oversized)).status, 413);
  assert.equal((await fetch(`${origin}/api/documents`, { method: 'POST',
    headers: { 'X-Web-Password': password, 'X-Document-Name': encodeURIComponent('proof.png') },
    body: png })).status, 403, 'uploads need the page write token');

  const task = name => write('/api/jobs', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url: url(name.padStart(24, '0')), firstName: 'Outside', lastName: 'Path',
      birthDate: '2000-01-02', documentPath: '/etc/hosts' }) });
  assert.equal((await task('1')).status, 400);
  assert.equal((await task('2')).status, 400);
  assert.equal((await write('/api/jobs', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url: url('000000000000000000000003'), firstName: 'Outside', lastName: 'Path',
      birthDate: '2000-01-02', documentPath: join(documentDir, 'missing.png') }) })).status, 400);
  assert.equal(called, false);
});
