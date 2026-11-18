import type { RouteLocationRaw } from "vue-router";
import { codeOf, decoders as d, detailsOf, isError, spacecraftRef, type ApiError } from "@/api";

/**
 * ux U95: Approve refused by domain's preflight (a87fe44f6) before anything is recorded. Every line
 * starts "Not approved:", says what to do, and ends "Your approval wasn't recorded." Approve is then
 * off with the line as its reason; Reject stays. The same codes mean other things elsewhere (an
 * apply failure, a catalog approve); on the decide panel they mean nothing was recorded.
 */
export type ApproveRefusal = Readonly<{
  text: string;
  link: Readonly<{ label: string; to: RouteLocationRaw }> | null;
  /** The raw code, for Technical details when the console has no words for it (U20). */
  code: string | null;
  /** false: worth trying again soon (plans still preparing), so Approve stays on. */
  final: boolean;
}>;

const NOT_RECORDED = "Your approval wasn't recorded.";
const CATALOG = { label: "Open the catalog", to: { name: "setup.catalog" } } as const;
const revision = (id: string) =>
  ({ name: "setup.catalog.model", params: { revisionId: id } }) as const;

/** "4 and 5", "4, 5 and 6", "4, 5, 6 and 2 more" (U95: up to 3). */
function list(words: readonly string[]): string {
  const shown = words.slice(0, 3);
  const more = words.length - shown.length;
  if (more > 0) return `${shown.join(", ")} and ${more} more`;
  return shown.length > 1
    ? `${shown.slice(0, -1).join(", ")} and ${shown.at(-1)}`
    : (shown[0] ?? "");
}

const notApproved = d.object({
  catalog_revisions: d.array(
    d.object({
      id: d.nullable(d.token),
      number: d.nullable(d.integer),
      mission_model_revision_id: d.token,
    }),
    100,
  ),
});
const comparisonFailed = d.object({
  catalog_revision: d.nullable(d.object({ id: d.token, number: d.integer })),
  comparison_report_id: d.token,
  /** Asked of api (optional): the model revision whose Approval page shows the report. */
  mission_model_revision_id: d.optional(d.token),
});
/** review_stale and model_not_active (api): the craft, each name possibly unknown. */
const craftDetails = d.object({
  // free-text: a spacecraft's display name; null when api can't resolve it
  spacecraft: d.optional(d.array(spacecraftRef, 100)),
});
const craftNames = (e: ApiError): string[] =>
  (detailsOf(e, craftDetails)?.spacecraft ?? []).flatMap((s) => (s.name ? [s.name] : []));

const line = (
  text: string,
  link: ApproveRefusal["link"] = null,
  o: Partial<Pick<ApproveRefusal, "code" | "final">> = {},
): ApproveRefusal => ({
  text: `Not approved: ${text} ${NOT_RECORDED}`,
  link,
  code: o.code ?? null,
  final: o.final ?? true,
});

function notApprovedLine(e: ApiError): ApproveRefusal {
  const revs = detailsOf(e, notApproved)?.catalog_revisions ?? [];
  const numbered = revs.filter((r) => r.number !== null);
  const one = revs.length === 1 ? revs[0] : undefined;
  if (one && one.number !== null)
    return line(
      `catalog rev ${one.number} isn't approved yet, so this can't apply. An org admin approves it in Setup › Catalog first.`,
      { label: `Open rev ${one.number}`, to: revision(one.mission_model_revision_id) },
    );
  if (numbered.length > 1)
    return line(
      `catalog revs ${list(numbered.map((r) => String(r.number)))} aren't approved yet, so this can't apply. An org admin approves them in Setup › Catalog first.`,
      CATALOG,
    );
  return line(
    "a catalog revision it uses isn't approved yet, so this can't apply. An org admin approves it in Setup › Catalog first.",
    CATALOG,
  );
}

function comparisonLine(e: ApiError): ApproveRefusal {
  const c = detailsOf(e, comparisonFailed);
  const report = c?.mission_model_revision_id
    ? { label: "Open the report", to: revision(c.mission_model_revision_id) }
    : CATALOG;
  return c?.catalog_revision
    ? line(
        `catalog rev ${c.catalog_revision.number}'s comparison didn't pass, so this can't apply.`,
        report,
      )
    : line(
        "the comparison for the catalog revision it uses didn't pass, so this can't apply.",
        report,
      );
}

function staleLine(e: ApiError): ApproveRefusal {
  const names = craftNames(e);
  const whose =
    names.length === 1
      ? `${names[0]}'s configuration`
      : names.length > 1
        ? `the configuration of ${list(names)}`
        : "a spacecraft's configuration";
  return line(
    `${whose} changed after this was requested, so it isn't what was reviewed. The requester sends it again.`,
  );
}

/** U95 addition: "the catalog revision EARENDIL-004 was reviewed with isn't the active one any more". */
function modelNotActiveLine(e: ApiError): ApproveRefusal {
  const names = craftNames(e);
  const whose = names.length
    ? `${list(names)} ${names.length === 1 ? "was" : "were"}`
    : "a spacecraft was";
  return line(
    `the catalog revision ${whose} reviewed with isn't the active one any more, so this isn't what was reviewed. The requester sends it again.`,
  );
}

/** U95's line for an Approve refusal; null when it isn't one (decideFailure words the rest). */
export function approveRefusal(e: ApiError): ApproveRefusal | null {
  // Refusals from before the preflight keep their own words (decideFailure): not_pending etc.
  if (e.kind !== "conflict" || isError(e, "not_pending")) return null;
  if (isError(e, "approved_activation_content_mismatch"))
    return line(
      "what this request would apply changed after it was requested, so it isn't what you reviewed. The requester sends it again.",
    );
  if (isError(e, "mission_model_revision_not_approved")) return notApprovedLine(e);
  if (isError(e, "mission_model_revision_not_in_catalog"))
    return line(
      "the catalog doesn't list the revision this request uses, so it can't apply. The requester sends a request for a revision the catalog lists.",
    );
  if (isError(e, "mission_model_comparison_failed")) return comparisonLine(e);
  if (isError(e, "activation_policy_changed"))
    return line(
      "the mission's approval setting changed after this was requested. The requester sends it again.",
    );
  if (isError(e, "spacecraft_configuration_review_stale")) return staleLine(e);
  if (isError(e, "spacecraft_configuration_review_required"))
    return line(
      "on this mission, changes are activated from each spacecraft's configuration (Setup › Spacecraft), so this request can't apply. Reject it, and send the change from the spacecraft's configuration instead.",
    );
  if (isError(e, "spacecraft_model_not_active")) return modelNotActiveLine(e);
  if (isError(e, "change_set_activation_stale"))
    return line(
      "what's running on this mission changed after this was requested, so it isn't what was reviewed. The requester sends it again.",
    );
  if (isError(e, "mission_model_activation_manifest_required"))
    return line(
      "this request doesn't say which catalog revision it activates, so it can't apply. The requester sends it again; if it keeps happening, tell the team that runs Cadence.",
    );
  if (isError(e, "mission_model_comparison_report_required"))
    return line(
      "the catalog revision it uses hasn't been compared yet. Run the comparison in Setup › Catalog first.",
      CATALOG,
    );
  if (isError(e, "mission_model_runtime_plans_not_ready"))
    return line(
      "Cadence is still preparing the catalog revision it uses. Try again in a moment.",
      null,
      { final: false },
    );
  // Any other refusal (manifest and binding checks): the generic line, the code in Technical details.
  return line("this request can't apply as it stands.", null, { code: codeOf(e) });
}
