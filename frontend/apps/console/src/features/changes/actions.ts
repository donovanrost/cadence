import type { RouteLocationRaw } from "vue-router";
import type { MissionId } from "@/api/index.ts";
import {
  codeOf,
  isError,
  isKnown,
  decoders,
  outcomeUnknown,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  detailsOf,
} from "@/api";

/** Change-set writes and the dry run. Contract: docs/apogee/api/changes.md. */
const { array, integer, object, string, token } = decoders;

const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/config`;
import {
  previewReader,
  reasonText,
  type HoldReason,
  type Preview,
  type PreviewItem,
} from "./preview.ts";
import { changeSetStates, configKindText } from "./shapes.ts";
import { submitReader, type SubmitResult } from "./submitResult.ts";
export type { SubmitResult } from "./submitResult.ts";
export {
  diffEntry,
  diffField,
  previewReader,
  type DiffEntry,
  type Preview,
  type PreviewItem,
} from "./preview.ts";

/** 1115 → "1,115", with the schema unit when there is one. */
export function valueText(v: unknown, unit?: string | null, format?: string | null): string {
  if (v === null || v === undefined) return "not set";
  if (format === "version" && typeof v === "number") return `v${v}`;
  const text = typeof v === "number" ? v.toLocaleString("en-US") : shown(v);
  return unit && typeof v === "number" ? `${text} ${unit}` : text;
}

/**
 * ux (rollback review #1): "<Entity> · <field> is <live> now, not <base> as <leftBy> left it
 * (changed in r9 by Mira K.). Roll back r9 first, or change it by hand."
 */
export function conflictSentences(item: PreviewItem, leftBy?: string): string | null {
  if (!item.paths || item.paths.length === 0) return null;
  const who = item.entity_name ?? item.entity_id ?? configKindText(item.kind);
  return item.paths
    .map((p) => {
      const since =
        p.changed_in === "outside"
          ? "changed outside a change set"
          : `changed in r${p.changed_in}${p.changed_by?.name ? ` by ${p.changed_by.name}` : ""}`;
      const head = `${who} · ${p.label ?? p.path} is ${valueText(p.live, p.unit, p.format)} now, not ${valueText(p.base, p.unit, p.format)} as ${leftBy ?? "it was when staged"}${leftBy ? " left it" : ""} (${since}).`;
      return p.changed_in === "outside"
        ? `${head} Change it by hand.`
        : `${head} Roll back r${p.changed_in} first, or change it by hand.`;
    })
    .join(" ");
}

const shown = (v: unknown) => (typeof v === "string" ? v : JSON.stringify(v));

/** One line per check item: server sentence first, then both values for a framing mismatch. */
/** `contacts_in_window` → "Contacts in window" (fallback when the server sends no sentence). */
export function humanize(key: string): string {
  const words = key
    .replace(/[_.:-]+/g, " ")
    .trim()
    .toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** #65 catalog generations: holds that acknowledging can't clear, and what clears them. */
const blockingNext: Readonly<Partial<Record<HoldReason, string>>> = {
  catalog_command_in_flight: "Apply when those commands finish.",
  catalog_configuration_pending: "Activate or discard the pending configuration first.",
};

/** A blocking item's "can't apply yet" line: #65 catalog holds by reason, L17/L22 by `blocking`. */
function blockingLine(item: PreviewItem): string | null {
  const said = item.sentence ?? humanize(item.reason ? reasonText(item.reason) : "");
  const next = item.reason && isKnown(item.reason) ? blockingNext[item.reason] : undefined;
  if (next) return `Can't apply yet: ${said} ${next}`;
  return item.blocking === true ? `Can't apply yet: ${said}` : null;
}

/** The first blocking item's "can't apply yet" line, or null when nothing blocks. */
export function blockingReason(preview: Preview): string | null {
  for (const check of preview.checks)
    for (const item of check.items) {
      const line = blockingLine(item);
      if (line) return line;
    }
  return null;
}

