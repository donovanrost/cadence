import { plural } from "@/ui";

/** The list's own noun (ux U86 follow-up): "1 pass", "3 events"; "item" by default. */
export type UnshownNoun = "item" | "pass" | "event";
const PLURALS: Readonly<Record<UnshownNoun, string>> = {
  item: "items",
  pass: "passes",
  event: "events",
};

/** ux U86: what a list says about the items it couldn't read (n ≥ 1). */
export function unshownWords(n: number, noun: UnshownNoun = "item"): string {
  const still = n === 1 ? "it's still missing" : "they're still missing";
  return `This console can't show ${plural(n, noun, PLURALS[noun])}. Reload to try again. If ${still}, tell the team that runs Cadence for you.`;
}
