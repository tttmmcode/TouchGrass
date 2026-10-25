/**
 * A Firestore lease so two runs of the same operator job (scheduled or by
 * hand) never work at the same time (Phase 6, P6-D). The lease document is
 * server-only (`_ops/…`; firestore.rules deny all client access). A crashed
 * holder's lease simply expires after `ttlMs`.
 */

import type {Firestore} from "firebase-admin/firestore";

export interface Lease {
  holder: string;
  release(): Promise<void>;
}

/** Takes the lease at [path] for [ttlMs], or returns null if another live
 * holder has it. */
export async function acquireLease(
  db: Firestore,
  path: string,
  holder: string,
  ttlMs: number,
  now: () => number = Date.now
): Promise<Lease | null> {
  const ref = db.doc(path);
  const got = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const until = Number(snap.get("leaseUntil") ?? 0);
    const current = snap.get("leaseHolder");
    if (until > now() && current !== holder) return false;
    tx.set(ref, {leaseHolder: holder, leaseUntil: now() + ttlMs}, {merge: true});
    return true;
  });
  if (!got) return null;
  return {
    holder,
    async release() {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (snap.get("leaseHolder") === holder) tx.set(ref, {leaseUntil: 0}, {merge: true});
      });
    },
  };
}
