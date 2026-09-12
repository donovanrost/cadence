import { sessionPage, count } from "../../shared/contracts";
export function readPage(value: unknown) {
  return sessionPage(value) && count(value.pending_invitations_count)
    ? {
        version: 1 as const,
        csrf_token: value.csrf_token,
        pending_invitations_count: value.pending_invitations_count,
      }
    : null;
}
