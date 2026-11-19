import type { KindSchema, StageOp } from "@/features/changes/index.ts";
import type { SpacecraftDetail } from "./detail.ts";

/** One U40 Operation row: the switch's running value (null: no active configuration says). */
export type OperationRow = Readonly<{
  key: "commanding_enabled" | "telemetry_enabled";
  label: string;
  on: boolean | null;
  sentence: string;
}>;

/**
 * U40 Operation panel: the Commanding and Telemetry switches as the active configuration runs them.
 * Their help comes from the spacecraft kind's schema (`switchHelp`), so it can't drift from api's.
 */
export function operationRows(d: SpacecraftDetail): readonly OperationRow[] {
  const name = d.spacecraft.name;
  // ux U40: names the spacecraft and why, without hinting at on or off.
  const unknown = `No active configuration covers ${name} yet, so this isn't set.`;
  const commanding = d.commanding_enabled ?? null;
  const telemetry = d.telemetry_enabled ?? null;
  return [
    {
      key: "commanding_enabled",
      label: "Commanding",
      on: commanding,
      sentence:
        commanding === null
          ? unknown
          : commanding
            ? `Operators can request and release commands to ${name}.`
            : `No new requests or releases for ${name}.`,
    },
    {
      key: "telemetry_enabled",
      label: "Telemetry",
      on: telemetry,
      sentence:
        telemetry === null
          ? unknown
          : telemetry
            ? `Cadence decodes telemetry from ${name}.`
            : `Cadence doesn't decode telemetry from ${name}: no live values, alarms or new history.`,
    },
  ];
}

/** A switch's help as the spacecraft kind's schema serves it (ux U40 text, api L17); null until read. */
export function switchHelp(schema: KindSchema | null, key: OperationRow["key"]): string | null {
  return schema?.fields.find((f) => f.path === key)?.help ?? null;
}

export type SwitchKey = OperationRow["key"];
const NOUN = {
  commanding_enabled: "commanding",
  telemetry_enabled: "telemetry",
} as const satisfies Record<SwitchKey, string>;

/** U40's Changes line: "EARENDIL-312 · turn commanding off". */
export const switchSummary = (name: string, key: SwitchKey, on: boolean): string =>
  `${name} · turn ${NOUN[key]} ${on ? "on" : "off"}`;

/** U40: the off sheet's title and the consequence it states before anything is staged (#309). */
export const offTitle = (name: string, key: SwitchKey): string =>
  `Turn ${NOUN[key]} off for ${name}?`;
export const offConsequence = (name: string, key: SwitchKey): string =>
  key === "commanding_enabled"
    ? `Turning commanding off stops new requests and releases for ${name}.`
    : `No live values, alarms or new history from ${name} until it's turned on again.`;

/** The staged change: the spacecraft kind's switch path, as the Edit form stages it (L17). */
export const switchOp = (spacecraftId: string, key: SwitchKey, on: boolean): StageOp => ({
  kind: "spacecraft",
  action: "update",
  entity_id: spacecraftId,
  changes: [{ path: key, value: on }],
});

/**
 * The switch value the open set stages for this spacecraft, or null when it stages none. Read
 * from its ops' `payload.changes` (the server's staged value), never inferred. The last one wins:
 * a re-stage by the same author replaces the earlier op (api changes.md), and reading the last
 * stays right if two ever coexist (mms-ux, #427).
 */
/** The parts of a change set this reads (a ChangeSet fits). */
type StagedOps = Readonly<{
  changes: readonly Readonly<{
    ops: readonly Readonly<{
      kind: unknown;
      entity_id: string | null;
      paths: readonly string[];
      payload: unknown;
    }>[];
  }>[];
}>;
export function stagedSwitch(
  set: StagedOps | null | undefined,
  spacecraftId: string,
  key: SwitchKey,
): boolean | null {
  let staged: boolean | null = null;
  for (const change of set?.changes ?? [])
    for (const op of change.ops) {
      if (op.kind !== "spacecraft" || op.entity_id !== spacecraftId || !op.paths.includes(key))
        continue;
      const value = changeValue(op.payload, key);
      if (typeof value === "boolean") staged = value;
    }
  return staged;
}

/**
 * 409 path_already_staged: someone else's open change already sets this switch (mms-ux, #427).
 * The way back is that change, in Setup › Changes.
 */
export const alreadyStagedLine = (name: string, key: SwitchKey): string =>
  `Not staged: ${NOUN[key]} is already staged for ${name} in the open change set. Discard that change in Setup › Changes to undo it.`;

function changeValue(payload: unknown, path: string): unknown {
  if (typeof payload !== "object" || payload === null || !("changes" in payload)) return undefined;
  const changes = payload.changes;
  if (!Array.isArray(changes)) return undefined;
  for (const c of changes as unknown[])
    if (typeof c === "object" && c !== null && "path" in c && c.path === path && "value" in c)
      return c.value;
  return undefined;
}
