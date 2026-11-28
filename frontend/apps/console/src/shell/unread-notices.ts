import { readonly, ref } from "vue";
import { fetchSession, type Session } from "@/api/session.ts";

/**
 * #709: the account menu's unread notices. Seeded from the session read; Mark read refreshes it
 * from the session read again, so it is the server's count (the same rows as the Notices list),
 * never one the console keeps itself. There's no live push (no user socket topic).
 */
const unread = ref(0);

export function seedUnreadNotices(session: Readonly<Session>) {
  unread.value = session.unread_notices_count;
}

export const unreadNotices = readonly(unread);

/** Re-reads the count. A failed read keeps the last one rather than guess. */
export async function refreshUnreadNotices(): Promise<void> {
  const r = await fetchSession();
  if (r.ok) unread.value = r.value.unread_notices_count;
}
