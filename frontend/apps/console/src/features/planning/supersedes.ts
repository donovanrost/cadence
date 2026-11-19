import type { MissionId } from "@/api/index.ts";
import { actor, decoders, request, type ApiResult, type Decoded } from "@/api";
import { planStates } from "@/features/scheduling/index.ts";
import { decidedReader, type Decided } from "./decided.ts";

/** Contract: docs/apogee/api/scheduling.md, "Dry run before saving" (writes nothing). */
const { array, integer, nullable, object, optional, string, token } = decoders;

const draftsShape = {
  drafts: array(
    object({
      plan: object({ id: token, version: integer }),
      // api drift sweep 11-13: null for a draft with no passes yet (contact_plan_overview.ex:76).
      day: nullable(string),
      author: nullable(actor),
      state: decoders.known(planStates),
    }),
    500,
  ),
};
const reader = object(draftsShape);
/** A template's read also carries the days an edit leaves alone (U48); absent until api ships it. */
const templateReader = object({ ...draftsShape, decided: optional(decidedReader) });
export type SupersededDraft = Decoded<typeof reader>["drafts"][number];

export async function fetchTemplateSupersedes(
  key: Readonly<{ missionId: MissionId; templateId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<Readonly<{ drafts: readonly SupersededDraft[]; decided: Decided | null }>>> {
  const r = await request(
    `/missions/${encodeURIComponent(key.missionId)}/contact-planning/templates/${encodeURIComponent(key.templateId)}/supersedes`,
    templateReader,
    { signal },
  );
  return r.ok
    ? { ok: true, value: { drafts: r.value.drafts, decided: r.value.decided ?? null } }
    : r;
}

/** One-off requirements: the drafts a new version, close or cancel supersedes (same row shape). */
export async function fetchRequirementSupersedes(
  key: Readonly<{ missionId: MissionId; requirementId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<readonly SupersededDraft[]>> {
  const r = await request(
    `/missions/${encodeURIComponent(key.missionId)}/contact-planning/requirements/${encodeURIComponent(key.requirementId)}/supersedes`,
    reader,
    { signal },
  );
  return r.ok ? { ok: true, value: r.value.drafts } : r;
}

/** "2026-11-15" → "Sun 15 Nov" (sentence case inside prose). */
function dayText(day: string): string {
  return new Date(`${day}T00:00:00Z`)
    .toLocaleDateString("en-GB", {
      weekday: "short",
      day: "numeric",
      month: "short",
      timeZone: "UTC",
    })
    .replace(",", "");
}

/**
 * ux ContactPlanning.md: "Saving v3 supersedes 2 open drafts: Wed 11 Nov (R1, Mira K.), Thu 12 Nov
 * (R1, you). They'll need drafting again."
 */
export function supersedeSentence(
  drafts: readonly SupersededDraft[],
  nextVersion: number,
  userId: string,
  /** What supersedes them: "Saving v3" by default; "Closing it" / "Canceling it" for requirements. */
  doing = `Saving v${nextVersion}`,
): string {
  const n = drafts.length;
  const list = drafts
    .map((d) => {
      const who = d.author ? (d.author.id === userId ? "you" : d.author.name) : null;
      return `${d.day ? dayText(d.day) : "No passes yet"} (r${d.plan.version}${who ? `, ${who}` : ""})`;
    })
    .join(", ");
  return `${doing} supersedes ${n === 1 ? "1 open draft" : `${n} open drafts`}: ${list}. ${n === 1 ? "It'll" : "They'll"} need drafting again.`;
}
