export type Notification = {
  id: string;
  kind: string;
  title: string;
  body: string | null;
  created_at: string;
  read_at: string | null;
  invitation_status: "none" | "pending" | "accepted" | "revoked" | "expired" | "unavailable";
};
export type Inbox = {
  version: 1;
  user_id: string;
  observed_at: string;
  limit: 50;
  query: { unread: "" | "true"; before_at: string; before_id: string };
  notifications: Notification[];
  next_cursor: { at: string; id: string } | null;
};
export type Action = "accept_invitation" | "mark_notification_read";
export type Act = (action: Action, input: { notification_id: string }) => Promise<unknown>;
export const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const id = (v: unknown): v is string =>
  typeof v === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,511}$/.test(v);
const time = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(v) &&
  Number.isFinite(Date.parse(v));
export function readInbox(value: unknown, userId: unknown): Inbox {
  assertInbox(value, userId);
  return value;
}
function assertInbox(value: unknown, userId: unknown): asserts value is Inbox {
  if (
    !id(userId) ||
    !record(value) ||
    value.version !== 1 ||
    value.user_id !== userId ||
    !time(value.observed_at) ||
    value.limit !== 50 ||
    !record(value.query) ||
    !["", "true"].includes(value.query.unread as string) ||
    typeof value.query.before_at !== "string" ||
    typeof value.query.before_id !== "string" ||
    !Array.isArray(value.notifications) ||
    value.notifications.length > 50
  )
    throw Error("Invalid notifications");
  const q = value.query;
  if ((q.before_at !== "" || q.before_id !== "") && (!time(q.before_at) || !id(q.before_id)))
    throw Error("Invalid inbox cursor");
  if (
    value.next_cursor !== null &&
    (!record(value.next_cursor) || !time(value.next_cursor.at) || !id(value.next_cursor.id))
  )
    throw Error("Invalid inbox continuation");
  const seen = new Set<string>();
  for (const row of value.notifications) {
    if (
      !record(row) ||
      !id(row.id) ||
      seen.has(row.id) ||
      typeof row.kind !== "string" ||
      typeof row.title !== "string" ||
      (row.body !== null && typeof row.body !== "string") ||
      !time(row.created_at) ||
      (row.read_at !== null && !time(row.read_at)) ||
      typeof row.invitation_status !== "string" ||
      !["none", "pending", "accepted", "revoked", "expired", "unavailable"].includes(
        row.invitation_status,
      ) ||
      (row.kind === "organization_invitation") !== (row.invitation_status !== "none") ||
      (q.unread === "true" && row.read_at !== null)
    )
      throw Error("Invalid notification");
    seen.add(row.id);
  }
}
export function inboxHref(query: Partial<Inbox["query"]> = {}): string {
  const params = new URLSearchParams();
  if (query.unread === "true") params.set("unread", "true");
  if (query.before_at || query.before_id) {
    if (!time(query.before_at) || !id(query.before_id)) throw Error("Invalid inbox cursor");
    params.set("before_at", query.before_at);
    params.set("before_id", query.before_id);
  }
  return "/notifications" + (params.size ? `?${params}` : "");
}
export function readActionResult(value: unknown): "read" | "accepted" | "unavailable" {
  if (!record(value)) throw Error("Invalid notification response");
  if (value.status === "unavailable") return "unavailable";
  if (
    value.status === "ok" &&
    record(value.data) &&
    ["read", "accepted"].includes(value.data.status as string)
  )
    return value.data.status as "read" | "accepted";
  throw Error("Invalid notification response");
}
