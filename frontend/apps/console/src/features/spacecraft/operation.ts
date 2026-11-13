import type { SpacecraftDetail } from "./detail.ts";

/** One U40 Operation row: the switch's running value (null: no active configuration says). */
export type OperationRow = Readonly<{
  key: "commanding_enabled" | "telemetry_enabled";
  label: string;
  help: string;
  on: boolean | null;
  sentence: string;
}>;

/** U40 Operation panel: the Commanding and Telemetry switches as the active configuration runs them. */
export function operationRows(d: SpacecraftDetail): readonly OperationRow[] {
  const name = d.spacecraft.name;
  const unknown = "No active configuration sets this yet.";
  const commanding = d.commanding_enabled ?? null;
  const telemetry = d.telemetry_enabled ?? null;
  return [
    {
      key: "commanding_enabled",
      label: "Commanding",
      help: "Lets operators request and release commands to this spacecraft. Turning it off cancels commands still waiting to be sent when the change is applied.",
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
      help: "Cadence decodes this spacecraft's telemetry into live values, alarms and history. Turning it off means no new live values, alarms or history until it's turned on again.",
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
