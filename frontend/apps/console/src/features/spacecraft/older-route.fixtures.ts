import { decode } from "@/api/index.ts";
import { detailReader } from "./detail.ts";

/** Test fixtures for the older-route removal (ux U79), through the real decoders. */
export function olderRules(extra: readonly Record<string, unknown>[] = []) {
  const base = {
    purpose: null,
    direction: "inbound",
    role: "primary",
    enabled: true,
    active: true,
    transport: { id: "t-1", name: "AWA S-band" },
    route_id: null,
  };
  const result = decode(detailReader, {
    spacecraft: {
      id: "sc-1",
      name: "EARENDIL-389",
      scid: 389,
      norad_id: null,
      plane: null,
      slot: null,
      last_received_at: null,
    },
    profile: null,
    configuration: null,
    telemetry: { status: "never", last_received_at: null },
    routing_rules: [
      {
        ...base,
        id: "old-1",
        name: "qa-pre-routing-175358",
        origin: "legacy",
        station: { id: "gs-2", code: "AWA", name: "Awarua" },
      },
      ...extra.map((r) => ({ ...base, ...r })),
    ],
    readiness: { ready: true, checks: [] },
  });
  if (!result.ok) throw new Error(result.error.message);
  return result.value.routing_rules;
}

const actor = { kind: "user", id: "u1", name: "Mira K." };
/** GET /config with the open set holding the given ops. */
export const configWith = (ops: readonly Record<string, unknown>[]) => ({
  head: {
    revision: 5,
    kind: "change_set",
    live: true,
    applied_at: "2026-11-16T02:29:00Z",
    applied_by: actor,
    reason: "r5",
    summary: null,
    entry_count: 1,
    change_set_id: null,
    rolls_back_to: null,
    approvals: [],
  },
  change_set: {
    id: "cs-1",
    version: 1,
    state: "open",
    base_revision: 5,
    opened_at: "2026-11-16T21:00:00Z",
    opened_by: actor,
    staged_count: 1,
    changes: [
      {
        id: "c-1",
        summary: "Remove older route “qa-pre-routing-175358” · EARENDIL-389",
        author: actor,
        staged_at: "2026-11-16T21:00:00Z",
        source: { surface: "spacecraft" },
        state: "staged",
        ops: ops.map((o, i) => ({ id: `o-${i}`, paths: [], payload: null, ...o })),
      },
    ],
    withdrawn: [],
    authors: [actor],
    submitted_by: null,
    submitted_at: null,
    reason: null,
    approval_required: null,
    reviews: [],
    failure: null,
    applied_revision: null,
  },
  permissions: ["config.stage"],
});
