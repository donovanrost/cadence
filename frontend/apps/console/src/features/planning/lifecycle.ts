import type { MissionId } from "@/api/index.ts";
import { actorName, decoders as d, detailsOf, isError, request, type ApiError } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { formatShort } from "@/ui";
import { templateStates, type TemplateDetail } from "./api.ts";

/**
 * L2 template pause / resume / close (plans/planning-verbs.md, api agreed 11-13). A lifecycle move
 * keeps the version; expected_version still guards it. Pause and close stop new requirements only.
 */
export type TemplateVerb = "pause" | "activate" | "close";

export function transitionTemplate(
  missionId: MissionId,
  templateId: string,
  verb: TemplateVerb,
  body: Readonly<{ expected_version: number; reason: string }>,
) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/contact-planning/templates/${encodeURIComponent(templateId)}/${verb}`,
    d.object({ id: d.token, state: d.known(templateStates), version: d.integer }),
    { method: "POST", body },
  );
}

/** Which moves a template in this state offers: active ↔ paused, active | paused → closed. */
export function verbsFor(state: TemplateDetail["state"]): readonly TemplateVerb[] {
  switch (state) {
    case "active":
      return ["pause", "close"];
    case "paused":
      return ["activate", "close"];
    case "closed":
    case "unrecognized":
      return [];
  }
}

export const VERBS: Readonly<
  Record<TemplateVerb, { button: string; title: string; sentence: string; confirm: string }>
> = {
  pause: {
    button: "Pause…",
    title: "Pause template",
    sentence:
      "Cadence stops making new requirements from it until you resume. Ones it already made stay.",
    confirm: "Pause it",
  },
  activate: {
    button: "Resume…",
    title: "Resume template",
    sentence: "Cadence starts making requirements from it again, from the next planning day.",
    confirm: "Resume it",
  },
  close: {
    button: "Close…",
    title: "Close template",
    sentence: "Ends the template for good; it can't be reopened. Ones it already made stay.",
    confirm: "Close it",
  },
};

const MOVED: Readonly<Record<TemplateDetail["state"], string>> = {
  active: "Resumed",
  paused: "Paused",
  closed: "Closed",
  unrecognized: "Changed",
};
/** "Paused by Mira K. on 11-12 14:03Z: provider outage", or null while active since create. */
export function stateChangedLine(t: TemplateDetail): string | null {
  const c = t.state_changed;
  if (!c) return null;
  const why = c.reason ? `: ${c.reason}` : "";
  return `${MOVED[c.state]} by ${actorName(c.actor, "someone")} on ${formatShort(new Date(c.at))}${why}`;
}

/** One sentence for a refused move (U20). */
export function transitionFailure(error: ApiError): string {
  if (isError(error, "template_transition_not_allowed")) {
    const state = detailsOf(error, d.object({ state: d.known(templateStates) }))?.state;
    return state === "closed"
      ? "It's closed now, so it can't change. Reload to see it."
      : "Its state changed since you loaded it. Reload to see it.";
  }
  if (isError(error, "version_conflict"))
    return "Someone changed this template since you loaded it. Reload to see the latest.";
  return failureOutcome(error, "changed").sentence;
}
