import { formatClock, formatCountdown, type OpState } from "@/ui";
import type { Episode, EpisodeDetail, EpisodeEvent } from "./episodes.ts";

/** Words for alarm episodes (ux U16): source, status, escalation, and event lines. */

const field = (payload: object, key: string): unknown => Reflect.get(payload, key);
const text = (value: unknown) => (typeof value === "string" ? value : null);

/** `Live` for catalog monitoring; ground limits always say when they were evaluated (never live). */
export function sourceTag(episode: Episode, now: Date): string {
  if (episode.source === "catalog_monitoring") return "Live";
  const at = episode.last_evaluated_at;
  return at
    ? `Ground limits · evaluated ${formatClock(new Date(at))}Z · ${formatCountdown(new Date(at), now)}`
    : "Ground limits · not evaluated yet";
}

/** The readout label for the value: ground limits show the value at evaluation (U16). */
export const valueLabel = (episode: Episode | null) =>
  episode?.source === "ground_limit" ? "At evaluation" : "Now";

export function statusLine(episode: Episode): { state: OpState; text: string } {
  const who = episode.assignee?.name ? ` · assigned to ${episode.assignee.name}` : "";
  switch (episode.status) {
    case "new":
      return { state: episode.severity === "critical" ? "crit" : "caution", text: `New${who}` };
    case "acknowledged":
      return {
        state: "neutral",
        text: `Acknowledged${episode.acknowledged_by?.name ? ` by ${episode.acknowledged_by.name}` : ""}${who}`,
      };
    case "cleared":
      return {
        state: "nominal",
        text: episode.cleared_unacknowledged ? "Cleared before anyone acknowledged" : "Cleared",
      };
  }
}

/** "Ack cleared · escalated to critical" when the latest escalation dropped an acknowledgement. */
export function escalationNotice(detail: EpisodeDetail): string | null {
  const last = [...detail.events].reverse().find((e) => e.kind === "escalated");
  if (!last || detail.status !== "new" || field(last.payload, "acknowledgement_cleared") !== true)
    return null;
  return `Ack cleared · escalated to ${text(field(last.payload, "to")) ?? detail.severity}`;
}

const by = (event: EpisodeEvent) => (event.actor?.name ? ` by ${event.actor.name}` : "");

export function eventText(event: EpisodeEvent): string {
  const p = event.payload;
  const note = text(field(p, "note"));
  const suffix = note ? `: “${note}”` : "";
  switch (event.kind) {
    case "raised":
      return "Alarm raised";
    case "escalated":
      return `Escalated to ${text(field(p, "to")) ?? "a higher severity"}${field(p, "acknowledgement_cleared") === true ? " · acknowledgement cleared" : ""}`;
    case "deescalated":
      return `Eased to ${text(field(p, "to")) ?? "a lower severity"}`;
    case "acknowledged":
      return `Acknowledged${by(event)}${suffix}`;
    case "assigned":
      return `Assigned${by(event)}${suffix}`;
    case "unassigned":
      return `Unassigned${by(event)}${suffix}`;
    case "note":
      return `Note${by(event)}${suffix}`;
    case "handed_off":
      return `Handed off${by(event)}${suffix}`;
    case "cleared":
      return field(p, "unacknowledged") === true
        ? "Cleared before anyone acknowledged"
        : "Cleared, back in limits";
  }
}

export function eventState(event: EpisodeEvent): OpState {
  switch (event.kind) {
    case "raised":
    case "escalated":
      return "crit";
    case "deescalated":
      return "caution";
    case "cleared":
      return "nominal";
    case "acknowledged":
    case "assigned":
    case "unassigned":
    case "note":
    case "handed_off":
      return "neutral";
  }
}
