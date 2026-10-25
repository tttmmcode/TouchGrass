/**
 * Operator CLI for TouchGrass maintenance jobs (Phase 6). NOT a deployed
 * function: index.ts never imports anything under ops/.
 *
 *   cd functions && npm run build
 *   node lib/ops/opsCli.js <command> --project <id> [options]
 *
 * Commands (all dry-run / read-only unless stated):
 *   photo-metadata-inventory   count completion photos with EXIF/XMP/GPS
 *   photo-metadata-remediate   strip metadata in place (WRITES with --execute)
 *   photo-token-rotate         new download token per completion photo and
 *                              the owner's stored links (WRITES with --execute)
 *   orphan-photos              abandoned-photo cleanup (DELETES with --execute)
 *   profile-photo-inventory    count stored profile photo URL kinds
 *
 * Safety (Phase 7G: one operation mode, exact allowlists, fail closed):
 * - Operation mode (`--mode`): `read-only` (the default) never writes
 *   anything anywhere in the project. Writing needs `--execute` AND an
 *   explicit mutation mode: `test-object-mutation` (token rotation scoped
 *   with `--uid` to one test account) or `production-mutation`. A mode
 *   that doesn't match `--execute` is refused.
 * - Environment: both emulator hosts (FIRESTORE_EMULATOR_HOST and
 *   FIREBASE_STORAGE_EMULATOR_HOST) with a `demo-` project id, which can
 *   never reach production; or neither, with a project and bucket on the
 *   exact production allowlist. One host without the other (Firestore and
 *   Storage would hit different environments) and a GCLOUD_PROJECT /
 *   GOOGLE_CLOUD_PROJECT that differs from `--project` are refused.
 * - Against a real project every command — even a read-only one, because
 *   it reads private photos — needs `--real-project`, and anything that
 *   writes also needs `--confirm-project <same id>`.
 * - stdout gets counts only. Object names, uids and resume cursors (a
 *   Storage page token encodes an object path) go only to the `--out` file,
 *   which every real-project run needs: a NEW file (never overwritten)
 *   under the git-ignored `ops-out/` directory, created owner-read/write
 *   only. Coordinates, URLs and image bytes are never printed, and errors
 *   print a fixed message or the error class, never file contents.
 * - Resuming: `--resume <previous --out file>` continues an inventory or
 *   cleanup where it stopped, and makes a remediation or token rotation
 *   skip the photos a previous run already finished (rotation also reuses
 *   that run's id, so a photo rotated just before an interruption only has
 *   its links finished, not a second new token).
 * - Remediation and token rotation both rewrite photos, so they share one
 *   Firestore lease: two such runs never work at the same time. Their
 *   dry-runs take no lease (Phase 7F): a dry-run writes nothing anywhere
 *   in the project, not even the lease document.
 * - `--full-read` (inventory) downloads each photo in full, so data
 *   appended after the image is found too.
 * - `--uid <uid>` (inventory, token rotation) limits the run to one user's
 *   photos: the canary on a test account before any full run.
 * - `--remove-via metadata|rewrite` (token rotation, default metadata): how
 *   the old token is removed once the links use the new one. Chosen from
 *   the test-account canary's evidence (PHASE_7D_TOKEN_ROTATION_RUNBOOK.md).
 * - `--stop-before-remove` (token rotation): stop once the new token is
 *   added and the links moved, old token still valid — the controlled
 *   revocation experiment (PHASE_7E_TOKEN_ROTATION_STATUS.md). Re-run with
 *   the same `--run-id` and without the flag to remove the old token.
 * - Uses Application Default Credentials; no key files are read or written.
 *   A real-project run is refused before anything is contacted when no ADC
 *   file exists (Phase 7H): run `gcloud auth application-default login`
 *   yourself first.
 * - The `--out` file of a read-only token-rotation run (Phase 7H, AC-1)
 *   holds counts and per-photo outcomes keyed by a short hash of the object
 *   name — no object names, uids or generations: the inventory's decisions
 *   need only the aggregates. (Its resume cursor still encodes one object
 *   path.)
 */

