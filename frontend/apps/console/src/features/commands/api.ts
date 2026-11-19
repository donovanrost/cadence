import type { MissionId } from "@/api/index.ts";
import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";

/** Contract: docs/apogee/api/commanding.md (M17, the active command catalog). */

/** The human catalog revision ("CATALOG rev 14"); null when none records the model (commanding.md). */
export const catalogRevisionReader = d.optional(
  d.nullable(d.object({ id: d.token, number: d.nullable(d.integer), label: d.nullable(d.string) })),
);
export const catalogRevisionWords = (
  r: Readonly<{ number: number | null; label: string | null }> | null | undefined,
) => (r ? (r.number !== null ? `Catalog rev ${r.number}` : r.label) : null);

const basis = {
  state: d.oneOf(["active", "not_active"] as const),
  revision_id: d.nullable(d.token),
  catalog_revision: catalogRevisionReader,
  plan_id: d.nullable(d.token),
  activation_id: d.nullable(d.token),
};

/** commanding.md: a command's significance (null when the catalog gives none). */
export const significance = d.nullable(
  d.oneOf(["routine", "warning", "critical", "hazardous"] as const),
);

const listFields = {
  id: d.token,
  name: d.string,
  display_name: d.nullable(d.string),
  description: d.nullable(d.string),
  subsystem: d.nullable(d.string),
  group: d.nullable(d.string),
  significance,
  critical: d.boolean,
  hazardous: d.boolean,
  second_go_required: d.boolean,
  argument_count: d.integer,
};
const commandSummary = d.object(listFields);
export type CommandSummary = Decoded<typeof commandSummary>;

/** Argument values are JSON text (uint64-safe); kept as text and parsed per type in args.ts. */
const argument = d.object({
  id: d.token,
  name: d.string,
  description: d.nullable(d.string),
  // Typing rule (1), lead: a new argument type mustn't fail the whole catalog read; it reads
  // "unrecognized" and that argument renders read-only (args.ts).
  type: d.known(["integer", "float", "string", "binary", "boolean", "enumerated"] as const),
  required: d.boolean,
  default_value_json: d.nullable(d.string),
  fixed_value_json: d.nullable(d.string),
  hazardous_values_json: d.array(d.string, 100),
  choices: d.array(d.object({ label: d.string, value_json: d.string }), 1_000),
  valid_range: d.nullable(
    d.object({ minimum_json: d.nullable(d.string), maximum_json: d.nullable(d.string) }),
  ),
  unit: d.nullable(d.string),
  /**
   * B2's Now column (api, per-target values): the point whose value is this argument's current
   * setting, from the verifier that compares a point with this argument; null when none.
   */
  current_point: d.optional(
    d.nullable(d.object({ id: d.token, name: d.string, unit: d.nullable(d.string) })),
  ),
});
export type CommandArgument = Decoded<typeof argument>;

const commandDetail = d.object({
  ...listFields,
  opcode_json: d.nullable(d.string),
  apid: d.nullable(d.integer),
  release_policy_hint: d.nullable(d.string),
  arguments: d.array(argument, 200),
  verifiers: d.array(
    d.object({
      id: d.token,
      name: d.string,
      // commanding.md: acceptance | start | completion | custom
      phase: d.knownText(["acceptance", "start", "completion", "custom"] as const),
      timeout_ms: d.nullable(d.integer),
    }),
    100,
  ),
});
export type CommandDetail = Decoded<typeof commandDetail>;

export const catalogReader = d.object({ ...basis, commands: d.array(commandSummary, 500) });
export type Catalog = Decoded<typeof catalogReader>;
export const commandReader = d.object({ ...basis, command: d.nullable(commandDetail) });

const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/commands`;

export function fetchCatalog(
  missionId: MissionId,
  q: string,
  signal?: AbortSignal,
): Promise<ApiResult<Catalog>> {
  const params = new URLSearchParams({ limit: "200", ...(q ? { q } : {}) });
  return request(
    `${base(missionId)}?${params.toString()}`,
    catalogReader,
    signal ? { signal } : {},
  );
}

export function fetchCommand(missionId: MissionId, commandId: string, signal?: AbortSignal) {
  return request(
    `${base(missionId)}/${encodeURIComponent(commandId)}`,
    commandReader,
    signal ? { signal } : {},
  );
}
