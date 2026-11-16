import { plural } from "@/ui";
import type { Change } from "./shapes.ts";

/**
 * ux 11-16 (lead's ask, from qa's probe): Discard always confirms, and counts only what you may
 * discard. With config.discard_any it's every change ('Discard all'); otherwise only yours.
 */
export type DiscardConfirm = Readonly<{ sentence: string; action: string }>;

/** 'Mira K., Tomás R.' — past two names, '… and 2 others'. */
function names(list: readonly string[]): string {
  if (list.length <= 2) return list.join(", ");
  return `${list.slice(0, 2).join(", ")} and ${plural(list.length - 2, "other")}`;
}

/** 'Tomás R.' already ends the sentence: don't add a second period (ux's own sentence has one). */
const sentenceEnd = (text: string) => (text.endsWith(".") ? text : `${text}.`);

export function discardConfirm(
  changes: readonly Change[],
  userId: string,
  discardAny: boolean,
): DiscardConfirm {
  const mine = changes.filter((c) => c.author.id === userId);
  const others = changes.filter((c) => c.author.id !== userId);
  // An author's name can be absent (a service or system actor): say 'someone' rather than nothing.
  const otherNames = [...new Set(others.map((c) => c.author.name ?? "someone"))];
  const gone = discardAny ? changes.length : mine.length;
  const action = `Discard ${plural(gone, "change")}`;

  if (discardAny && others.length > 0)
    return {
      sentence: `Discard all ${plural(gone, "staged change")}? ${others.length} of them ${
        others.length === 1 ? "is" : "are"
      } other people's: ${sentenceEnd(names(otherNames))} They can't be brought back.`,
      action,
    };
  if (!discardAny && others.length > 0) {
    const who = otherNames.length === 1 ? `${otherNames[0]}'s` : `${names(otherNames)}'s`;
    return {
      sentence: `Discard your ${plural(gone, "staged change")}? ${who} ${plural(others.length, "change")} ${
        others.length === 1 ? "stays" : "stay"
      } staged.`,
      action,
    };
  }
  return {
    sentence: `Discard your ${plural(gone, "staged change")}? They can't be brought back.`,
    action,
  };
}