import {existsSync, writeFileSync, readFileSync, mkdirSync} from "node:fs";
import {createHash, randomUUID} from "node:crypto";
import {dirname, isAbsolute, join, relative, resolve} from "node:path";
import {homedir} from "node:os";
import {FINAL_OUTCOMES, type RemediationOutcome} from "./photoMetadataJob";
import {ROTATION_FINAL, type RotationOutcome} from "./photoTokenRotation";

export type Command =
  | "photo-metadata-inventory"
  | "photo-metadata-remediate"
  | "photo-token-rotate"
  | "orphan-photos"
  | "profile-photo-inventory";

const COMMANDS: Command[] = [
  "photo-metadata-inventory", "photo-metadata-remediate", "photo-token-rotate", "orphan-photos",
  "profile-photo-inventory",
];
const WRITING: Command[] = ["photo-metadata-remediate", "photo-token-rotate", "orphan-photos"];
/** Lease shared by every job that rewrites photo objects. */
export const PHOTO_REWRITE_LEASE = "_ops/photoRewrite_lease";
/** Projects these jobs must never touch: a similarly named Firebase project
 * that is not TouchGrass production (Phase 7A finding). */
export const NOT_TOUCHGRASS = ["gen-lang-client-0754598293"];
/** The ONLY real project these tools may reach, and its only bucket. */
export const PRODUCTION_ALLOWLIST: Readonly<Record<string, string>> = {
  "touchgrass-today": "touchgrass-today.firebasestorage.app",
};

/** The repository's own git-ignored output directory (lib/ops → repo root).
 * Real-project output goes only here — not to any other folder that merely
 * happens to be called ops-out (Phase 7H). */
export const OPS_OUT_DIR = resolve(__dirname, "..", "..", "..", "ops-out");

/** True when [path] is strictly inside the repository's ops-out/. */
export function insideOpsOut(path: string): boolean {
  const rel = relative(OPS_OUT_DIR, resolve(path));
  return rel !== "" && !rel.startsWith("..") && !isAbsolute(rel);
}

/** Where Google's client libraries look for Application Default
 * Credentials when GOOGLE_APPLICATION_CREDENTIALS is unset. */
export function adcWellKnownFile(env: Record<string, string | undefined>, platform = process.platform): string {
  if (env.CLOUDSDK_CONFIG) return join(env.CLOUDSDK_CONFIG, "application_default_credentials.json");
  return platform === "win32" ?
    join(env.APPDATA ?? join(homedir(), "AppData", "Roaming"), "gcloud", "application_default_credentials.json") :
    join(homedir(), ".config", "gcloud", "application_default_credentials.json");
}

/** Why a real-project run can't authenticate, or null. Checks only that a
 * credentials file exists — never reads it. */
export function credentialsRefusal(env: Record<string, string | undefined>,
  exists: (p: string) => boolean = existsSync, platform = process.platform): string | null {
  const explicit = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (explicit) {
    return exists(explicit) ? null : "GOOGLE_APPLICATION_CREDENTIALS names a file that doesn't exist.";
  }
  if (exists(adcWellKnownFile(env, platform))) return null;
  return "No Application Default Credentials found. In your own terminal run: " +
    "gcloud auth application-default login   — then try again. (Nothing was contacted.)";
}

/** What a run may do. Only `read-only` is implicit. */
export type OperationMode = "read-only" | "test-object-mutation" | "production-mutation";
const MODES: OperationMode[] = ["read-only", "test-object-mutation", "production-mutation"];

export interface CliArgs {
  command: Command;
  project: string;
  bucket?: string;
  out?: string;
  manifest?: string;
  execute: boolean;
  confirmProject?: string;
  realProject: boolean;
  backup: boolean;
  runId?: string;
  max?: number;
  pageToken?: string;
  startAfter?: string;
  resume?: string;
  fullRead: boolean;
  uid?: string;
  removeVia?: "metadata" | "rewrite";
  stopBeforeRemove: boolean;
  mode: OperationMode;
}

