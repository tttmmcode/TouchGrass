/**
 * Phase 7E: the deploy entry point (index.ts) must stay deployable on its
 * own. firebase-tools resolves every param the loaded code declares BEFORE
 * applying `--only`, so a secret declared anywhere in index.ts's import
 * graph would make `firebase deploy --only functions:deleteAccount` prompt
 * for (and create) that secret — or fail. AI verification is disabled and
 * must never be deployable by accident.
 */
import {test, describe} from "node:test";
import assert from "node:assert/strict";
import {declaredParams} from "firebase-functions/params";

describe("functions deploy entry point (Phase 7E)", () => {
  test("exports exactly deleteAccount and declares no params (no GEMINI_API_KEY)", async () => {
    // Loading index.js initializes the Admin SDK locally; it makes no calls.
    process.env.GCLOUD_PROJECT ??= "demo-entry-point-test";
    const index = await import("./index");
    assert.deepEqual(Object.keys(index).sort(), ["deleteAccount"]);
    assert.deepEqual(declaredParams.map((p) => p.name), [], "the entry point must not declare params or secrets");
  });

  test("the AI module is the one that declares the secret (so loading it is what to avoid)", async () => {
    const before = declaredParams.length;
    const ai = await import("./aiVerification");
    assert.ok("verifyChallengeCompletion" in ai);
    const added = declaredParams.slice(before).map((p) => p.name);
    assert.deepEqual(added, ["GEMINI_API_KEY"]);
  });
});
