import {
  visible,
  type Change,
  type FormRules,
  type FormState,
  type SchemaField,
} from "@/features/changes/index.ts";

/**
 * U83: a listen-mode downlink transport's listener, own or shared (U85: the direction reads
 * Downlink/Uplink/Both; its stored values stay inbound/outbound/bidirectional). The stored document
 * holds `listener: "shared"` or no key (missing reads as own; api). When an edit hides the field over
 * a stored shared listener (connect, uplink or both), the transport goes back to its own
 * listener: own is sent in the same stage, since the stored shared would be refused (api).
 */
export const LISTENER = "configuration.listener";
const WHY = "only a downlink transport that listens can share one";
export const STOPS_SHARING = `This transport will stop sharing its listener: ${WHY}.`;

const field = (s: FormState): SchemaField | undefined =>
  s.schema.fields.find((f) => f.path === LISTENER);
const storedShared = (s: FormState) => s.before[LISTENER] === "shared";
/** The edit hides the listener over a stored shared one. */
const stopsSharing = (s: FormState) => {
  const f = field(s);
  return f !== undefined && storedShared(s) && !visible(f, s.values);
};
/** An option's words from the schema; missing is own (api). */
const words = (s: FormState, value: string) =>
  field(s)?.enum?.find((o) => o.value === (value || "own"))?.label ?? (value || "own");

export const listenerRules: FormRules = {
  // Switching back before staging shows Own chosen (ux U83).
  reconcile: (s) => (stopsSharing(s) ? { ...s.values, [LISTENER]: "own" } : s.values),
  finish: (changes, s) => {
    const others = changes.filter((c) => c.path !== LISTENER);
    if (stopsSharing(s)) return [...others, { path: LISTENER, value: "own" }];
    // Own over a missing key is no change (api).
    const own = changes.some((c) => c.path === LISTENER && c.value === "own");
    return own && !storedShared(s) ? others : changes;
  },
  notes: (s) => {
    if (!stopsSharing(s)) return {};
    // Under the field that changed: the first of mode and direction, in form order.
    const changed = s.schema.fields.find(
      (f) =>
        f.path !== LISTENER && f.visible_when === null && s.values[f.path] !== s.before[f.path],
    );
    return changed ? { [changed.path]: STOPS_SHARING } : {};
  },
  describe: (c: Change, s) =>
    c.path !== LISTENER || typeof c.value !== "string"
      ? null
      : `Listener: ${words(s, s.before[LISTENER] ?? "")} → ${words(s, c.value)}${
          stopsSharing(s) ? ` (${WHY})` : ""
        }`,
};
