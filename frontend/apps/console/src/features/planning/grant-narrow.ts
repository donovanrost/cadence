import { grantActions, type Grant, type NarrowChanges } from "./grants.ts";

/**
 * U105 Narrow…: the sheet offers the grant's own values and only less (actions a subset, each
 * limit and Valid for at most what it has now). The server judges every field again (422
 * automation_grant_not_narrower is the backstop).
 */
export type NarrowDraft = Readonly<{
  actions: readonly string[];
  hours: string;
  contacts: string;
  concurrency: string;
  days: string;
}>;

const known = (g: Grant) =>
  g.allowed_actions.filter((a): a is (typeof grantActions)[number] => a !== "unrecognized");
/** A grant with an action the console can't name keeps its actions as they are (never dropped unseen). */
export const actionsNarrowable = (g: Grant) => !g.allowed_actions.includes("unrecognized");
const show = (n: number) => String(Number.isInteger(n) ? n : Number(n.toFixed(2)));

/** The sheet's starting values: what the grant allows now. */
export function narrowDraft(g: Grant): NarrowDraft {
  return {
    actions: known(g),
    hours: show(g.maximum_horizon_seconds / 3600),
    contacts: String(g.maximum_contacts),
    concurrency: String(g.maximum_execution_concurrency),
    days: g.validity_seconds === null ? "" : show(g.validity_seconds / 86_400),
  };
}

/** U105's up-front reason while nothing is narrower (A6/A7). */
export const NOTHING_NARROWER = "Choose less than the grant allows now.";
const MORE = "That's more than the grant allows now. To widen it, propose a new grant.";
const whole = (text: string) => (/^\d+$/.test(text.trim()) ? Number(text.trim()) : null);

type Limit = Readonly<{
  key: keyof NarrowDraft & ("hours" | "contacts" | "concurrency" | "days");
  field:
    | "maximum_horizon_seconds"
    | "maximum_contacts"
    | "maximum_execution_concurrency"
    | "validity_seconds";
  unit: number;
}>;
const LIMITS: readonly Limit[] = [
  { key: "hours", field: "maximum_horizon_seconds", unit: 3600 },
  { key: "contacts", field: "maximum_contacts", unit: 1 },
  { key: "concurrency", field: "maximum_execution_concurrency", unit: 1 },
  { key: "days", field: "validity_seconds", unit: 86_400 },
];

export type NarrowBuilt =
  | Readonly<{ ok: true; changes: NarrowChanges }>
  | Readonly<{ ok: false; why: string; errors: Readonly<Record<string, string>> }>;

/** The narrow body's `changes` (only the fields that shrink), or why it can't go yet. */
export function narrowChanges(g: Grant, draft: NarrowDraft): NarrowBuilt {
  const start = narrowDraft(g);
  const errors: Record<string, string> = {};
  const changes: {
    allowed_actions?: readonly string[];
    maximum_horizon_seconds?: number;
    maximum_contacts?: number;
    maximum_execution_concurrency?: number;
    validity_seconds?: number;
  } = {};
  for (const limit of LIMITS) {
    const text = draft[limit.key];
    if (text.trim() === start[limit.key].trim()) continue;
    const now = g[limit.field];
    const n = whole(text);
    if (n === null || n === 0) errors[limit.key] = "Enter a whole number above 0.";
    else if (now !== null && n * limit.unit > now) errors[limit.key] = MORE;
    else if (now === null || n * limit.unit < now) changes[limit.field] = n * limit.unit;
  }
  const current = known(g);
  if (draft.actions.length === 0) errors["actions"] = "Keep at least one.";
  else if (draft.actions.some((a) => !current.some((c) => c === a))) errors["actions"] = MORE;
  else if (actionsNarrowable(g) && draft.actions.length < current.length)
    changes["allowed_actions"] = current.filter((c) => draft.actions.includes(c));
  if (Object.keys(errors).length > 0)
    return { ok: false, why: Object.values(errors)[0] ?? NOTHING_NARROWER, errors };
  if (Object.keys(changes).length === 0) return { ok: false, why: NOTHING_NARROWER, errors };
  return { ok: true, changes };
}
