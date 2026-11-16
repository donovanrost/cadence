import type { RouteLocationRaw } from "vue-router";
import type { OpState } from "@/ui";
import type { EventSeverity, MissionEvent } from "./api.ts";
import { KIND_WORDS, kindLabel, severityState, subjectLink } from "./model.ts";

/**
 * The event detail panel's content (ux decisions U71 A8; api a87bee73d), first-class fields in
 * ux's order, then Technical details. A ref without a name, and a status code without a word, go
 * to Technical details.
 */
export type EventDetail = Readonly<{
  title: string;
  state: OpState;
  severity: string;
  /** "Contacts · Contacts canceled". */
  groupType: string;
  /** "Occurred 11-15 02:51:03Z". */
  occurred: string;
  links: readonly Readonly<{ label: string; to: RouteLocationRaw }>[];
  status: string | null;
  /** `contact`: a scheduled or realized contact id, linked to History once it resolves (U78). */
  technical: readonly Readonly<{ label: string; value: string; contact?: true }>[];
}>;

const SEVERITY_WORDS: Readonly<Record<EventSeverity, string>> = {
  critical: "Critical",
  caution: "Caution",
  nominal: "Nominal",
  info: "Info",
};

/** "11-15 02:51:03Z": date and seconds (UTC). */
export function occurredText(at: string): string {
  return `Occurred ${at.slice(5, 10)} ${at.slice(11, 19)}Z`;
}

/** A status is shown in words when it is words ('canceled', 'in_flight'); a code goes to Technical. */
function statusWords(status: string | null | undefined): string | null {
  if (!status || !/^[a-z][a-z_ ]*$/i.test(status)) return null;
  const words = status.replace(/_/g, " ").toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function eventDetail(e: MissionEvent): EventDetail {
  const r = e.record ?? null;
  const links: { label: string; to: RouteLocationRaw }[] = [];
  if (e.spacecraft)
    links.push({
      label: e.spacecraft.name,
      to: { name: "ops.spacecraft", params: { scId: e.spacecraft.scid } },
    });
  const subject = e.refs.subject ?? null;
  const subjectTo = subjectLink(e);
  if (subject?.name && subjectTo) links.push({ label: subject.name, to: subjectTo });
  const status = statusWords(r?.status);
  const technical: { label: string; value: string; contact?: true }[] = [
    { label: "Event id", value: e.id },
    ...(e.raw_kind ? [{ label: "Raw kind", value: e.raw_kind }] : []),
  ];
  const add = (label: string, value: string | null | undefined) => {
    if (value) technical.push({ label, value });
  };
  if (r?.status && !status) add("Status", r.status);
  if (r?.source_record) add("Source record", `${r.source_record.kind} ${r.source_record.id}`);
  add("Source endpoint", r?.source_endpoint_ref);
  add("Path", r?.path_id);
  add("Capability instance", r?.capability_instance_id);
  add("Activation", r?.activation_id);
  add("Correlation key", r?.correlation_key);
  for (const [label, value] of [
    ["Scheduled contact", r?.scheduled_contact_id],
    ["Realized contact", r?.realized_contact_id],
  ] as const) {
    if (value) technical.push({ label, value, contact: true });
  }
  if (subject && !(subject.name && subjectTo)) add(`Subject (${subject.kind})`, subject.id);
  add("Command request", e.refs.command_request_id);
  add("Contact", e.refs.contact_id);
  add("Alarm", e.refs.alarm_id);
  add("Point", e.refs.point_id);
  return {
    title: e.text,
    state: severityState(e.severity),
    severity: SEVERITY_WORDS[e.severity],
    groupType: `${KIND_WORDS[e.kind]} · ${kindLabel(e)}`,
    occurred: occurredText(e.at),
    links,
    status,
    technical,
  };
}
