import { sessionPage } from "../../shared/contracts";
export function readPage(value: unknown) {
  return sessionPage(value) ? { version: 1 as const, csrf_token: value.csrf_token } : null;
}
