/**
 * Controlled download-token revocation experiment (Phase 7F, Phase C).
 * An OPERATOR TOOL, never deployed. It answers one question with
 * production evidence before any real photo's link is rotated: once the
 * rotation tool removes a photo's old download token, does the old
 * `?alt=media&token=` URL stop working?
 *
 * Everything it touches is synthetic and created by `setup`: two test
 * accounts (an owner and an "other" user), one 16×16 test JPEG with no
 * metadata at `completion_photos/{ownerUid}/2026-01-01.jpg`, and one Journal
 * document holding its link. `cleanup` removes all of it. The rotation steps
 * themselves are done by the real tool (`opsCli.js photo-token-rotate --uid`),
 * so the experiment exercises exactly the code a production rotation runs.
 *
 *   node lib/ops/revocationExperiment.js setup   --project P --confirm-project P --mode test-object-mutation --state F
 *   node lib/ops/revocationExperiment.js probe   --stage before|paused|after --state F
 *   node lib/ops/revocationExperiment.js cleanup --mode test-object-mutation --state F
 *
 * Against the emulators (FIRESTORE_/FIREBASE_STORAGE_/FIREBASE_AUTH_
 * EMULATOR_HOST all set, `demo-` project id) it is the rehearsal. Otherwise
 * only `touchgrass-today` is accepted; `setup` and `cleanup` change test
 * data, so they need `--mode test-object-mutation` (and setup also
 * `--confirm-project`). Some emulator hosts without the others are refused:
 * the run would mix environments. `probe` only reads — apart from signing
 * the two test accounts in, which updates their last-sign-in time.
 *
 * Output: statuses, check names and a verdict — never tokens, URLs or
 * passwords. The state file (owner-only, under the git-ignored ops-out/)
 * holds the synthetic accounts' random passwords and the test photo's
 * tokens so later stages can probe them; `cleanup` deletes it and keeps a
 * copy without those secrets.
 */

import {randomBytes, randomUUID} from "node:crypto";
import {readFileSync, rmSync, writeFileSync} from "node:fs";
import {downloadUrl} from "./photoTokenRotation";
import {jpeg} from "./testJpeg";

const PRODUCTION = "touchgrass-today";
const TOKEN_KEY = "firebaseStorageDownloadTokens";
export const EXPERIMENT_FILE = "2026-01-01.jpg";
export const EXPERIMENT_MEMORY = "p7f-revocation";

export type Probe = number | "error";
export interface Sample {old: Probe; current: Probe}
export type Verdict = "revoked" | "not-revoked" | "inconclusive";

/**
 * What a series of probes taken after the old token's removal shows.
 * - not-revoked: the old URL opened the photo at least once.
 * - revoked: it was refused (401/403/404) in every sample AND the current
 *   link opened the same photo in that same sample — the service was
 *   healthy, so the refusal is about the token, not an outage.
 * - inconclusive: anything else (errors, 5xx, too few samples).
 */
export function interpretRevocation(samples: Sample[], minSamples = 3): Verdict {
  if (samples.some((s) => s.old === 200)) return "not-revoked";
  if (samples.length < minSamples) return "inconclusive";
  const refused = (p: Probe) => p === 401 || p === 403 || p === 404;
  return samples.every((s) => refused(s.old) && s.current === 200) ? "revoked" : "inconclusive";
}

export interface ExperimentState {
  project: string;
  bucket: string;
  ownerUid: string;
  otherUid: string;
  ownerEmail: string;
  otherEmail: string;
  ownerPassword: string;
  otherPassword: string;
  object: string;
  memoryPath: string;
  oldToken: string;
  md5: string;
  contentType: string;
  cacheControl: string;
  setupAt: string;
  probes: Array<{stage: string; at: string; passed: boolean; checks: Record<string, boolean>; verdict?: Verdict;
    samples?: Sample[]}>;
  cleanedUpAt?: string;
}

/** Where requests go: the emulators (rehearsal) or production. */
export interface Endpoints {
  storageBase: string;
  signInUrl: string;
}

export interface ExperimentDeps {
  auth: {
    createUser(p: {email: string; password: string; displayName: string}): Promise<{uid: string}>;
    deleteUser(uid: string): Promise<void>;
  };
  db: {
    doc(path: string): {
      set(data: Record<string, unknown>): Promise<unknown>;
      get(): Promise<{exists: boolean; get(f: string): unknown}>;
    };
    collection(path: string): {get(): Promise<{size: number}>};
    recursiveDelete(ref: unknown): Promise<void>;
  };
  bucket: {
    name: string;
    file(name: string): {
      save(data: Buffer, o: Record<string, unknown>): Promise<unknown>;
      getMetadata(): Promise<[Record<string, unknown>, ...unknown[]]>;
      delete(o?: {ignoreNotFound?: boolean}): Promise<unknown>;
    };
    getFiles(q: {prefix: string}): Promise<[unknown[], ...unknown[]]>;
  };
  endpoints: Endpoints;
  fetch: typeof fetch;
  sleep: (ms: number) => Promise<void>;
}

