import { formatCount, type OpState } from "@/ui";

/** Only the status counts; a queue row (QueueItem) fits. */
type Stated = Readonly<{ state: OpState }>;

/** Now.md A2 'Over 100 open': the first 100 rows render in server order (render budget, 1,000 craft). */
export const QUEUE_CAP = 100;

export type Hidden = Readonly<{ count: number; crit: number; caution: number; other: number }>;

/** What the cut hides, by status. Null when nothing is hidden. */
export function hiddenRows(items: readonly Stated[], cap = QUEUE_CAP): Hidden | null {
  const rest = items.slice(cap);
  if (rest.length === 0) return null;
  const crit = rest.filter((r) => r.state === "crit").length;
  const caution = rest.filter((r) => r.state === "caution").length;
  return { count: rest.length, crit, caution, other: rest.length - crit - caution };
}

/** The button's parts after 'Show N more', zero counts left out ('▲ 412 caution · 488 other'). */
export function hiddenParts(h: Hidden): { state: "crit" | "caution" | null; text: string }[] {
  const parts: { state: "crit" | "caution" | null; text: string }[] = [];
  if (h.crit > 0) parts.push({ state: "crit", text: `${formatCount(h.crit)} crit` });
  if (h.caution > 0) parts.push({ state: "caution", text: `${formatCount(h.caution)} caution` });
  if (h.other > 0) parts.push({ state: null, text: `${formatCount(h.other)} other` });
  return parts;
}
