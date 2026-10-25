// Phase 7A: what the LIVE Storage rules allow today. LIVE_RULES is the
// ruleset exported read-only from touchgrass-today on 2026-10-19
// (tool/export_live_rules.mjs; sha256 c55022239296…). It matches no
// committed storage.rules. These tests run it on the emulator to prove the
// exposure and that both replacements (interim and final) close it.
import { describe, it, after } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, listAll } from 'firebase/storage';
import { PROJECT_ID, authed, storageEnv } from './helpers.mjs';

const LIVE_RULES = `rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /completion_photos/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}`;

const seed = async (env) => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), 'completion_photos/alice/1700000000000.jpg'), new Uint8Array([1]), { contentType: 'image/jpeg' });
  });
};

let env;
after(async () => { await env?.cleanup(); });

describe('LIVE Storage rules (as exported 2026-10-19)', () => {
  it('ALLOWS any signed-in user to read another user\'s completion photo (exposure)', async () => {
    env = await initializeTestEnvironment({ projectId: PROJECT_ID, storage: { rules: LIVE_RULES } });
    await seed(env);
    await assertSucceeds(getBytes(ref(authed(env, 'mallory').storage(), 'completion_photos/alice/1700000000000.jpg')));
  });
  it('ALLOWS any signed-in user to list another user\'s photos (enumeration)', async () => {
    await assertSucceeds(listAll(ref(authed(env, 'mallory').storage(), 'completion_photos/alice')));
  });
  it('ALLOWS an owner to store any file type in their folder (e.g. HTML)', async () => {
    await assertSucceeds(uploadBytes(ref(authed(env, 'mallory').storage(), 'completion_photos/mallory/x.html'),
      new TextEncoder().encode('<script>1</script>'), { contentType: 'text/html' }));
  });
  it('DENIES profile-photo uploads (no rule): avatar changes fail live today', async () => {
    await assertFails(uploadBytes(ref(authed(env, 'alice').storage(), 'user_avatars/alice.png'), new Uint8Array([1]), { contentType: 'image/png' }));
    await env.cleanup();
    env = undefined;
  });
});

for (const [label, file] of [['INTERIM', 'deploy/interim/storage.interim.rules'], ['FINAL', 'storage.rules']]) {
  describe(`${label} rules close the live exposure`, () => {
    it(`DENIES cross-user reads and listing under ${file}`, async () => {
      env = await storageEnv(file);
      await seed(env);
      await assertFails(getBytes(ref(authed(env, 'mallory').storage(), 'completion_photos/alice/1700000000000.jpg')));
      await assertFails(listAll(ref(authed(env, 'mallory').storage(), 'completion_photos/alice')));
      await assertSucceeds(getBytes(ref(authed(env, 'alice').storage(), 'completion_photos/alice/1700000000000.jpg')));
      await env.cleanup();
      env = undefined;
    });
  });
}
