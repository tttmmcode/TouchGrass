/**
 * Scheduled wrapper for the abandoned-photo cleanup (audit D-16, Phase 5).
 *
 * DELIBERATELY NOT EXPORTED FROM index.ts, so it is neither deployed nor
 * scheduled — `firebase deploy` only ships what index.ts exports, and
 * orphanPhotoCleanup.test.ts fails if index.ts starts exporting it. Enabling
 * it needs owner approval (it creates a Cloud Scheduler job — see
 * REMEDIATION_CHECKLIST.md, Phase 5, D-16 for cost and steps). To enable,
 * after approval, add to index.ts:
 *
 *   export {orphanPhotoCleanupJob} from "./orphanPhotoCleanupJob";
 *
 * and run it in dry-run (the default) first, reading the logged report.
 * Deletion additionally requires setting the parameter
 * ORPHAN_PHOTO_CLEANUP_MODE=delete. It has no HTTP or callable endpoint:
 * only Cloud Scheduler can invoke it, never an app user.
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineString} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {randomUUID} from "node:crypto";
import {adminCleanupDeps, runOrphanPhotoCleanup} from "./orphanPhotoCleanup";
import {acquireLease} from "./ops/lease";

const cleanupMode = defineString("ORPHAN_PHOTO_CLEANUP_MODE", {default: "dry-run"});

/** Server-only progress document (firestore.rules deny all client access). */
const STATE_DOC = "_ops/orphanPhotoCleanup";

export const orphanPhotoCleanupJob = onSchedule(
  {
    schedule: "every day 04:00",
    timeZone: "Etc/UTC",
    region: "us-central1",
    // One instance handling one run at a time: runs never overlap.
    maxInstances: 1,
    concurrency: 1,
    timeoutSeconds: 300,
    memory: "256MiB",
    retryCount: 0,
  },
  async () => {
    const db = getFirestore();
    // A second run (manual trigger, overlap after a slow run) backs off.
    const lease = await acquireLease(db, `${STATE_DOC}_lease`, randomUUID(), 10 * 60 * 1000);
    if (!lease) {
      logger.info("Orphan photo cleanup skipped: another run holds the lease");
      return;
    }
    try {
      const stateRef = db.doc(STATE_DOC);
      const state = (await stateRef.get()).data() ?? {};
      const report = await runOrphanPhotoCleanup(
        adminCleanupDeps(db, getStorage().bucket()),
        {
          mode: cleanupMode.value() === "delete" ? "delete" : "dry-run",
          now: new Date(),
          pageToken: typeof state.pageToken === "string" ? state.pageToken : undefined,
        }
      );
      // Counts only — no uids, file names or photo content are logged.
      await stateRef.set({
        pageToken: report.nextPageToken ?? null,
        lastRunAt: FieldValue.serverTimestamp(),
        lastReport: report,
      });
      logger.info("Orphan photo cleanup", report);
    } finally {
      await lease.release();
    }
  }
);
