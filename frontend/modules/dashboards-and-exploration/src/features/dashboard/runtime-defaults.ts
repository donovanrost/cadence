import {
  parseRuntimeDefaults,
  runtimeDefaultsMaxBytes,
  type RuntimeDefaults,
} from "../../shared/runtime-defaults";
export {
  parseRuntimeDefaults,
  runtimeDefaultsMaxBytes,
  type RuntimeDefaults,
} from "../../shared/runtime-defaults";
const bytes = (text: string) => new TextEncoder().encode(text).length;
function object(value: unknown): value is RuntimeDefaults {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function formatRuntimeDefaults(value: RuntimeDefaults): string {
  const pretty = JSON.stringify(value, null, 2);
  return bytes(pretty) <= runtimeDefaultsMaxBytes ? pretty : JSON.stringify(value);
}

// Quick controls patch only their own field. Source contexts, scopes, overlays,
// and future domain settings remain intact in the complete authored document.
export function setRuntimeDefault(
  json: string,
  context: string,
  key: string,
  value: string,
): string {
  const defaults = parseRuntimeDefaults(json);
  const current = defaults[context];
  if (current !== undefined && current !== null && !object(current))
    throw Error("Repair this context in the full JSON document before using quick controls.");
  const next = { ...(current as RuntimeDefaults | null | undefined) };
  if (value === "") delete next[key];
  else next[key] = value;
  // Define an own property even for special JSON keys; never traverse prototypes.
  Object.defineProperty(defaults, context, { value: next, enumerable: true, configurable: true });
  return formatRuntimeDefaults(defaults);
}

export const runtimeQuickFields = [
  {
    context: "time",
    key: "mode",
    label: "Time mode",
    values: ["live", "range", "archive", "replay_run"],
  },
  { context: "time", key: "axis", label: "Time axis", values: ["generation_time", "receipt_time"] },
  {
    context: "data",
    key: "realm",
    label: "Data realm",
    values: ["flight", "rehearsal", "replay", "simulation"],
  },
  {
    context: "data",
    key: "source_mode",
    label: "Source selection",
    values: ["primary", "bound", "specific"],
  },
  {
    context: "data",
    key: "view",
    label: "Data view",
    values: ["canonical", "as_recorded", "all_revisions", "recomputed"],
  },
  {
    context: "limits",
    key: "semantics_mode",
    label: "Limit semantics",
    values: ["observed", "current", "recomputed", "compare"],
  },
] as const;