const tokenIn = (url: unknown): string => {
  try {
    return typeof url === "string" ? new URL(url).searchParams.get("token") ?? "" : "";
  } catch {
    return "";
  }
};
const tokensOf = (m: Record<string, unknown>) =>
  String((m.metadata as Record<string, string> | undefined)?.[TOKEN_KEY] ?? "").split(",").map((t) => t.trim()).filter(Boolean);

/** A download URL for the configured endpoint (emulator or production). */
function tokenUrl(e: Endpoints, bucket: string, name: string, token: string): string {
  const prod = downloadUrl(bucket, name, token);
  return e.storageBase === "https://firebasestorage.googleapis.com" ? prod :
    prod.replace("https://firebasestorage.googleapis.com", e.storageBase);
}

async function status(f: typeof fetch, url: string, init?: RequestInit): Promise<Probe> {
  try {
    // Node's fetch keeps no HTTP cache: every probe reaches the service.
    const res = await f(url, init);
    await res.arrayBuffer().catch(() => undefined);
    return res.status;
  } catch {
    return "error";
  }
}

/** A signed-in user's metadata read of the photo through the Storage API
 * (rules apply): 200 for the owner, 403 for anyone else. */
async function authedRead(d: ExperimentDeps, s: ExperimentState, email: string, password: string): Promise<Probe> {
  try {
    const res = await d.fetch(d.endpoints.signInUrl, {method: "POST", headers: {"content-type": "application/json"},
      body: JSON.stringify({email, password, returnSecureToken: true})});
    if (res.status !== 200) return "error";
    const idToken = String(((await res.json()) as {idToken?: unknown}).idToken ?? "");
    return status(d.fetch, `${d.endpoints.storageBase}/v0/b/${s.bucket}/o/${encodeURIComponent(s.object)}`,
      {headers: {authorization: `Firebase ${idToken}`}});
  } catch {
    return "error";
  }
}

/** Creates the synthetic accounts, photo and Journal link. */
export async function setupExperiment(d: ExperimentDeps, project: string, now = new Date()): Promise<ExperimentState> {
  const tag = randomBytes(4).toString("hex");
  const pw = () => randomBytes(24).toString("base64url");
  const ownerEmail = `tg-p7f-revocation-owner-${tag}@example.com`;
  const otherEmail = `tg-p7f-revocation-other-${tag}@example.com`;
  const ownerPassword = pw();
  const otherPassword = pw();
  const owner = await d.auth.createUser({email: ownerEmail, password: ownerPassword, displayName: "P7F revocation test"});
  const other = await d.auth.createUser({email: otherEmail, password: otherPassword, displayName: "P7F revocation test"});
  const object = `completion_photos/${owner.uid}/${EXPERIMENT_FILE}`;
  const oldToken = randomUUID();
  const contentType = "image/jpeg";
  const cacheControl = "private, max-age=300";
  await d.bucket.file(object).save(Buffer.from(jpeg({jfif: true})), {
    resumable: false, contentType,
    metadata: {contentType, cacheControl, metadata: {[TOKEN_KEY]: oldToken}},
  });
  const memoryPath = `users/${owner.uid}/memories/${EXPERIMENT_MEMORY}`;
  await d.db.doc(memoryPath).set({photoUrl: downloadUrl(d.bucket.name, object, oldToken)});
  const [meta] = await d.bucket.file(object).getMetadata();
  return {
    project, bucket: d.bucket.name, ownerUid: owner.uid, otherUid: other.uid, ownerEmail, otherEmail,
    ownerPassword, otherPassword, object, memoryPath, oldToken, md5: String(meta.md5Hash ?? ""),
    contentType, cacheControl, setupAt: now.toISOString(), probes: [],
  };
}

export type Stage = "before" | "paused" | "after";

/** Probes the photo at a stage of the experiment and checks what that
 * stage must show. Never returns tokens or URLs. */
