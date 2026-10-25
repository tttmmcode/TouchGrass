// D-05: storage.rules must compile and scope access correctly.
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, deleteObject, listAll } from 'firebase/storage';
import { storageEnv, authed, seedProfiles } from './helpers.mjs';

let env;
before(async () => { env = await storageEnv(); }); // fails if the rules do not compile
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearStorage();
  await env.clearFirestore();
  // Every signed-in test user has a profile, as real users do (Phase 7F:
  // uploads require one; the no-profile case is in the parity suite).
  await seedProfiles(env, ['alice', 'bob', 'mallory']);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const st = ctx.storage();
    await uploadBytes(ref(st, 'user_avatars/alice.png'), new Uint8Array([1, 2]), { contentType: 'image/png' });
    await uploadBytes(ref(st, 'completion_photos/alice/1.jpg'), new Uint8Array([1, 2]), { contentType: 'image/jpeg' });
  });
});

const st = (uid) => authed(env, uid).storage();
const bytes = (n) => new Uint8Array(n);
const svg = new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');

describe('user_avatars/{uid}.png', () => {
  it('ALLOWS the owner to upload a PNG avatar', async () => {
    await assertSucceeds(uploadBytes(ref(st('bob'), 'user_avatars/bob.png'), bytes(10), { contentType: 'image/png' }));
  });
  it('ALLOWS the owner to replace their avatar', async () => {
    await assertSucceeds(uploadBytes(ref(st('alice'), 'user_avatars/alice.png'), bytes(10), { contentType: 'image/png' }));
  });
  it('ALLOWS any signed-in user to read an avatar', async () => {
    await assertSucceeds(getBytes(ref(st('mallory'), 'user_avatars/alice.png')));
  });
  it('DENIES unauthenticated avatar reads', async () => {
    await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), 'user_avatars/alice.png')));
  });
  it('DENIES overwriting another user\'s avatar', async () => {
    await assertFails(uploadBytes(ref(st('mallory'), 'user_avatars/alice.png'), bytes(10), { contentType: 'image/png' }));
  });
  it('DENIES avatar paths that are not {uid}.png', async () => {
    await assertFails(uploadBytes(ref(st('mallory'), 'user_avatars/mallory.png.html'), bytes(10), { contentType: 'image/png' }));
    await assertFails(uploadBytes(ref(st('mallory'), 'user_avatars/mallory/x.png'), bytes(10), { contentType: 'image/png' }));
  });
  it('DENIES an SVG avatar (S-8)', async () => {
    await assertFails(uploadBytes(ref(st('bob'), 'user_avatars/bob.png'), svg, { contentType: 'image/svg+xml' }));
  });
  it('DENIES a non-image avatar', async () => {
    await assertFails(uploadBytes(ref(st('bob'), 'user_avatars/bob.png'), bytes(10), { contentType: 'text/html' }));
  });
  it('DENIES an avatar of 5 MB or more (boundary)', async () => {
    await assertFails(uploadBytes(ref(st('bob'), 'user_avatars/bob.png'), bytes(5 * 1024 * 1024), { contentType: 'image/png' }));
  });
  it('ALLOWS an avatar just under 5 MB (boundary)', async () => {
    await assertSucceeds(uploadBytes(ref(st('bob'), 'user_avatars/bob.png'), bytes(5 * 1024 * 1024 - 1), { contentType: 'image/png' }));
  });
  it('DENIES client deletion (deletion design deferred to Phase 2 / D-04)', async () => {
    await assertFails(deleteObject(ref(st('alice'), 'user_avatars/alice.png')));
  });
});

describe('completion_photos/{uid}/{yyyy-MM-dd}.jpg', () => {
  const day = '2026-10-17.jpg';
  for (const type of ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']) {
    it(`ALLOWS the owner to upload ${type}`, async () => {
      await assertSucceeds(uploadBytes(ref(st('alice'), `completion_photos/alice/${day}`), bytes(10), { contentType: type }));
    });
  }
  it('ALLOWS a retried upload to replace the same file (idempotent, D-13)', async () => {
    await assertSucceeds(uploadBytes(ref(st('alice'), `completion_photos/alice/${day}`), bytes(10), { contentType: 'image/jpeg' }));
    await assertSucceeds(uploadBytes(ref(st('alice'), `completion_photos/alice/${day}`), bytes(12), { contentType: 'image/jpeg' }));
  });
  for (const name of ['2.jpg', '1700000000000.jpg', '2026-10-17.png', '2026-10-17.jpg.html', 'x/2026-10-17.jpg', '20261017.jpg']) {
    it(`DENIES a file not named {yyyy-MM-dd}.jpg: ${name} (no orphan-prone names, D-13)`, async () => {
      await assertFails(uploadBytes(ref(st('alice'), `completion_photos/alice/${name}`), bytes(10), { contentType: 'image/jpeg' }));
    });
  }
  it('ALLOWS reading a legacy {timestamp}.jpg photo (seeded)', async () => {
    await assertSucceeds(getBytes(ref(st('alice'), 'completion_photos/alice/1.jpg')));
  });
  it('ALLOWS the owner to read their photo', async () => {
    await assertSucceeds(getBytes(ref(st('alice'), 'completion_photos/alice/1.jpg')));
  });
  it('DENIES other users reading the photo', async () => {
    await assertFails(getBytes(ref(st('mallory'), 'completion_photos/alice/1.jpg')));
  });
  it('DENIES uploading into another user\'s folder', async () => {
    await assertFails(uploadBytes(ref(st('mallory'), `completion_photos/alice/${day}`), bytes(10), { contentType: 'image/jpeg' }));
  });
  it('DENIES uid-prefix collisions (alice vs alice2)', async () => {
    await assertFails(uploadBytes(ref(st('alice'), `completion_photos/alice2/${day}`), bytes(10), { contentType: 'image/jpeg' }));
  });
  it('DENIES an SVG completion photo (S-8)', async () => {
    await assertFails(uploadBytes(ref(st('alice'), `completion_photos/alice/${day}`), svg, { contentType: 'image/svg+xml' }));
  });
  it('DENIES a photo of 10 MB or more (boundary)', async () => {
    await assertFails(uploadBytes(ref(st('alice'), `completion_photos/alice/${day}`), bytes(10 * 1024 * 1024), { contentType: 'image/jpeg' }));
  });
  it('ALLOWS a photo just under 10 MB (boundary)', async () => {
    await assertSucceeds(uploadBytes(ref(st('alice'), `completion_photos/alice/${day}`), bytes(10 * 1024 * 1024 - 1), { contentType: 'image/jpeg' }));
  });
  it('ALLOWS listing your own folder', async () => {
    await assertSucceeds(listAll(ref(st('alice'), 'completion_photos/alice')));
  });
  it('DENIES listing another user\'s folder', async () => {
    await assertFails(listAll(ref(st('mallory'), 'completion_photos/alice')));
  });
  it('DENIES client deletion (account deletion is server-side, D-04)', async () => {
    await assertFails(deleteObject(ref(st('alice'), 'completion_photos/alice/1.jpg')));
  });
});

describe('everything else', () => {
  it('DENIES writes outside the two known prefixes', async () => {
    await assertFails(uploadBytes(ref(st('alice'), 'public/x.jpg'), bytes(10), { contentType: 'image/jpeg' }));
  });
});