export function itemLine(item: PreviewItem, leftBy?: string): string {
  const blocked = blockingLine(item);
  if (blocked) return blocked;
  const conflict = conflictSentences(item, leftBy);
  if (conflict) return conflict;
  // A plain sentence with its raw detail split off reads on its own (ux rollback review #7).
  if (item.sentence && item.detail) return item.sentence;
  if (item.profile_value && item.transport_value) {
    const both = `profile ${item.profile_value.path} = ${shown(item.profile_value.value)} vs ${item.transport_value.transport.name} ${item.transport_value.path} = ${shown(item.transport_value.value)}`;
    const count = item.spacecraft_count == null ? "" : ` · ${item.spacecraft_count} spacecraft`;
    return `${item.sentence ? `${item.sentence} ` : ""}(${both}${count})`;
  }
  // framing_unverified (DECISIONS #40): only the profile side is known.
  if (item.profile_value && item.reason === "framing_unverified") {
    const head = item.sentence ?? "Can't verify against any transport.";
    const count = item.spacecraft_count == null ? "" : ` · ${item.spacecraft_count} spacecraft`;
    return `${head} (profile ${item.profile_value.path} = ${shown(item.profile_value.value)}${count})`;
  }
  if (item.sentence) return item.sentence;
  if (item.errors && item.errors.length > 0)
    return item.errors.map((e) => `${e.path}: ${e.message}`).join("; ");
  return item.reason ? humanize(reasonText(item.reason)) : configKindText(item.kind);
}

const versionResult = object({
  change_set_id: token,
  version: integer,
  state: decoders.known(changeSetStates),
});

export function previewChangeSet(
  key: Readonly<{ missionId: MissionId; changeSetId: string; version: number }>,
  signal: AbortSignal,
): Promise<ApiResult<Preview>> {
  return request(
    `${base(key.missionId)}/change-sets/${encodeURIComponent(key.changeSetId)}/preview`,
    previewReader,
    { method: "POST", body: {}, signal },
  );
}

export function withdrawChange(missionId: MissionId, changeId: string) {
  return request(
    `${base(missionId)}/changes/${encodeURIComponent(changeId)}/withdraw`,
    versionResult,
    {
      method: "POST",
      body: {},
    },
  );
}

export function discardChangeSet(
  missionId: MissionId,
  changeSetId: string,
  expectedVersion: number,
) {
  return request(
    `${base(missionId)}/change-sets/${encodeURIComponent(changeSetId)}/discard`,
    object({
      change_set_id: token,
      version: integer,
      state: decoders.known(changeSetStates),
      remaining: decoders.optional(integer),
    }),
    { method: "POST", body: { expected_version: expectedVersion } },
  );
}

export function submitChangeSet(
  missionId: MissionId,
  changeSetId: string,
  body: Readonly<{ reason: string; expected_version: number; acknowledged_holds: boolean }>,
): Promise<ApiResult<SubmitResult>> {
  return request(
    `${base(missionId)}/change-sets/${encodeURIComponent(changeSetId)}/submit`,
    submitReader,
    { method: "POST", body },
  );
}

export function reviewChangeSet(
  missionId: MissionId,
  changeSetId: string,
  body: Readonly<{ decision: "approve" | "send_back"; comment: string; expected_version: number }>,
): Promise<ApiResult<SubmitResult>> {
  return request(
    `${base(missionId)}/change-sets/${encodeURIComponent(changeSetId)}/review`,
    submitReader,
    { method: "POST", body },
  );
}

/** The server's error tag (docs/apogee/api/changes.md § Errors), when the error carries one. */
export function errorCode(error: ApiError): string | null {
  return codeOf(error);
}

/** People-facing sentence for a change-set rejection, keyed by the facade tag. */
export function rejectionSentence(error: ApiError): string {
  switch (errorCode(error)) {
    case "change_set_changed":
      return "Someone changed the staged set while you were looking. It has been reloaded; check it and try again.";
    case "frozen_in_review":
      return "The change set is in review, so staging is paused.";
    case "reviewer_is_author":
      return "You staged part of this set, so you can't approve it. Another person must review it.";
    case "activation_policy_changed":
      return "The approval policy changed since this was submitted. The set has reopened.";
    case "checks_failed":
      return "Checks failed: nothing changed. Fix the NO-GO items and try again.";
    case "holds_not_acknowledged":
      return "Read and acknowledge the holds before applying.";
    case "holds_blocking":
      return "A blocking hold remains, so nothing was applied. It can't be acknowledged; apply once it clears (see the checks).";
    case "catalog_command_in_flight":
      return "Commands started on the affected spacecraft, so nothing was applied. Try again when they finish.";
    case "reason_required":
      return "Say why (10 characters or more).";
    case "comment_required":
      return "Add a comment for the author.";
    case "nothing_staged":
      return "Nothing is staged.";
    case null:
    default:
      return "message" in error ? error.message : "Request failed.";
  }
}

