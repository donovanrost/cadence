import type { Ref } from "vue";
import { usePagedQuery, type PageFetcher } from "@/api";
import { fetchAudit, type AuditEvent, type AuditPage, type AuditQuery } from "./api.ts";

/** A page's envelope besides its events: the sources it covered and the events it left out (U86). */
export type AuditPageMeta = Pick<AuditPage, "sources" | "unshown">;

const fetchPage: PageFetcher<AuditQuery, AuditEvent, AuditPageMeta> = async (
  query,
  cursor,
  signal,
) => {
  const r = await fetchAudit(cursor ? { ...query, cursor } : query, signal);
  if (!r.ok) return r;
  const { events, next_cursor: next, sources, unshown } = r.value;
  return { ok: true, value: { items: events, next, meta: { sources, unshown } } };
};

/**
 * The audit log in pages (usePagedQuery): Load older appends the next page for the same query
 * (its window end is fixed, so later pages read the same window); a refetch reloads up to the
 * events shown.
 */
export const useAuditLog = (query: Ref<AuditQuery | null>) =>
  usePagedQuery(query, fetchPage, (event) => event.id);
