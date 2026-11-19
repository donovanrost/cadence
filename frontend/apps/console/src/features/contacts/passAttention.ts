import type { Unshown } from "@/api/index.ts";
import { plural } from "@/ui";
import type { Attention } from "@/features/now/index.ts";
import type { Pass } from "./api.ts";

/**
 * ux U45 (recorded): a pass shows its top attention item (api's order: priority, soonest due,
 * contact_start on ties) as a tag, with the rest counted beside it; the pass detail lists them all.
 */
type WithAttention = Pick<
  Pass,
  "attention" | "attentions" | "attention_unshown" | "attentions_unshown"
>;

/** The pass's open items, top first; `attention` alone until api sends `attentions`. */
export const passAttentions = (p: WithAttention): readonly Attention[] =>
  p.attentions ?? (p.attention ? [p.attention] : []);

/** U86: the pass's open items this console couldn't read (from the same list). */
export function passUnshown(p: WithAttention): readonly Unshown[] {
  if (p.attentions !== undefined) return p.attentions_unshown ?? [];
  return p.attention_unshown ? [p.attention_unshown] : [];
}

export type PassAttentionTag = Readonly<{ state: "caution" | "crit"; label: string; more: number }>;

/** ▲ NOT STARTED (caution) · ◆ MISSED (crit) · anything else needs attention (caution). */
export function passAttentionTag(p: WithAttention): PassAttentionTag | null {
  const [top, ...rest] = passAttentions(p);
  // U86: an item this console can't read is still open, so it counts, and alone it still tags.
  const unshown = passUnshown(p).length;
  if (!top)
    return unshown ? { state: "caution", label: "Needs attention", more: unshown - 1 } : null;
  const more = rest.length + unshown;
  if (top.source === "contact_start")
    return top.conflict === "missed"
      ? { state: "crit", label: "Missed", more }
      : { state: "caution", label: "Not started", more };
  return { state: "caution", label: "Needs attention", more };
}

/** The bar's screen-reader tail: ", hasn't started, and 2 more items" (ux: no parentheses). */
export function passAttentionDescription(p: WithAttention): string {
  const tag = passAttentionTag(p);
  if (!tag) return "";
  const what =
    tag.label === "Missed"
      ? "was missed"
      : tag.label === "Not started"
        ? "hasn't started"
        : "needs attention";
  return `, ${what}${tag.more ? `, and ${plural(tag.more, "more item", "more items")}` : ""}`;
}
