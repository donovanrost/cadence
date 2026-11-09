/** What a resolution needs of a U30 pass row (scheduling's UnconfirmedPass fits). */
export type ResolvablePass = Readonly<{
  snapshot_id: string;
  provider: Readonly<{ name: string | null }>;
  /** `EARENDIL-001 · KIR · 11-15 03:00Z` (design language §4), as the row shows it. */
  text: string;
}>;
