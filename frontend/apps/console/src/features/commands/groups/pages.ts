import {
  decoders as d,
  requestPageMeta,
  type ApiResult,
  type MissionId,
  type Page,
} from "@/api/index.ts";
import type { MemberStage } from "./api.ts";
import { groupsBase } from "./api.ts";
import {
  eventReader,
  targetReader,
  type EventKind,
  type GroupEvent,
  type GroupTarget,
} from "./show.ts";

/**
 * #795 (commanding.md "Paged targets and events"): a group's targets and events a page at a time,
 * so a group of thousands of targets is never read whole. Cursors are opaque and belong to their
 * group and list; `meta.total` counts what the filters keep.
 */

/** The server's most per page: targets 500, events 200. */
export const TARGETS_PAGE = 100;
export const EVENTS_PAGE = 50;

const totalReader = d.object({ total: d.integer });
export type PageTotal = Readonly<{ total: number }>;

export type TargetsKey = Readonly<{
  missionId: MissionId;
  groupId: string;
  /** Target stages to keep (the target's own); empty keeps every stage. */
  stages?: readonly MemberStage[];
  /** A case-insensitive substring of the name or spacecraft id (at most 100 characters). */
  q?: string;
  /** Needs you's targets: failed or uncertain, or held behind a release of unknown outcome. */
  needsYou?: boolean;
  limit?: number;
}>;

const base = (missionId: MissionId, groupId: string) =>
  `${groupsBase(missionId)}/${encodeURIComponent(groupId)}`;

export async function fetchTargetsPage(
  key: TargetsKey,
  cursor: string | null,
  signal: AbortSignal,
): Promise<ApiResult<Page<GroupTarget, PageTotal>>> {
  const params = new URLSearchParams({ limit: String(key.limit ?? TARGETS_PAGE) });
  if (key.stages?.length) params.set("stage", key.stages.join(","));
  if (key.q) params.set("q", key.q.slice(0, 100));
  if (key.needsYou) params.set("needs_you", "true");
  if (cursor !== null) params.set("cursor", cursor);
  const r = await requestPageMeta(
    `${base(key.missionId, key.groupId)}/targets?${params.toString()}`,
    d.object({ targets: d.array(targetReader, 500) }),
    totalReader,
    { signal },
  );
  if (!r.ok) return r;
  return {
    ok: true,
    value: { items: r.value.value.targets, next: r.value.nextCursor, meta: r.value.meta },
  };
}

export type EventsKey = Readonly<{
  missionId: MissionId;
  groupId: string;
  /** Event kinds to keep; empty keeps every kind. */
  kinds?: readonly EventKind[];
  limit?: number;
}>;

/** A page of events: the first page is the latest; the cursor reads back to older ones. */
export async function fetchEventsPage(
  key: EventsKey,
  cursor: string | null,
  signal: AbortSignal,
): Promise<ApiResult<Page<GroupEvent, PageTotal>>> {
  const params = new URLSearchParams({ limit: String(key.limit ?? EVENTS_PAGE) });
  if (key.kinds?.length) params.set("kind", key.kinds.join(","));
  if (cursor !== null) params.set("cursor", cursor);
  const r = await requestPageMeta(
    `${base(key.missionId, key.groupId)}/events?${params.toString()}`,
    d.object({ events: d.array(eventReader, 200) }),
    totalReader,
    { signal },
  );
  if (!r.ok) return r;
  return {
    ok: true,
    value: { items: r.value.value.events, next: r.value.nextCursor, meta: r.value.meta },
  };
}

/** The most pages a walk reads: max_targets (5,000) at 500 a page, so a runaway cursor ends. */
const MAX_PAGES = 10;

/**
 * Every target of a group, 500 a page (Compose's resend clone needs them all). Bounded by the size
 * guard; a runaway cursor ends in a failure, never a loop.
 */
export async function fetchAllTargets(
  key: Omit<TargetsKey, "limit">,
  signal: AbortSignal,
): Promise<ApiResult<readonly GroupTarget[]>> {
  const out: GroupTarget[] = [];
  let cursor: string | null = null;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const r: ApiResult<Page<GroupTarget, PageTotal>> = await fetchTargetsPage(
      { ...key, limit: 500 },
      cursor,
      signal,
    );
    if (!r.ok) return r;
    out.push(...r.value.items);
    cursor = r.value.next;
    if (cursor === null) return { ok: true, value: out };
  }
  return {
    ok: false,
    error: { kind: "malformed", message: "the group has more target pages than its size guard" },
  };
}

/** Every event of the given kinds (a few: hold_acknowledged is written once per HOLD at submit). */
export async function fetchAllEvents(
  key: Omit<EventsKey, "limit">,
  signal: AbortSignal,
): Promise<ApiResult<readonly GroupEvent[]>> {
  const out: GroupEvent[] = [];
  let cursor: string | null = null;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const r: ApiResult<Page<GroupEvent, PageTotal>> = await fetchEventsPage(
      { ...key, limit: 200 },
      cursor,
      signal,
    );
    if (!r.ok) return r;
    out.unshift(...r.value.items);
    cursor = r.value.next;
    if (cursor === null) return { ok: true, value: out };
  }
  return {
    ok: false,
    error: { kind: "malformed", message: "the group has more event pages than expected" },
  };
}
