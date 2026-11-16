import { isKnown, type Unrecognized } from "@/api";

/**
 * A provider account's booking updates, i.e. its event ingestion mode (ux U77; lead 11-16: parity with
 * the legacy L13 registration; api-ops adds it to the account settings). Values per
 * ProviderAccountVersion, shown in this order. `p` is the provider's name wherever ux wrote Northlight.
 */
export const ingestionModes = ["polling", "webhook", "hybrid", "disabled"] as const;
export type IngestionMode = (typeof ingestionModes)[number];
/** The settings key, kept off the generic adapter schema form so these words can be used. */
export const INGESTION_PATH = "event_ingestion_mode";

export const INGESTION_LABEL = "Booking updates";
export const ingestionHint = (p: string) =>
  `How Cadence hears when ${p} confirms, moves or cancels a booking.`;

/** The value's short word ('Cadence checks', 'Northlight sends', 'Both', 'Off'). */
export function ingestionWord(m: IngestionMode, p: string): string {
  switch (m) {
    case "polling":
      return "Cadence checks";
    case "webhook":
      return `${p} sends`;
    case "hybrid":
      return "Both";
    case "disabled":
      return "Off";
  }
}

export function ingestionDescription(m: IngestionMode, p: string): string {
  switch (m) {
    case "polling":
      return `Cadence asks ${p} for changes regularly.`;
    case "webhook":
      return `${p} sends changes as they happen. Set up the webhook at ${p} first.`;
    case "hybrid":
      return `${p} sends changes as they happen, and Cadence also checks in case one is missed.`;
    case "disabled":
      return `Cadence doesn't take in ${p}'s changes.`;
  }
}

/**
 * What the console offers (api-ops 11-16): webhook and hybrid need the provider set up to post to
 * Cadence, which the console doesn't configure, so an account seeded with them reads read-only.
 */
export const offeredModes = ["polling", "disabled"] as const satisfies readonly IngestionMode[];
export type OfferedMode = (typeof offeredModes)[number];
export const isOffered = (m: IngestionMode): m is OfferedMode => offeredModes.some((o) => o === m);

export const ingestionOptions = (p: string) =>
  offeredModes.map((m) => ({ value: m, label: ingestionWord(m, p) }));

/**
 * The line under the field for a choice (U77): Off's caution, and on Edit what the change does.
 * `from` is the current mode on Edit, null on Add.
 */
export function ingestionNote(
  to: IngestionMode,
  from: IngestionMode | null,
  p: string,
): Readonly<{ tone: "caution" | "info"; text: string }> | null {
  if (to === "disabled") {
    if (from === null)
      return {
        tone: "caution",
        text: `While this is off, Cadence won't see ${p} confirm, move or cancel bookings. Turn it on in Edit when the account is ready.`,
      };
    if (from === "disabled") return null;
    return {
      tone: "caution",
      text: `While this is off, Cadence won't see ${p} confirm, move or cancel the bookings made with this account.`,
    };
  }
  if (from === "disabled")
    return { tone: "info", text: `Cadence starts taking in ${p}'s changes when you save.` };
  if (to === "webhook" && (from === "polling" || from === "hybrid"))
    return {
      tone: "caution",
      text: `Cadence will stop checking. Make sure ${p}'s webhook is set up, or changes will be missed.`,
    };
  return null;
}

/** Edit's Save label: turning updates off says so (U77). */
export const ingestionSaveLabel = (to: IngestionMode | null, from: IngestionMode | null) =>
  to === "disabled" && from !== null && from !== "disabled" ? "Save and turn off updates" : "Save";

/** The account page's read-back value; Off adds its consequence (U77). Null when not read. */
export function ingestionReadBack(
  mode: IngestionMode | Unrecognized | null | undefined,
  p: string,
): Readonly<{ value: string; off: string | null }> | null {
  if (mode == null) return null;
  if (!isKnown(mode)) return { value: mode.unrecognized.replaceAll("_", " "), off: null };
  return {
    value: ingestionWord(mode, p),
    off: mode === "disabled" ? `Cadence won't see ${p}'s booking changes.` : null,
  };
}