/** Parses argv (without node and script). Throws with a usage message. */
export function parseArgs(argv: string[]): CliArgs {
  const [command, ...rest] = argv;
  if (!COMMANDS.includes(command as Command)) {
    throw new Error(`Unknown command. Use one of: ${COMMANDS.join(", ")}`);
  }
  const flags = new Map<string, string | true>();
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (!a.startsWith("--")) throw new Error(`Unexpected argument: ${a}`);
    const key = a.slice(2);
    const next = rest[i + 1];
    if (next !== undefined && !next.startsWith("--")) {
      flags.set(key, next);
      i++;
    } else {
      flags.set(key, true);
    }
  }
  const known = ["project", "bucket", "out", "manifest", "execute", "confirm-project", "real-project",
    "no-backup", "run-id", "max", "page-token", "start-after", "resume", "full-read", "uid", "remove-via", "stop-before-remove",
    "mode"];
  for (const k of flags.keys()) if (!known.includes(k)) throw new Error(`Unknown option --${k}`);
  const str = (k: string) => {
    const v = flags.get(k);
    if (v === true) throw new Error(`--${k} needs a value`);
    return v;
  };
  const project = str("project");
  if (!project || !/^[a-z0-9-]{4,40}$/.test(project)) throw new Error("--project <firebase project id> is required");
  const max = str("max");
  if (max !== undefined && !/^[1-9][0-9]{0,6}$/.test(max)) throw new Error("--max must be a positive integer");
  const uid = str("uid");
  if (uid !== undefined && !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) throw new Error("--uid must be a Firebase uid");
  const removeVia = str("remove-via");
  if (removeVia !== undefined && removeVia !== "metadata" && removeVia !== "rewrite") {
    throw new Error("--remove-via must be metadata or rewrite");
  }
  const runId = str("run-id");
  if (runId !== undefined && !/^[A-Za-z0-9_-]{1,64}$/.test(runId)) throw new Error("--run-id must be 1–64 of [A-Za-z0-9_-]");
  const mode = str("mode") ?? "read-only";
  if (!MODES.includes(mode as OperationMode)) throw new Error(`--mode must be one of: ${MODES.join(", ")}`);
  return {
    command: command as Command,
    project,
    bucket: str("bucket"),
    out: str("out"),
    manifest: str("manifest"),
    execute: flags.get("execute") === true,
    confirmProject: str("confirm-project"),
    realProject: flags.get("real-project") === true,
    backup: !flags.has("no-backup"),
    runId,
    max: max === undefined ? undefined : Number(max),
    pageToken: str("page-token"),
    startAfter: str("start-after"),
    resume: str("resume"),
    fullRead: flags.get("full-read") === true,
    uid,
    removeVia,
    stopBeforeRemove: flags.get("stop-before-remove") === true,
    mode: mode as OperationMode,
  };
}

/** Whether the environment is the emulators (both hosts) — null when only
 * one host is set, which is never safe. */
function emulatorEnv(env: Record<string, string | undefined>): boolean | null {
  const firestore = Boolean(env.FIRESTORE_EMULATOR_HOST);
  const storage = Boolean(env.FIREBASE_STORAGE_EMULATOR_HOST);
  return firestore === storage ? firestore : null;
}

/** Why this project/bucket/environment combination must not be used, or
 * null. Checked before any client is created, so a refused run never
 * contacts anything. */
