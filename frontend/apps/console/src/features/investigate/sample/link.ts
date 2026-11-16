/**
 * ux U80: the query keys that open the Sample aside on the Telemetry tab, next to points/focus/at.
 * Nothing when the sample has no id (catalog monitoring): the link only rings the time then.
 */
export function sampleQuery(
  id: string | null,
  received: string | null | undefined,
): Record<string, string> {
  return id ? { sample: id, ...(received ? { received } : {}) } : {};
}
