import { plural } from "@/ui";

/** ux U86: what a list says about the items it couldn't read (n ≥ 1). */
export function unshownWords(n: number): string {
  const still = n === 1 ? "it's still missing" : "they're still missing";
  return `This console can't show ${plural(n, "item")}. Reload to try again. If ${still}, tell the team that runs Cadence for you.`;
}