export function environmentRefusal(project: string, bucket: string | undefined,
  env: Record<string, string | undefined>): string | null {
  const emulator = emulatorEnv(env);
  if (emulator === null) {
    return "Only one of FIRESTORE_EMULATOR_HOST / FIREBASE_STORAGE_EMULATOR_HOST is set: Firestore and Storage " +
      "would reach different environments. Set both or neither.";
  }
  const envProject = env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT;
  if (envProject && envProject !== project) return "GCLOUD_PROJECT / GOOGLE_CLOUD_PROJECT doesn't match --project.";
  if (NOT_TOUCHGRASS.includes(project)) return `${project} is not the TouchGrass project; refusing.`;
  if (emulator) {
    return project.startsWith("demo-") ? null :
      "Emulator runs must use a demo- project id (it can never reach production).";
  }
  const allowedBucket = PRODUCTION_ALLOWLIST[project];
  if (!allowedBucket) return `${project} is not on the production allowlist; refusing.`;
  if (bucket !== undefined && bucket !== allowedBucket) return `--bucket must be exactly ${allowedBucket}.`;
  return null;
}

/** The bucket a run uses: the allowlisted one for production. */
export function bucketFor(args: CliArgs, env: Record<string, string | undefined>): string {
  return args.bucket ?? (emulatorEnv(env) ? `${args.project}.firebasestorage.app` : PRODUCTION_ALLOWLIST[args.project]);
}

/** Why the run must not start, or null when it may. */
export function refusal(args: CliArgs, env: Record<string, string | undefined>): string | null {
  const envRefused = environmentRefusal(args.project, args.bucket, env);
  if (envRefused) return envRefused;
  const emulator = emulatorEnv(env) === true;
  if (args.execute && !WRITING.includes(args.command)) return `${args.command} is read-only; drop --execute`;
  if (args.execute && args.mode === "read-only") {
    return "--execute writes: also pass --mode test-object-mutation (with --uid) or --mode production-mutation.";
  }
  if (!args.execute && args.mode !== "read-only") return `--mode ${args.mode} needs --execute; a run without it is read-only.`;
  if (args.mode === "test-object-mutation" && !(args.command === "photo-token-rotate" && args.uid)) {
    return "--mode test-object-mutation is only for photo-token-rotate scoped to one test account with --uid.";
  }
  if (!emulator && !args.realProject) {
    return "Not pointed at the emulators. Reading a real project's private data needs --real-project " +
      "and the owner's authorization.";
  }
  if (!emulator && !args.out) {
    return "A real-project run needs --out <file>: findings and resume cursors go only to that private file.";
  }
  if (!emulator && args.out && !insideOpsOut(args.out)) {
    return "--out must be inside this repository's git-ignored ops-out/ directory " +
      "(e.g. ../ops-out/rotation/dry-1.json).";
  }
  if (args.resume && (args.pageToken || args.startAfter)) return "Use either --resume or --page-token/--start-after";
  if (args.resume && args.runId && args.command === "photo-token-rotate") return "--resume reuses the previous run id; drop --run-id";
  if (args.fullRead && args.command !== "photo-metadata-inventory") return "--full-read is only for photo-metadata-inventory";
  if ((args.removeVia || args.stopBeforeRemove) && args.command !== "photo-token-rotate") {
    return "--remove-via and --stop-before-remove are only for photo-token-rotate";
  }
  if (args.uid && !["photo-metadata-inventory", "photo-token-rotate"].includes(args.command)) {
    return "--uid is only for photo-metadata-inventory and photo-token-rotate";
  }
  if (args.execute && !emulator && args.confirmProject !== args.project) {
    return "Writing to a real project needs --confirm-project <the same project id>.";
  }
  if (args.command === "photo-metadata-remediate") {
    if (!args.manifest) return "photo-metadata-remediate needs --manifest <inventory --out file>";
    if (!args.out) return "photo-metadata-remediate needs --out <file> for its reversible manifest";
  }
  if (WRITING.includes(args.command) && args.execute && !args.out) {
    return "--execute needs --out <file> so every outcome is recorded";
  }
  return null;
}

function writePrivate(path: string, data: unknown): void {
  // "wx": create a new file only (owner read/write); never replace one.
  writeFileSync(path, JSON.stringify(data, null, 2), {encoding: "utf8", mode: 0o600, flag: "wx"});
}

