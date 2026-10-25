// Phase 7A: deploy/interim/storage.interim.rules — the compatible hotfix
// for the live project. Must close cross-user access while accepting the
// uploads of BOTH the live web app ({timestamp}.jpg) and the new app
// ({yyyy-MM-dd}.jpg).
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, deleteObject, listAll } from 'firebase/storage';
import { storageEnv, authed } from './helpers.mjs';

let env;
before(async () => { env = await storageEnv('deploy/interim/storage.interim.rules'); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const st = ctx.storage();
    for (const p of ['completion_photos/alice/1700000000000.jpg', 'completion_photos/alice/2026-01-01.jpg']) {
      await uploadBytes(ref(st, p), new Uint8Array([1, 2]), { contentType: 'image/jpeg' });
    }
    await uploadBytes(ref(st, 'user_avatars/alice.png'), new Uint8Array([1]), { contentType: 'image/png' });
    await uploadBytes(ref(st, 'metadata_backup/completion_photos/alice/run1/2026-01-01.jpg'), new Uint8Array([1]), { contentType: 'image/jpeg' });
  });
});

const st = (uid) => authed(env, uid).storage();
const jpeg = { contentType: 'image/jpeg' };
const bytes = (n) => new Uint8Array(n);

describe('interim — completion photos', () => {
  it('ALLOWS the owner to read and list their own photos', async () => {
    await assertSucceeds(getBytes(ref(st('alice'), 'completion_photos/alice/1700000000000.jpg')));
    await assertSucceeds(listAll(ref(st('alice'), 'completion_photos/alice')));
  });
  it('DENIES other users reading or listing them', async () => {
    await assertFails(getBytes(ref(st('mallory'), 'completion_photos/alice/2026-01-01.jpg')));
    await assertFails(listAll(ref(st('mallory'), 'completion_photos/alice')));
  });
  it('DENIES unauthenticated reads', async () => {
    await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), 'completion_photos/alice/2026-01-01.jpg')));
  });
  it('ALLOWS the live web app\'s upload name ({timestamp}.jpg)', async () => {
    await assertSucceeds(uploadBytes(ref(st('alice'), 'completion_photos/alice/1760900000000.jpg'), bytes(10), jpeg));
  });
  it('ALLOWS the new app\'s upload name ({yyyy-MM-dd}.jpg)', async () => {
    await assertSucceeds(uploadBytes(ref(st('alice'), 'completion_photos/alice/2026-10-19.jpg'), bytes(10), jpeg));
  });
  it('DENIES other names, nested paths, non-images and SVG', async () => {
    await assertFails(uploadBytes(ref(st('alice'), 'completion_photos/alice/x.html'), bytes(10), { contentType: 'text/html' }));
    await assertFails(uploadBytes(ref(st('alice'), 'completion_photos/alice/a/2026-10-19.jpg'), bytes(10), jpeg));
    await assertFails(uploadBytes(ref(st('alice'), 'completion_photos/alice/2026-10-19.jpg'), bytes(10), { contentType: 'text/plain' }));
    await assertFails(uploadBytes(ref(st('alice'), 'completion_photos/alice/2026-10-19.jpg'),
      new TextEncoder().encode('<svg/>'), { contentType: 'image/svg+xml' }));
  });
  it('DENIES 10 MB or more', async () => {
    await assertFails(uploadBytes(ref(st('alice'), 'completion_photos/alice/2026-10-19.jpg'), bytes(10 * 1024 * 1024), jpeg));
  });
  it('DENIES writing into another user\'s folder', async () => {
    await assertFails(uploadBytes(ref(st('mallory'), 'completion_photos/alice/2026-10-19.jpg'), bytes(10), jpeg));
  });
  it('ALLOWS the owner to delete (the live app deletes its own photos); DENIES others', async () => {
    await assertFails(deleteObject(ref(st('mallory'), 'completion_photos/alice/2026-01-01.jpg')));
    await assertSucceeds(deleteObject(ref(st('alice'), 'completion_photos/alice/2026-01-01.jpg')));
  });
});

describe('interim — profile photos', () => {
  it('ALLOWS the owner to upload their avatar (denied by the live rules today)', async () => {
    await assertSucceeds(uploadBytes(ref(st('bob'), 'user_avatars/bob.png'), bytes(10), { contentType: 'image/png' }));
  });
  it('ALLOWS signed-in reads; DENIES unauthenticated reads', async () => {
    await assertSucceeds(getBytes(ref(st('mallory'), 'user_avatars/alice.png')));
    await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), 'user_avatars/alice.png')));
  });
  it('DENIES another user\'s avatar, other names and oversize files', async () => {
    await assertFails(uploadBytes(ref(st('mallory'), 'user_avatars/alice.png'), bytes(10), { contentType: 'image/png' }));
    await assertFails(uploadBytes(ref(st('bob'), 'user_avatars/bob.html'), bytes(10), { contentType: 'image/png' }));
    await assertFails(uploadBytes(ref(st('bob'), 'user_avatars/bob.png'), bytes(5 * 1024 * 1024), { contentType: 'image/png' }));
  });
});

describe('interim — everything else', () => {
  it('DENIES metadata backups even to the photo owner', async () => {
    await assertFails(getBytes(ref(st('alice'), 'metadata_backup/completion_photos/alice/run1/2026-01-01.jpg')));
    await assertFails(listAll(ref(st('alice'), 'metadata_backup/completion_photos/alice')));
  });
  it('DENIES unknown paths', async () => {
    await assertFails(uploadBytes(ref(st('alice'), 'misc/alice.jpg'), bytes(10), jpeg));
  });
});
