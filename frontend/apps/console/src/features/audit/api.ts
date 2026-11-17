import type { RouteLocationRaw } from "vue-router";
import {
  actor,
  decoders,
  isKeyOf,
  orNull,
  perItem,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
  type SessionOrganization,
  type Unshown,
} from "@/api";

/** Contract: docs/apogee/api/setup.md, `GET /organizations/:id/audit` (AU1). */
const { array, nullable, object, string, timestamp, token } = decoders;

export const auditKinds = ["config", "commanding", "access", "alarms", "contacts", "data"] as const;
export type AuditKind = (typeof auditKinds)[number];

const idText = (v: unknown, path = ""): string | null =>
  typeof v === "number" ? String(v) : nullable(token)(v === undefined ? null : v, path);

const event = object({
  id: token,
  at: timestamp,
  // Settings history carries only the actor's name (id null); some records have no actor.
  // The shared entity (typing §12 A5); settings history sends only a name, some records none.
  actor: orNull(actor),
  // A source the console doesn't know yet (api is adding more) decodes; kindText labels it.
  // free-text: an open vocabulary (the server adds sources); kindText words it and new kinds get a chip.
  kind: token,
  // free-text: the server's sentence for what happened.
  action: string,
  // Revision targets carry their integer number as the id; settings carry the section key.
  target: nullable(
    object({
      // free-text: the target's kind is technical context; the row shows `label`.
      kind: token,
      id: idText,
      label: string,
    }),
  ),
  mission: nullable(object({ id: token, name: string })),
  // free-text: the reason or note a person gave.
  reason: nullable(string),
});
const pageShape = object({
  /** U86 follow-up: read event by event; one this console can't read is left out and counted. */
  events: perItem(event, 1000, { label: "Org Audit", kindOf: (raw) => [raw["kind"]] }),
  sources: object({
    included: array(token, 20),
    missing: array(token, 20),
  }),
  next_cursor: nullable(string),
});
export type AuditPage = Readonly<
  Omit<Decoded<typeof pageShape>, "events"> & {
    events: readonly AuditEvent[];
    /** U86: the events left out of this page, for the line above the table and the export. */
    unshown: readonly Unshown[];
  }
>;
export const auditReader: Reader<AuditPage> = (value, path = "") => {
  const p = pageShape(value, path);
  return { ...p, events: p.events.items, unshown: p.events.unshown };
};
export type AuditEvent = Decoded<typeof event>;

export type AuditQuery = Readonly<{
  organizationId: string;
  days: number;
  /** Known kinds and any source the server adds later (filter chips come from both). */
  kinds: readonly string[];
  missionId: string | null;
  /** One person's events (AU1 `actor_id`; People › person Activity). */
  actorId?: string;
  /** Window end, fixed per query so later pages read the same window. */
  to: string;
  cursor?: string;
}>;

export function fetchAudit(q: AuditQuery, signal: AbortSignal): Promise<ApiResult<AuditPage>> {
  const to = new Date(q.to);
  const from = new Date(to.getTime() - q.days * 86_400_000);
  const params = new URLSearchParams({ from: from.toISOString(), to: to.toISOString() });
  if (q.kinds.length > 0) params.set("kinds", q.kinds.join(","));
  if (q.missionId) params.set("mission_id", q.missionId);
  if (q.actorId) params.set("actor_id", q.actorId);
  if (q.cursor) params.set("cursor", q.cursor);
  return request(
    `/organizations/${encodeURIComponent(q.organizationId)}/audit?${params.toString()}`,
    auditReader,
    { signal },
  );
}

export const kindLabel: Readonly<Record<AuditKind, string>> = {
  config: "Config",
  commanding: "Commanding",
  access: "Access",
  alarms: "Alarms",
  contacts: "Contacts",
  data: "Data",
};

/** A kind or source in words: the known label, else the key humanized ("provider_accounts" → "Provider accounts"). */
export function kindText(kind: string): string {
  const known = auditKinds.find((k) => k === kind);
  if (known) return kindLabel[known];
  const words = kind.replaceAll("_", " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** A source as a phrase for the sources callout: "config events", "provider account changes". */
const sourcePhrases = {
  provider_accounts: "provider account changes",
} as const;
export function sourcePhrase(kind: string): string {
  return isKeyOf(sourcePhrases, kind)
    ? sourcePhrases[kind]
    : `${kindText(kind).toLowerCase()} events`;
}

export type AuditRow = AuditEvent & Readonly<{ repeat: number }>;

/** Identical consecutive actions collapse into one row with a count (Timeline rule). */
export function groupRepeats(events: readonly AuditEvent[]): readonly AuditRow[] {
  const rows: AuditRow[] = [];
  const same = (a: AuditEvent, b: AuditEvent) =>
    a.action === b.action &&
    a.actor?.name === b.actor?.name &&
    a.target?.label === b.target?.label &&
    a.mission?.id === b.mission?.id &&
    a.reason === b.reason;
  for (const e of events) {
    const last = rows.at(-1);
    if (last && same(last, e)) rows[rows.length - 1] = { ...last, repeat: last.repeat + 1 };
    else rows.push({ ...e, repeat: 1 });
  }
  return rows;
}

/** The target, unless the action sentence already names it ("Requested NOOP · NOOP"). */
export function targetText(e: AuditEvent): string | null {
  return e.target && !e.action.includes(e.target.label) ? e.target.label : null;
}

/**
 * Where a target opens, when it has a console page. api 11-15: a `command_group` target opens its
 * command page (ops.commands.request, whose :requestId is the group id) in the event's mission,
 * found among the organization's missions for its slug. Every other kind (`command_request`, kinds
 * the console doesn't know yet) stays plain text.
 */
export function targetRoute(
  e: Pick<AuditEvent, "target" | "mission">,
  organization: Pick<SessionOrganization, "slug" | "missions"> | null,
): RouteLocationRaw | null {
  const target = e.target;
  // compared-as-text: target kinds are an open set across audit sources; only a command group links
  if (!target || target.kind !== "command_group" || !target.id || !e.mission || !organization)
    return null;
  const missionId = e.mission.id;
  const mission = organization.missions.find((m) => m.id === missionId);
  return mission
    ? {
        name: "ops.commands.request",
        params: { org: organization.slug, mission: mission.slug, requestId: target.id },
      }
    : null;
}

/** "config, commanding and access" */
export function listWords(words: readonly string[]): string {
  return words.length < 2
    ? (words[0] ?? "")
    : `${words.slice(0, -1).join(", ")} and ${words.at(-1) ?? ""}`;
}
