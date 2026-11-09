/**
 * Station bar items for the commanding takeover header (CommandFlow: Compose → Check → Approve →
 * Release → Radiate → Acknowledge → Verify). Several stations can be current at once (Uplink:
 * 05–07 run together). Done stations before `collapseDoneBefore` fold into one `✓ 01–04` item;
 * future stations from `collapseFutureFrom` fold into one gray `05 · 06 · 07` item.
 */
export type StationState = "done" | "current" | "future";
export type StationItem = Readonly<{
  key: string;
  /** Visible text, e.g. `03 Approve`, `01–04`, `05 · 06 · 07`. */
  text: string;
  /** Full names for assistive tech. */
  label: string;
  state: StationState;
  collapsed: boolean;
}>;

const num = (i: number) => String(i + 1).padStart(2, "0");

export function stationItems(
  steps: readonly string[],
  current: readonly number[],
  options: Readonly<{
    collapseDoneBefore?: number | undefined;
    collapseFutureFrom?: number | undefined;
  }> = {},
): StationItem[] {
  const first = Math.min(...current);
  const state = (i: number): StationState =>
    current.includes(i) ? "current" : i < first ? "done" : "future";
  const items: StationItem[] = [];
  const doneEnd = options.collapseDoneBefore ?? 0;
  if (doneEnd > 1 && steps.slice(0, doneEnd).every((_, i) => state(i) === "done")) {
    items.push({
      key: "done",
      text: `${num(0)}–${num(doneEnd - 1)}`,
      label: `${steps.slice(0, doneEnd).join(", ")} (done)`,
      state: "done",
      collapsed: true,
    });
  }
  const start = items.length > 0 ? doneEnd : 0;
  const futureFrom = options.collapseFutureFrom ?? steps.length;
  const foldFuture = steps.slice(futureFrom).every((_, k) => state(futureFrom + k) === "future");
  steps.forEach((name, i) => {
    if (i < start || (foldFuture && i >= futureFrom)) return;
    items.push({
      key: String(i),
      text: `${num(i)} ${name}`,
      label: name,
      state: state(i),
      collapsed: false,
    });
  });
  if (foldFuture && futureFrom < steps.length) {
    items.push({
      key: "future",
      text: steps
        .slice(futureFrom)
        .map((_, k) => num(futureFrom + k))
        .join(" · "),
      label: `${steps.slice(futureFrom).join(", ")} (later)`,
      state: "future",
      collapsed: true,
    });
  }
  return items;
}
