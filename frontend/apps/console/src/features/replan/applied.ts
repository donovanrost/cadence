/**
 * An applied repair proposal books only: S8 keeps every committed pass locked, so moves and
 * adds are bookings and drops send nothing (no cancellations to name, ux rule (a)).
 */
export function bookingRequests(
  diff: Readonly<{ moved: readonly unknown[]; added: readonly unknown[] }>,
): number {
  return diff.moved.length + diff.added.length;
}
