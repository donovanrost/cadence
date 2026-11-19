import type { KindSchema } from "@/features/changes/index.ts";
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
