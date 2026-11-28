import {
  decoders as d,
  isKnown,
  request,
  requestPage,
  role,
  type ApiResult,
  type Decoded,
  type Page,
  type Role,
} from "@/api";
import type { SessionOrganization } from "@/api/session.ts";
import type { RouteLocationRaw } from "vue-router";

/**
 * #709 (session.md "Account: notices"): the signed-in person's notices, the legacy bell's. The
 * server lists only the kinds the console words, and `unread_notices_count` counts the same rows.
 */
export const noticeKinds = ["organization_access_granted"] as const;

export const noticeReader = d.object({
  id: d.token,
  kind: d.known(noticeKinds),
  organization: d.object({
    id: d.token,
    // free-text: the organization's display name when the person was added.
    name: d.nullable(d.string),
  }),
  role,
  created_at: d.timestamp,
  read_at: d.nullable(d.timestamp),
});
export type Notice = Decoded<typeof noticeReader>;

/** The server's page size, and the most a page may carry. */
const PAGE = 50;

export async function fetchNoticesPage(
  _key: true,
  cursor: string | null,
  signal: AbortSignal,
): Promise<ApiResult<Page<Notice, undefined>>> {
  const params = new URLSearchParams({ limit: String(PAGE) });
  if (cursor !== null) params.set("cursor", cursor);
  const r = await requestPage(
    `/account/notices?${params.toString()}`,
    d.object({ notices: d.array(noticeReader, PAGE) }),
    { signal },
  );
  if (!r.ok) return r;
  return {
    ok: true,
    value: { items: r.value.value.notices, next: r.value.nextCursor, meta: undefined },
  };
}

export function markNoticeRead(id: string): Promise<ApiResult<Notice>> {
  return request(`/account/notices/${encodeURIComponent(id)}/read`, noticeReader, {
    method: "POST",
    body: {},
  });
}

/** Where the organization opens: its home, when the session has it with a mission to open. */
export function organizationLink(
  notice: Notice,
  organizations: readonly SessionOrganization[],
): { name: string; to: RouteLocationRaw | null } {
  const org = organizations.find((o) => o.id === notice.organization.id);
  const name = org?.name ?? notice.organization.name?.trim() ?? "";
  return {
    name: name === "" ? "an organization" : name,
    to: org && org.missions.length > 0 ? { name: "org.home", params: { org: org.slug } } : null,
  };
}

/** The role inside the sentence, keyed by the role vocabulary ("as a member"). */
const roleInSentence: Readonly<Record<Role, string>> = {
  organization_admin: "an org admin",
  member: "a member",
};

type NoticeKind = Notice["kind"];
/** The words around the organization's name, by kind (U20: a kind it doesn't know says so). */
const kindWords: Readonly<Record<NoticeKind, (n: Notice) => { before: string; after: string }>> = {
  organization_access_granted: (n) => ({
    before: "You were added to ",
    after: ` as ${isKnown(n.role) ? roleInSentence[n.role] : n.role.unrecognized}.`,
  }),
  unrecognized: () => ({ before: "A notice this console doesn't recognize, about ", after: "." }),
};

export const noticeWords = (notice: Notice) => kindWords[notice.kind](notice);