/** Parses a JSON file. On failure says which flag's file was unreadable,
 * never the parser's message (it can quote the file: names, uids). */
function readJsonFile(path: string, flag: string): Record<string, unknown> {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    throw new Error(`${flag} file can't be read as JSON.`);
  }
}

/** A short, non-reversible tag for an object name: lets two files be
 * compared without either holding the path (which contains a uid). */
export function nameTag(name: string): string {
  return createHash("sha256").update(name).digest("hex").slice(0, 16);
}

/** What the --out file holds for [result]. A read-only token-rotation run
 * (AC-1) keeps no object names, uids or generations (Phase 7H); every other
 * file is unchanged (remediation manifests and execute-run resumes need the
 * names). */
export function forOutFile(args: CliArgs, result: Record<string, unknown>): Record<string, unknown> {
  if (args.command !== "photo-token-rotate" || args.execute) return result;
  const entries = Array.isArray(result.entries) ? result.entries as Array<Record<string, unknown>> : [];
  // An allowlist, so a field added to RotationEntry later isn't saved here
  // by accident.
  const KEEP = ["outcome", "step", "refsTotal", "refsStale", "refsUpdated", "refsCurrent", "refsChanged", "detail"];
  return {
    ...result,
    entries: entries.map((e) => ({
      nameTag: typeof e.name === "string" ? nameTag(e.name) : null,
      ...Object.fromEntries(KEEP.filter((k) => e[k] !== undefined).map((k) => [k, e[k]])),
    })),
  };
}

/** The error's class and, when it is a short code (e.g. 403 or
 * PERMISSION_DENIED), that code — never its message, which can name
 * object paths. */
export function safeErrorLabel(e: unknown): string {
  const name = e instanceof Error ? e.name : "error";
  const code = (e as {code?: unknown} | null)?.code;
  const shown = typeof code === "number" || (typeof code === "string" && /^[A-Za-z0-9_.-]{1,40}$/.test(code)) ?
    ` (code ${String(code)})` : "";
  return `${name}${shown}`;
}

/** Counts only, for stdout: no names, uids or cursors. */
export function summary(report: Record<string, unknown>): Record<string, unknown> {
  const s = {...report};
  const more = Boolean(s.nextPageToken || s.nextStartAfter);
  for (const k of ["items", "entries", "outcomes", "uids", "nextPageToken", "nextStartAfter"]) delete s[k];
  if (more) s.moreRemaining = "yes — run again with --resume <this run's --out file>";
  return s;
}

/** What a run continues from, given the previous run's --out file. */
export function resumeOptions(command: Command, previous: Record<string, unknown>, execute = false):
  {pageToken?: string; startAfter?: string; skipNames?: string[]; runId?: string} {
  if (previous.command !== command) {
    throw new Error(`--resume file is from "${String(previous.command)}", not "${command}"`);
  }
  const cursor = (k: string) => {
    const v = previous[k];
    if (typeof v !== "string" || v.length === 0) throw new Error("--resume file has nothing left to resume");
    return v;
  };
  switch (command) {
  case "photo-metadata-inventory":
  case "orphan-photos":
    return {pageToken: cursor("nextPageToken")};
  case "profile-photo-inventory":
    return {startAfter: cursor("nextStartAfter")};
  case "photo-metadata-remediate": {
    const entries = Array.isArray(previous.entries) ? previous.entries as Array<{name?: unknown; outcome?: unknown}> : [];
    return {skipNames: entries
      .filter((e) => typeof e.name === "string" && FINAL_OUTCOMES.has(e.outcome as RemediationOutcome))
      .map((e) => e.name as string)};
  }
  case "photo-token-rotate": {
    if (previous.mode === "dry-run" && !execute) {
      // A capped dry-run continues listing where it stopped (Phase 7F).
      return {pageToken: cursor("nextPageToken")};
    }
    if (previous.mode !== "execute") throw new Error("--resume needs the --out file of an --execute rotation run");
    const runId = previous.runId;
    if (typeof runId !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(runId)) throw new Error("--resume file has no run id");
    const entries = Array.isArray(previous.entries) ? previous.entries as Array<{name?: unknown; outcome?: unknown}> : [];
    return {runId, skipNames: entries
      .filter((e) => typeof e.name === "string" && ROTATION_FINAL.has(e.outcome as RotationOutcome))
      .map((e) => e.name as string)};
  }
  }
}