export async function probeExperiment(d: ExperimentDeps, s: ExperimentState, stage: Stage,
  opts: {samples?: number; intervalMs?: number} = {}): Promise<ExperimentState["probes"][number]> {
  const memory = await d.db.doc(s.memoryPath).get();
  const current = tokenIn(memory.exists ? memory.get("photoUrl") : undefined);
  const [meta] = await d.bucket.file(s.object).getMetadata();
  const tokens = tokensOf(meta);
  const samples: Sample[] = [];
  const n = Math.max(opts.samples ?? (stage === "after" ? 3 : 1), 1);
  for (let i = 0; i < n; i++) {
    if (i > 0) await d.sleep(opts.intervalMs ?? 30_000);
    samples.push({
      old: await status(d.fetch, tokenUrl(d.endpoints, s.bucket, s.object, s.oldToken)),
      current: current ? await status(d.fetch, tokenUrl(d.endpoints, s.bucket, s.object, current)) : "error",
    });
  }
  const [files] = await d.bucket.getFiles({prefix: `completion_photos/${s.ownerUid}/`});
  const memories = await d.db.collection(`users/${s.ownerUid}/memories`).get();
  const checks: Record<string, boolean> = {
    "photo content unchanged (MD5)": String(meta.md5Hash ?? "") === s.md5,
    "content type and cache control unchanged": meta.contentType === s.contentType && meta.cacheControl === s.cacheControl,
    "owner can read through the Storage API": await authedRead(d, s, s.ownerEmail, s.ownerPassword) === 200,
    "other test account is refused (rules)": await authedRead(d, s, s.otherEmail, s.otherPassword) === 403,
    "no other object or Journal document appeared": files.length === 1 && memories.size === 1,
    "saved link opens the photo": samples.every((x) => x.current === 200),
  };
  let verdict: Verdict | undefined;
  if (stage === "before") {
    checks["saved link still uses the original token"] = current === s.oldToken;
    checks["exactly one token"] = tokens.length === 1 && tokens[0] === s.oldToken;
    checks["original URL opens the photo"] = samples.every((x) => x.old === 200);
  } else if (stage === "paused") {
    checks["saved link moved to a new token"] = current !== "" && current !== s.oldToken;
    checks["both tokens present (old still valid at the pause)"] =
      tokens.length === 2 && tokens.includes(s.oldToken) && tokens.includes(current);
    checks["original URL still opens (expected at the pause)"] = samples.every((x) => x.old === 200);
  } else {
    checks["saved link uses the new token"] = current !== "" && current !== s.oldToken;
    checks["only the new token is stored"] = tokens.length === 1 && tokens[0] === current;
    verdict = interpretRevocation(samples);
    checks["original URL refused (verdict revoked)"] = verdict === "revoked";
  }
  return {stage, at: new Date().toISOString(), passed: Object.values(checks).every(Boolean), checks, verdict, samples};
}

/** Removes everything setup created; reports what remained. */
export async function cleanupExperiment(d: ExperimentDeps, s: ExperimentState): Promise<Record<string, boolean>> {
  await d.bucket.file(s.object).delete({ignoreNotFound: true});
  await d.db.recursiveDelete(d.db.doc(`users/${s.ownerUid}`));
  for (const uid of [s.ownerUid, s.otherUid]) {
    await d.auth.deleteUser(uid).catch((e: {code?: string}) => {
      if (e?.code !== "auth/user-not-found") throw e;
    });
  }
  const [files] = await d.bucket.getFiles({prefix: `completion_photos/${s.ownerUid}/`});
  const memories = await d.db.collection(`users/${s.ownerUid}/memories`).get();
  return {
    "test photo deleted": files.length === 0,
    "test Journal document deleted": memories.size === 0,
    "original URL no longer opens": await status(d.fetch, tokenUrl(d.endpoints, s.bucket, s.object, s.oldToken)) !== 200,
  };
}

/** The state without secrets, for the record kept after cleanup. */
export function redactState(s: ExperimentState): Record<string, unknown> {
  const {ownerPassword: _p1, otherPassword: _p2, oldToken: _t, ...rest} = s;
  void _p1;
  void _p2;
  void _t;
  return rest;
}

// ── CLI ─────────────────────────────────────────────────────────────────────

/** Why the command must not run, or null. */
export function experimentRefusal(cmd: string, flags: Map<string, string>, env: Record<string, string | undefined>):
  string | null {
  if (!["setup", "probe", "cleanup"].includes(cmd)) return "Use setup, probe or cleanup.";
  if (!flags.get("state")) return "--state <file under ops-out/> is required.";
  const hosts = [env.FIRESTORE_EMULATOR_HOST, env.FIREBASE_STORAGE_EMULATOR_HOST, env.FIREBASE_AUTH_EMULATOR_HOST]
    .map(Boolean);
  if (hosts.some(Boolean) && !hosts.every(Boolean)) {
    return "Some emulator hosts are set and others aren't: the run would mix environments. Set all three or none.";
  }
  const emulator = hosts.every(Boolean);
  if (!emulator && cmd !== "probe" && flags.get("mode") !== "test-object-mutation") {
    return `${cmd} changes test data in production: add --mode test-object-mutation.`;
  }
  if (cmd === "setup") {
    const project = flags.get("project");
    if (!project) return "--project is required.";
    if (emulator && !project.startsWith("demo-")) return "The rehearsal must use a demo- project id.";
    if (!emulator && project !== PRODUCTION) return `Only ${PRODUCTION} (or the emulators) is accepted.`;
    if (!emulator && flags.get("confirm-project") !== project) return "setup creates test data: add --confirm-project <same id>.";
  }
  if (cmd === "probe" && !["before", "paused", "after"].includes(flags.get("stage") ?? "")) {
    return "--stage before|paused|after is required.";
  }
  return null;
}

