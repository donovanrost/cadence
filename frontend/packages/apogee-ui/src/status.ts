/** Operational state grammar: shape + color + word, never color alone (design-language §2). */
export type OpState =
  | "crit"
  | "caution"
  | "stale"
  | "nominal"
  | "off"
  | "live"
  | "neutral"
  | "optional";

/** Text tint utility for a state's word or value (≥4.5:1 on panel). */
export function stateTextClass(state: OpState): string {
  switch (state) {
    case "crit":
      return "text-crit-text";
    case "caution":
      return "text-caution-text";
    case "stale":
      return "text-stale-text";
    case "nominal":
      return "text-nominal-text";
    case "off":
    case "optional":
    case "neutral":
      return "text-text-3";
    case "live":
      return "text-readout";
  }
}

/** Inset 2px top bar marking a non-nominal tile. Empty for states that carry no accent. */
export function stateInsetClass(state: OpState): string {
  switch (state) {
    case "crit":
      return "shadow-[inset_0_2px_0_var(--color-crit)]";
    case "caution":
      return "shadow-[inset_0_2px_0_var(--color-caution)]";
    case "stale":
      return "shadow-[inset_0_2px_0_var(--color-stale)]";
    case "live":
      return "shadow-[inset_0_2px_0_var(--color-readout)]";
    case "nominal":
    case "off":
    case "optional":
    case "neutral":
      return "";
  }
}

/** Default word for a state when the caller has none more specific. */
export function stateWord(state: OpState): string {
  switch (state) {
    case "crit":
      return "Critical";
    case "caution":
      return "Caution";
    case "stale":
      return "Stale";
    case "nominal":
      return "Nominal";
    case "off":
      return "Not set up";
    case "live":
      return "Live";
    case "neutral":
      return "";
    case "optional":
      return "Optional";
  }
}