function defaultRunId(): string {
  return new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 14);
}

/** The lease a run must hold, or null. Only runs that write take one: a
 * dry-run writes nothing in the project, not even a lease document
 * (Phase 7F). */
export function leaseFor(args: CliArgs): {path: string; ttlMs: number; busy: string} | null {
  if (!args.execute) return null;
  switch (args.command) {
  case "photo-metadata-remediate":
  case "photo-token-rotate":
    return {path: PHOTO_REWRITE_LEASE, ttlMs: 60 * 60 * 1000,
      busy: "Another photo remediation or token rotation run holds the lease; try again later."};
  case "orphan-photos":
    return {path: "_ops/orphanPhotoCleanup_lease", ttlMs: 10 * 60 * 1000,
      busy: "Another cleanup run holds the lease; try again later."};
  default:
    return null;
  }
}

/** Takes the run's lease (a no-op stand-in when it needs none), or null
 * when another run holds it (message printed). */
async function takeLease(db: import("firebase-admin/firestore").Firestore, args: CliArgs) {
  const spec = leaseFor(args);
  if (!spec) return {release: async () => undefined};
  const {acquireLease} = await import("./lease");
  const lease = await acquireLease(db, spec.path, `cli-${randomUUID()}`, spec.ttlMs);
  if (!lease) console.error(spec.busy);
  return lease;
}

async function main(argv: string[]): Promise<number> {
  let args: CliArgs;
  try {
    args = parseArgs(argv);
  } catch (e) {
    console.error(String((e as Error).message));
    return 2;
  }
  const refused = refusal(args, process.env);
  if (refused) {
    console.error(refused);
    return 2;
  }
  let resume: ReturnType<typeof resumeOptions> = {};
  if (args.resume) {
    try {
      resume = resumeOptions(args.command, readJsonFile(args.resume, "--resume"), args.execute);
    } catch (e) {
      console.error(String((e as Error).message));
      return 2;
    }
  }
  if (args.out && existsSync(args.out)) {
    // Never overwrite earlier evidence (e.g. a finished run's outcomes).
    console.error("--out names an existing file; choose a new file name.");
    return 2;
  }
  if (emulatorEnv(process.env) !== true) {
    const noCredentials = credentialsRefusal(process.env);
    if (noCredentials) {
      console.error(noCredentials);
      return 2;
    }
  }
  if (args.out) {
    // Before any read: a run whose findings can't be saved must not start
    // (Phase 7H — the folder didn't exist yet for the first AC-1 run).
    try {
      mkdirSync(dirname(resolve(args.out)), {recursive: true, mode: 0o700});
    } catch {
      console.error("--out folder can't be created.");
      return 2;
    }
  }
  // Loaded lazily so argument errors never initialise Firebase.
  const {initializeApp} = await import("firebase-admin/app");
  const {getFirestore, FieldPath} = await import("firebase-admin/firestore");
  const {getStorage} = await import("firebase-admin/storage");
  initializeApp({projectId: args.project, storageBucket: bucketFor(args, process.env)});
  const result = await runCommand(args, resume, {
    db: getFirestore(), bucket: getStorage().bucket(), documentId: FieldPath.documentId(), now: new Date(),
  });
  if (typeof result === "number") return result;
  if (args.out) writePrivate(args.out, {command: args.command, at: new Date().toISOString(), ...forOutFile(args, result)});
  console.log(JSON.stringify(summary(result), null, 2));
  return 0;
}

/** The clients a command runs against: Admin SDK objects in production,
 * recording fakes in the read-only guarantee tests. */