function parseFlags(rest: string[]): Map<string, string> {
  const flags = new Map<string, string>();
  for (let i = 0; i < rest.length; i += 2) {
    if (!rest[i].startsWith("--") || rest[i + 1] === undefined) throw new Error(`Bad argument: ${rest[i]}`);
    flags.set(rest[i].slice(2), rest[i + 1]);
  }
  return flags;
}

/** The public Firebase web API key (the same one shipped in the web app). */
function webApiKey(): string {
  const src = readFileSync(`${__dirname}/../../../lib/firebase_options.dart`, "utf8");
  const m = /FirebaseOptions web = FirebaseOptions\(\s*apiKey: '([^']+)'/.exec(src);
  if (!m) throw new Error("web apiKey not found in lib/firebase_options.dart");
  return m[1];
}

async function main(argv: string[]): Promise<number> {
  const [cmd, ...rest] = argv;
  let flags: Map<string, string>;
  try {
    flags = parseFlags(rest);
  } catch (e) {
    console.error((e as Error).message);
    return 2;
  }
  const refused = experimentRefusal(cmd, flags, process.env);
  if (refused) {
    console.error(refused);
    return 2;
  }
  const statePath = flags.get("state")!;
  const prior: ExperimentState | undefined = cmd === "setup" ? undefined : JSON.parse(readFileSync(statePath, "utf8"));
  const project = prior?.project ?? flags.get("project")!;
  const emulator = Boolean(process.env.FIREBASE_STORAGE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
  if (!emulator && project !== PRODUCTION) {
    console.error("State file is not for the production project.");
    return 2;
  }
  const {initializeApp} = await import("firebase-admin/app");
  const {getAuth} = await import("firebase-admin/auth");
  const {getFirestore} = await import("firebase-admin/firestore");
  const {getStorage} = await import("firebase-admin/storage");
  initializeApp({projectId: project, storageBucket: `${project}.firebasestorage.app`});
  const deps: ExperimentDeps = {
    auth: getAuth() as never,
    db: getFirestore() as never,
    bucket: getStorage().bucket() as never,
    endpoints: emulator ? {
      storageBase: `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}`,
      signInUrl: `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator`,
    } : {
      storageBase: "https://firebasestorage.googleapis.com",
      signInUrl: `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${webApiKey()}`,
    },
    fetch,
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
  };
  const save = (s: ExperimentState) => writeFileSync(statePath, JSON.stringify(s, null, 2), {encoding: "utf8", mode: 0o600});

  if (cmd === "setup") {
    const s = await setupExperiment(deps, project);
    save(s);
    const ready = new Date(Date.parse(s.setupAt) + 11 * 60 * 1000).toISOString();
    console.log(JSON.stringify({setup: "done", testOwnerUid: s.ownerUid, rotationAllowedAfter: ready,
      note: "the rotation tool skips photos changed in the last 10 minutes"}, null, 2));
    return 0;
  }
  if (cmd === "probe") {
    const p = await probeExperiment(deps, prior!, flags.get("stage") as Stage, {
      samples: flags.has("samples") ? Number(flags.get("samples")) : undefined,
      intervalMs: flags.has("interval-ms") ? Number(flags.get("interval-ms")) : undefined,
    });
    prior!.probes.push(p);
    save(prior!);
    console.log(JSON.stringify(p, null, 2));
    return p.passed ? 0 : 1;
  }
  const result = await cleanupExperiment(deps, prior!);
  prior!.cleanedUpAt = new Date().toISOString();
  writeFileSync(`${statePath}.result.json`, JSON.stringify({...redactState(prior!), cleanup: result}, null, 2),
    {encoding: "utf8", mode: 0o600});
  rmSync(statePath, {force: true});
  console.log(JSON.stringify({cleanup: result}, null, 2));
  return Object.values(result).every(Boolean) ? 0 : 1;
}

if (require.main === module) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e) => {
      console.error(`Failed: ${(e as Error).name}`);
      process.exit(1);
    }
  );
}
