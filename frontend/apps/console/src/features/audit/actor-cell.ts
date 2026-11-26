import { tableActor, type TableActor } from "@/features/changes/index.ts";
import type { AuditEvent } from "./api.ts";

/**
 * The Audit table's actor cell (U25 via #308's tableActor): a person by name or a muted "Not
 * known", a service with its tag, never an id. #470/#523 (ux): on an entry whose kind is
 * `platform` as the server sends it (never by action names), a nameless person is the team that
 * runs Cadence. A named actor, a service or the system actor there keep their forms.
 */
export function auditActorCell(e: AuditEvent): TableActor | null {
  const a = e.actor;
  if (!a) return null;
  // compared-as-text: audit entry kinds are an open set across sources; ux keys this on `platform`
  if (e.kind === "platform" && a.kind === "user" && a.name === null)
    return { text: "The team that runs Cadence", muted: true, service: false };
  return tableActor(a);
}