export type StageOp = Readonly<{
  kind:
    | "ground_station"
    | "transport"
    | "spacecraft"
    | "spacecraft_profile"
    | "spacecraft_override";
  action: "create" | "update" | "delete";
  entity_id?: string;
  document?: Readonly<Record<string, unknown>>;
  changes?: readonly Readonly<{ path: string; value: unknown }>[];
  options?: Readonly<Record<string, unknown>>;
}>;

export const stageResultReader = object({
  change_set_id: token,
  change_id: token,
  version: integer,
  staged_count: integer,
  base_revision: integer,
  entity_ids: array(token, 5000),
});
export type StageResult = Decoded<typeof stageResultReader>;

/** Stage one change (any number of ops) into the mission's open change set. */
export function stageChange(
  missionId: MissionId,
  body: Readonly<{
    summary: string;
    source: Readonly<Record<string, unknown>>;
    ops: readonly StageOp[];
  }>,
): Promise<ApiResult<StageResult>> {
  return request(`${base(missionId)}/stage`, stageResultReader, { method: "POST", body });
}

/** `invalid_op` details: which op (by index) failed, and why. */
export function invalidOpDetails(error: ApiError): Readonly<{
  index: number;
  errors: readonly Readonly<{ path: string; message: string }>[];
}> | null {
  if (errorCode(error) !== "invalid_op" || !("details" in error)) return null;
  const parsed = decoders.decode(
    object({ index: integer, errors: array(object({ path: string, message: string }), 200) }),
    error.details,
  );
  return parsed.ok ? parsed.value : null;
}

/**
 * A rejected stage's field errors, split for a form (U79: the error sits on its field): those whose
 * path is one of the form's fields, and the rest (shown in the form's callout).
 */
export function fieldErrors(
  error: ApiError,
  paths: ReadonlySet<string>,
  /** The op the form staged (a KindEditor stages one, at 0); another op's errors stay in the rest. */
  index = 0,
): Readonly<{
  onFields: Readonly<Record<string, string>>;
  rest: readonly Readonly<{ path: string; message: string }>[];
}> | null {
  const detail = invalidOpDetails(error);
  if (!detail || detail.errors.length === 0) return null;
  const onFields: Record<string, string> = {};
  const rest: { path: string; message: string }[] = [];
  for (const e of detail.errors) {
    // compared-as-text: the kinds send plain field paths, the schema's own (fe-setup); first message wins.
    if (detail.index === index && paths.has(e.path) && onFields[e.path] === undefined)
      onFields[e.path] = e.message;
    else rest.push(e);
  }
  return { onFields, rest };
}

export type FailureOutcome = Readonly<{
  /** false: the server rejected it, nothing changed. null: we can't tell (reply lost or unreadable). */
  changed: false | null;
  sentence: string;
  /** U65: where to go about it ('Open the report' on a failed model comparison). */
  link?: Readonly<{ label: string; to: RouteLocationRaw }>;
}>;

const comparisonFailed = decoders.object({ mission_model_revision_id: decoders.token });

/**
 * Every stage/apply failure says whether anything changed (ux review 2026-11-09). A rejection
 * means nothing changed; an unreadable reply or a lost connection means we can't tell.
 */
