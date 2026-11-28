import type { OrganizationId } from "@/api/index.ts";
import { actor, decoders as d, orNull, request, type ApiResult, type Decoded } from "@/api";

/** PA1 history (api c06a70c0): versions newest first, each with its changes against the one before. */
export const versionsReader = d.object({
  id: d.token,
  name: d.string,
  current_version: d.nullable(d.integer),
  versions: d.array(
    d.object({
      version: d.integer,
      created_at: d.timestamp,
      actor: orNull(actor),
      changes: d.array(
        d.object({
          field: d.string,
          label: d.nullable(d.string),
          before: (v: unknown) => (v === undefined ? null : v),
          after: (v: unknown) => (v === undefined ? null : v),
        }),
        200,
      ),
    }),
    1000,
  ),
});
export type AccountVersions = Decoded<typeof versionsReader>;
export type AccountVersion = AccountVersions["versions"][number];

export function fetchAccountVersions(
  key: Readonly<{ orgId: OrganizationId; id: string }>,
  signal: AbortSignal,
): Promise<ApiResult<AccountVersions>> {
  return request(
    `/organizations/${encodeURIComponent(key.orgId)}/provider-accounts/${encodeURIComponent(key.id)}/versions`,
    versionsReader,
    { signal },
  );
}

/** A changed value as text; credentials arrive as their reference only (never a secret). */
export function valueText(v: unknown): string {
  if (v === null) return "—";
  if (typeof v === "string") return v === "" ? "(empty)" : v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return JSON.stringify(v);
}

/** "Name: Earendil Demo → Earendil Ground" per change; v1 reads "Created." */
export function changeLines(v: AccountVersion, first: boolean): readonly string[] {
  if (v.changes.length === 0) return [first ? "Created." : "No field changes recorded."];
  return v.changes.map(
    (c) => `${c.label ?? c.field}: ${valueText(c.before)} → ${valueText(c.after)}`,
  );
}
