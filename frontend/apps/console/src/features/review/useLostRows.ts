import type { Ref } from "vue";
import { usePagedQuery, type PageFetcher } from "@/api";
import { fetchLost, type ReviewKey, type ReviewRow, type ReviewRows } from "./api.ts";

/** A page's envelope besides its rows: how many lost passes match and how many are disputable. */
export type LostMeta = Pick<ReviewRows, "total" | "disputable">;

const fetchPage: PageFetcher<ReviewKey, ReviewRow, LostMeta> = async (key, cursor, signal) => {
  const r = await fetchLost(cursor ? { ...key, cursor } : key, signal);
  if (!r.ok) return r;
  const { rows, total, disputable, next_cursor: next } = r.value;
  return { ok: true, value: { items: rows, next: next ?? null, meta: { total, disputable } } };
};

/**
 * R4's lost passes in pages (usePagedQuery): Load more appends the next 50 for the same window; a
 * live `pass_results` refetch reloads up to the rows shown (a failed refresh keeps them, silently:
 * the strip and the other panels refresh on their own).
 */
export const useLostRows = (key: Ref<ReviewKey>) => usePagedQuery(key, fetchPage, (row) => row.id);
