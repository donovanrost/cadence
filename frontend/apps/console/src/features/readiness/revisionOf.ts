/** "r3" → "3", for the revision page; anything else (v4, app) stays plain text. */
export const revisionOf = (label: string | null) =>
  label && /^r\d+$/.test(label) ? label.slice(1) : null;

/**
 * `Compare r3 ↔ r6` (Setup.md R2, Changes.md §4): the combined diff of the revisions shown, from
 * the one before the oldest (r1 has none before it). Needs two revisions to say anything.
 */
export function compareSpan(
  labels: readonly (string | null)[],
): Readonly<{ from: string; to: string }> | null {
  const numbers = labels.map((l) => Number(revisionOf(l))).filter((n) => n > 0);
  if (numbers.length < 2) return null;
  const to = Math.max(...numbers);
  const from = Math.max(1, Math.min(...numbers) - 1);
  return from < to ? { from: String(from), to: String(to) } : null;
}
