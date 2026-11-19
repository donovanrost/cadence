import type { StageOp } from "@/features/changes/index.ts";
import type { ProfileSummary } from "@/features/profiles/index.ts";
import type { ProposedSpacecraft } from "./batch.ts";

export type BatchOps =
  | Readonly<{ ok: true; ops: readonly StageOp[]; summary: string }>
  | Readonly<{ ok: false; message: string }>;

/**
 * One `spacecraft` create op per row (domain kind: display_name, scid, profile pin, metadata).
 * Plane, slot and NORAD go in metadata, where the directory reads them until they're first-class.
 */
export function batchOps(
  rows: readonly ProposedSpacecraft[],
  profiles: readonly ProfileSummary[],
  defaultProfileId: string,
): BatchOps {
  const byName = new Map(profiles.map((p) => [p.name.toLowerCase(), p]));
  const fallback = profiles.find((p) => p.id === defaultProfileId);
  if (!fallback) return { ok: false, message: "Pick a profile." };
  const ops: StageOp[] = [];
  for (const row of rows) {
    if (row.problems.length > 0)
      return { ok: false, message: `${row.name || "A row"}: ${row.problems[0] ?? "invalid"}` };
    const profile = row.profileName === null ? fallback : byName.get(row.profileName.toLowerCase());
    if (!profile)
      return { ok: false, message: `${row.name}: unknown profile ${row.profileName ?? ""}` };
    const metadata: Record<string, number> = {};
    if (row.norad !== null) metadata.norad_id = row.norad;
    if (row.plane !== null) metadata.plane = row.plane;
    if (row.slot !== null) metadata.slot = row.slot;
    ops.push({
      kind: "spacecraft",
      action: "create",
      document: {
        display_name: row.name,
        scid: row.scid,
        spacecraft_type_id: profile.id,
        spacecraft_type_version: profile.version,
        metadata,
      },
    });
  }
  const names = new Set(
    ops.map((op) => (op.document?.spacecraft_type_id === fallback.id ? fallback.name : "mixed")),
  );
  const profileLabel = names.size === 1 ? fallback.name : "several profiles";
  return {
    ok: true,
    ops,
    summary:
      rows.length === 1
        ? `Add spacecraft ${rows[0]?.name ?? ""} (${profileLabel})`
        : `${rows.length} new spacecraft (${profileLabel})`,
  };
}