export interface OpsClients {
  db: import("firebase-admin/firestore").Firestore;
  bucket: import("@google-cloud/storage").Bucket;
  documentId: unknown;
  now: Date;
}

/** Runs one command; returns its report (project and bucket included), or
 * an exit code when the run couldn't start (3: lease held). */
export async function runCommand(args: CliArgs, resume: ReturnType<typeof resumeOptions>, c: OpsClients):
  Promise<Record<string, unknown> | number> {
  const {db, bucket} = c;
  let report: Record<string, unknown>;
  switch (args.command) {
  case "photo-metadata-inventory": {
    const {adminPhotoStore, inventoryPhotoMetadata} = await import("./photoMetadataJob");
    report = {...await inventoryPhotoMetadata(adminPhotoStore(bucket), {
      maxObjects: args.max, pageToken: resume.pageToken ?? args.pageToken, fullRead: args.fullRead, uid: args.uid,
    })};
    break;
  }
  case "photo-metadata-remediate": {
    const {adminPhotoStore, remediatePhotoMetadata} = await import("./photoMetadataJob");
    const inv = readJsonFile(args.manifest!, "--manifest") as {items?: unknown[]};
    const lease = await takeLease(db, args);
    if (!lease) return 3;
    try {
      report = {...await remediatePhotoMetadata(adminPhotoStore(bucket), (inv.items ?? []) as never[], {
        mode: args.execute ? "execute" : "dry-run",
        runId: args.runId ?? defaultRunId(),
        backup: args.backup,
        maxObjects: args.max,
        skipNames: resume.skipNames,
      })};
    } finally {
      await lease.release();
    }
    break;
  }
  case "photo-token-rotate": {
    const {adminReferenceDeps, adminTokenStore, rotatePhotoTokens} = await import("./photoTokenRotation");
    const lease = await takeLease(db, args);
    if (!lease) return 3;
    const runId = resume.runId ?? args.runId ?? defaultRunId();
    try {
      report = {runId, ...await rotatePhotoTokens(adminTokenStore(bucket),
        adminReferenceDeps(db as unknown as Parameters<typeof adminReferenceDeps>[0], bucket.name), {
          mode: args.execute ? "execute" : "dry-run",
          runId,
          bucket: bucket.name,
          now: c.now,
          maxObjects: args.max,
          pageToken: resume.pageToken ?? args.pageToken,
          skipNames: resume.skipNames,
          uid: args.uid,
          removeVia: args.removeVia,
          stopBeforeRemove: args.stopBeforeRemove,
        })};
    } finally {
      await lease.release();
    }
    break;
  }
  case "orphan-photos": {
    const {adminCleanupDeps, runOrphanPhotoCleanup} = await import("../orphanPhotoCleanup");
    const lease = await takeLease(db, args);
    if (!lease) return 3;
    try {
      report = {...await runOrphanPhotoCleanup(adminCleanupDeps(db as never, bucket as never), {
        mode: args.execute ? "delete" : "dry-run",
        now: c.now,
        pageToken: resume.pageToken ?? args.pageToken,
        maxObjects: args.max,
        collectOutcomes: true,
      })};
    } finally {
      await lease.release();
    }
    break;
  }
  case "profile-photo-inventory": {
    const {adminProfileDeps, inventoryProfilePhotos} = await import("./profilePhotoInventory");
    report = {...await inventoryProfilePhotos(
      adminProfileDeps(db as unknown as Parameters<typeof adminProfileDeps>[0], c.documentId),
      {maxDocs: args.max, bucket: args.bucket, startAfter: resume.startAfter ?? args.startAfter})};
    break;
  }
  }
  // Project and bucket are echoed so the operator sees exactly what was read.
  return {project: args.project, bucket: bucket.name, operationMode: args.mode, ...report};
}

if (require.main === module) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e) => {
      // The error class (and a short code) only: messages can contain
      // object paths.
      console.error(`Failed: ${safeErrorLabel(e)}`);
      process.exit(1);
    }
  );
}