export function failureOutcome(
  error: ApiError,
  verb: "staged" | "applied" | "changed",
): FailureOutcome {
  if (error.kind === "malformed")
    return {
      changed: null,
      sentence: `The server's reply wasn't understood, so it isn't clear whether anything was ${verb}. Check Staged changes before trying again.`,
    };
  if (error.kind === "unavailable" && error.status === 0)
    return {
      changed: null,
      sentence: `The connection dropped, so it isn't clear whether anything was ${verb}. Check Staged changes before trying again.`,
    };
  // qa #19: a 500 can arrive after the write committed; it's unclear, never "nothing changed".
  if (error.kind === "unavailable" && outcomeUnknown(error))
    return {
      changed: null,
      sentence: `The server failed while answering, so it isn't clear whether anything was ${verb}. Check Staged changes and Revisions now, before trying again.`,
    };
  // Field-level rejections (e.g. DECISIONS #36 catalog refusal) name the field and the route.
  const fields = invalidOpDetails(error);
  if (fields && fields.errors.length > 0)
    return {
      changed: false,
      sentence: `Nothing was ${verb}. ${fields.errors.map((e) => (e.path ? `${e.path}: ${e.message}` : e.message)).join(" · ")}`,
    };
  // invalid_params: details keyed by field (`{comment: "is required"}` or a list of messages).
  if (errorCode(error) === "invalid_params" && "details" in error) {
    const d = error.details;
    if (d !== null && typeof d === "object" && !Array.isArray(d)) {
      const parts = Object.entries(d).flatMap(([field, v]) =>
        typeof v === "string"
          ? [`${field}: ${v}`]
          : Array.isArray(v)
            ? v.filter((m): m is string => typeof m === "string").map((m) => `${field}: ${m}`)
            : [],
      );
      if (parts.length > 0)
        return { changed: false, sentence: `Nothing was ${verb}. ${parts.join(" · ")}` };
    }
  }
  // U63/U65: the server's sentence already says "Not applied: …" and names what (ux).
  if (
    (isError(error, "telemetry_app_not_installed") ||
      isError(error, "telemetry_packet_inputs_required") ||
      isError(error, "mission_model_revision_not_approved") ||
      isError(error, "mission_model_comparison_failed")) &&
    "message" in error &&
    error.message
  ) {
    const report = isError(error, "mission_model_comparison_failed")
      ? detailsOf(error, comparisonFailed)
      : null;
    return {
      changed: false,
      sentence: error.message,
      ...(report
        ? {
            link: {
              label: "Open the report",
              to: {
                name: "setup.catalog.model",
                params: { revisionId: report.mission_model_revision_id },
              },
            },
          }
        : {}),
    };
  }
  return { changed: false, sentence: `Nothing was ${verb}. ${rejectionSentence(error)}` };
}

/** Dry run of unstaged ops (nothing written): per-op validation and conflicts, by op index. */
export function previewOps(
  key: Readonly<{ missionId: MissionId; ops: readonly StageOp[] }>,
  signal: AbortSignal,
): Promise<ApiResult<Preview>> {
  return request(`${base(key.missionId)}/preview`, previewReader, {
    method: "POST",
    body: { ops: key.ops },
    signal,
  });
}

/** "Santiago (Demo) S-band downlink" → "Santiago": the station part names a transport in a list. */
function shortTransport(name: string): string {
  const cut = name.search(/ \(| S-band| X-band| Ka-band/);
  return cut > 0 ? name.slice(0, cut) : name;
}

/**
 * Check rows' lines, with framing mismatches that differ only by transport folded into one line:
 * "… would decode 900-byte frames, but 2 transports send 1,115-byte frames (Santiago, Svalbard)."
 */
export function groupedLines(items: readonly PreviewItem[], leftBy?: string): readonly string[] {
  const groups = new Map<string, PreviewItem[]>();
  const order: string[] = [];
  items.forEach((item, i) => {
    const key =
      item.reason === "framing_mismatch" && item.profile_value && item.transport_value
        ? JSON.stringify([
            item.entity_id,
            item.profile_value.path,
            item.profile_value.value,
            item.transport_value.path,
            item.transport_value.value,
          ])
        : `#${i}`;
    if (!groups.has(key)) order.push(key);
    groups.set(key, [...(groups.get(key) ?? []), item]);
  });
  return order.map((key) => {
    const group = groups.get(key) ?? [];
    const first = group[0];
    if (!first) return "";
    if (group.length === 1) return itemLine(first, leftBy);
    const names = group.flatMap((g) =>
      g.transport_value ? [g.transport_value.transport.name] : [],
    );
    const one = first.transport_value?.transport.name ?? "";
    const sentence = first.sentence ?? "";
    const folded = sentence.replace(`but ${one} sends`, `but ${group.length} transports send`);
    return folded !== sentence
      ? `${folded.replace(/\.$/, "")} (${names.map(shortTransport).join(", ")}).`
      : group.map((g) => itemLine(g, leftBy)).join(" · ");
  });
}
