import { record, present, text, count } from "../../shared/contracts";
type NotificationSummary = {
  notification_id: string;
  title: string;
  body: string | null;
  read_at: string | null;
};
function summary(value: unknown): value is NotificationSummary {
  return (
    record(value) &&
    present(value.notification_id, 512) &&
    text(value.title) &&
    (value.body === null ||
      (typeof value.body === "string" &&
        value.body.length <= 16384 &&
        !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(value.body))) &&
    (value.read_at === null || (text(value.read_at) && Number.isFinite(Date.parse(value.read_at))))
  );
}
export function readBell(value: unknown) {
  if (
    !record(value) ||
    value.version !== 1 ||
    !record(value.user) ||
    !present(value.user.user_id, 512) ||
    !count(value.unread_count) ||
    !Array.isArray(value.notifications) ||
    value.notifications.length > 100 ||
    !value.notifications.every(summary) ||
    new Set(value.notifications.map((row) => row.notification_id)).size !==
      value.notifications.length
  )
    return null;
  return {
    unread_count: value.unread_count,
    notifications: value.notifications.map((row) => ({
      notification_id: row.notification_id,
      title: row.title,
      body: row.body,
      read_at: row.read_at,
    })),
  };
}
