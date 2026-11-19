/** What a resolution needs of a U30 pass row (scheduling's UnconfirmedPass fits). */
export type ResolvablePass = Readonly<{
  snapshot_id: string;
  /** null when no provider is recorded yet (api drift sweep 11-13). */
  provider: Readonly<{ name: string | null }> | null;
  /** `EARENDIL-001 · KIR · 11-15 03:00Z` (design language §4), as the row shows it. */
  text: string;
}>;
