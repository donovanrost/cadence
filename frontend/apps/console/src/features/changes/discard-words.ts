import { plural } from "@/ui";
import type { Change } from "./shapes.ts";

/**
 * ux 11-16 (lead's ask, from qa's probe; screens/Changes.md): Discard always confirms, and counts
 * only what you may discard. With config.discard_any it's every change ('Discard all'); otherwise
 * only yours.
 */
export type DiscardConfirm = Readonly<{ sentence: string; action: string }>;

/** The other people whose changes are in the set: named ones first, unnamed ones only counted. */
function otherAuthors(others: readonly Change[]) {
  const named = new Map<string, string>();
  const unnamed = new Set<string>();
  others.forEach((c, i) => {
    const key = c.author.id ?? `#${i}`;
    if (c.author.name) named.set(key, c.author.name);
    else unnamed.add(key);
  });
  return { named: [...named.values()], unnamed: unnamed.size, total: named.size + unnamed.size };
}

/** 'Mira K., Tomás R.' — past two names (and every unnamed author), '… and N others'. */
function nameList(named: readonly string[], unnamed: number): string {
  const shown = named.slice(0, 2);
  const rest = named.length - shown.length + unnamed;
  return rest > 0 ? `${shown.join(", ")} and ${plural(rest, "other")}` : shown.join(", ");
}

/** 'Tomás R.' already ends the sentence: don't add a second period. */
const sentenceEnd = (text: string) => (text.endsWith(".") ? text : `${text}.`);
const are = (n: number) => (n === 1 ? "is" : "are");

function allSentence(gone: number, others: readonly Change[]): string {
  const who = otherAuthors(others);
  const head = `Discard all ${plural(gone, "staged change")}? ${others.length} of them ${are(others.length)}`;
  const tail = "They can't be brought back.";
  if (who.total === 1 && who.named.length === 1) return `${head} ${who.named[0]}'s. ${tail}`;
  if (who.named.length === 0) return `${head} other people's. ${tail}`;
  return `${head} other people's: ${sentenceEnd(nameList(who.named, who.unnamed))} ${tail}`;
}

function mineSentence(gone: number, others: readonly Change[]): string {
  const who = otherAuthors(others);
  const stay = others.length === 1 ? "stays" : "stay";
  const kept =
    who.total === 1 && who.named.length === 1
      ? `${who.named[0]}'s ${plural(others.length, "change")} ${stay} staged.`
      : `${plural(others.length, "change")} by other people ${stay} staged.`;
  return `Discard your ${plural(gone, "staged change")}? ${kept}`;
}

export function discardConfirm(
  changes: readonly Change[],
  userId: string,
  discardAny: boolean,
): DiscardConfirm {
  const mine = changes.filter((c) => c.author.id === userId);
  const others = changes.filter((c) => c.author.id !== userId);
  const gone = discardAny ? changes.length : mine.length;
  const action = `Discard ${plural(gone, "change")}`;
  if (others.length === 0)
    return {
      sentence: `Discard your ${plural(gone, "staged change")}? They can't be brought back.`,
      action,
    };
  return { sentence: discardAny ? allSentence(gone, others) : mineSentence(gone, others), action };
}
