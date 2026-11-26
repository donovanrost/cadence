import { requestPage, type ApiResult, type MissionId, type Unshown } from "@/api/index.ts";
import { passReader, type Pass, type Passes } from "./api.ts";
import { PASS_PAGE_LIMIT, passPageReader } from "./passList.ts";

/** One page of GET /passes; fetchPasses walks them (exported for decoder tests). */
export const passesPageReader = passPageReader(passReader);
/**
 * Every pass in the window (#793): pages of 500 walked to the server's last cursor, each request
 * with the same window and filters (the cursor is bound to them; api #845). The counts are the
 * whole window's, from the first page. A failed page fails the read; nothing is shown cut short.
 */
export async function fetchPasses(
  missionId: MissionId,
  query: Readonly<{ from: Date; to: Date; spacecraftId?: string; station?: string }>,
  signal?: AbortSignal,
): Promise<ApiResult<Passes>> {
  const params = new URLSearchParams({
    from: query.from.toISOString(),
    to: query.to.toISOString(),
    limit: String(PASS_PAGE_LIMIT),
  });
  if (query.spacecraftId) params.set("spacecraft_id", query.spacecraftId);
  if (query.station) params.set("station", query.station);
  const path = `/missions/${encodeURIComponent(missionId)}/passes`;
  const options = signal ? { signal } : {};
  const page = (cursor: string | null) => {
    if (cursor !== null) params.set("cursor", cursor);
    return requestPage(`${path}?${params.toString()}`, passesPageReader, options);
  };
  const first = await page(null);
  if (!first.ok) return first;
  const { from, to, counts } = first.value.value;
  const passes: Pass[] = [...first.value.value.passes];
  const unshown: Unshown[] = [...first.value.value.unshown];
  let cursor = first.value.nextCursor;
  while (cursor !== null) {
    const next = await page(cursor);
    if (!next.ok) return next;
    passes.push(...next.value.value.passes);
    unshown.push(...next.value.value.unshown);
    cursor = next.value.nextCursor;
  }
  return { ok: true, value: { from, to, counts, passes, unshown } };
}
