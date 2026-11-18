import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  perItem,
  request,
  spacecraftId as spacecraftIdReader,
  type Decoded,
  type PerItem,
} from "@/api/index.ts";

/**
 * #235 (lead's FINAL 11-18 08:49:52Z; ux U94 "Fleets"): what a spacecraft-configuration request
 * changes, on L10's detail. A request can review up to 500 craft, so api groups them: a group is
 * craft whose rows, first start and telemetry switch are exactly equal (server-computed), every
 * group is sent, and a group's names past the first 100 page from the names route.
 * Readers first: optional on the detail until api ships it; null for other kinds.
 */

/** The closed set of fields, in api's order (switches are never rows: #109). */
export const changeFields = [
  "catalog_revision",
  "telemetry_source",
  "handled_apids",
  "downlink",
  "uplink",
  "frame_size",
  "secondary_header_length",
  "insert_zone_length",
  "ocf_length",
  "truncated_primary_header",
] as const;
export type ChangeField = (typeof changeFields)[number];

const catalogValue = d.nullable(d.object({ id: d.token, number: d.nullable(d.integer) }));
// free-text: a packet source's display name
const sourceValue = d.nullable(d.object({ id: d.token, name: d.string }));
const apidsValue = d.nullable(d.array(d.integer, 2048));
const downlinkValue = d.nullable(d.knownText(["tm", "aos", "uslp"] as const));
const uplinkValue = d.nullable(d.knownText(["tc", "uslp"] as const));
const bytesValue = d.nullable(d.integer);
const yesNoValue = d.nullable(d.boolean);

/** One row: `before` is null on a first start (and whenever the active value isn't set). */
const rowOf = <F extends ChangeField, T>(field: F, value: (v: unknown, p?: string) => T) =>
  d.object({
    field: d.literal(field),
    // free-text: api's label, a fallback only; the console words rows by field (U94).
    label: d.string,
    before: value,
    after: value,
  });

const changeRow = d.variant("field", {
  catalog_revision: rowOf("catalog_revision", catalogValue),
  telemetry_source: rowOf("telemetry_source", sourceValue),
  handled_apids: rowOf("handled_apids", apidsValue),
  downlink: rowOf("downlink", downlinkValue),
  uplink: rowOf("uplink", uplinkValue),
  frame_size: rowOf("frame_size", bytesValue),
  secondary_header_length: rowOf("secondary_header_length", bytesValue),
  insert_zone_length: rowOf("insert_zone_length", bytesValue),
  ocf_length: rowOf("ocf_length", bytesValue),
  truncated_primary_header: rowOf("truncated_primary_header", yesNoValue),
});
export type ChangeRow = Decoded<typeof changeRow>;

const craftRef = d.object({
  spacecraft_id: spacecraftIdReader,
  // free-text: a spacecraft's display name (never an id, U25)
  name: d.string,
});
export type CraftRef = Decoded<typeof craftRef>;

/**
 * A row this console can't read (a new field, a value that doesn't decode) is left out and
 * counted, never dropped silently: the approver must see that something isn't shown.
 */
const changeGroup = d.object({
  rows: perItem(changeRow, changeFields.length * 2, {
    label: "A configuration change's rows",
    kindOf: (raw) => [raw["field"]],
  }),
  first_start: d.boolean,
  /** The craft's Telemetry switch now (#109); the reviewed configuration runs with it. */
  telemetry_enabled: d.boolean,
  count: d.integer,
  spacecraft: d.array(craftRef, 100),
});
export type ChangeGroup = Decoded<typeof changeGroup>;

export const configurationChangesReader = d.object({
  groups: perItem(changeGroup, 500, {
    label: "A configuration request's changes",
    kindOf: () => ["configuration change group"],
  }),
  total: d.integer,
});
export type ConfigurationChanges = Decoded<typeof configurationChangesReader>;
export type ChangeGroups = PerItem<ChangeGroup>;

/** The detail's key: optional until api ships #235, null for other request kinds. */
export const configurationChangesField = {
  configuration_changes: d.optional(d.nullable(configurationChangesReader)),
} as const;

/** One page of a group's names (100 a page, in the request's order). */
export const groupNamesReader = d.object({
  spacecraft: d.array(craftRef, 100),
  next_offset: d.nullable(d.integer),
});
export type GroupNames = Decoded<typeof groupNamesReader>;

export type GroupNamesKey = Readonly<{
  missionId: MissionId;
  requestId: string;
  group: number;
  offset: number;
}>;

/** GET …/activations/:id/configuration-changes?group=N&offset=K (api #235; not live yet). */
export function fetchGroupNames(k: GroupNamesKey, signal: AbortSignal) {
  const path = `/missions/${encodeURIComponent(k.missionId)}/activations/${encodeURIComponent(k.requestId)}/configuration-changes`;
  return request(`${path}?group=${k.group}&offset=${k.offset}`, groupNamesReader, { signal });
}
