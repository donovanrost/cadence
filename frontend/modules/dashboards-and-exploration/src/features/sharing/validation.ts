import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { readWorkspaceSnapshot } from "../../workspace";
import type { SharedView, SharedViewKind } from "./contracts";

function fail(): never {
  throw Error("Invalid shared dashboard view");
}
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
function exact(v: unknown, keys: string[]): Record<string, unknown> {
  if (!record(v) || Object.keys(v).length !== keys.length || keys.some((k) => !Object.hasOwn(v, k)))
    return fail();
  return v;
}
function text(v: unknown, max: number, empty = false): string {
  if (typeof v !== "string" || new TextEncoder().encode(v).length > max || (!empty && !v.trim()))
    return fail();
  return v;
}
const id = (v: unknown) => {
  const s = text(v, 256);
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  if (/[\u0000-\u001f]/.test(s)) fail();
  return s;
};
const integer = (v: unknown, min: number, max: number) => {
  if (!Number.isSafeInteger(v) || (v as number) < min || (v as number) > max) fail();
};
const timestamp = (v: unknown) => {
  const s = text(v, 64);
  if (!/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(s) || !Number.isFinite(Date.parse(s)))
    fail();
};
const contextKeys = [
  "spacecraft_id",
  "scope_kind",
  "scope_id",
  "time_mode",
  "time_axis",
  "from",
  "to",
  "replay_run_id",
  "realm",
  "data_view",
  "data_source_id",
  "source_binding_id",
  "limit_mode",
  "selected_target",
  "selected_id",
];
const contextEnums: Record<string, string[]> = {
  time_mode: ["live", "range", "archive", "replay_run"],
  time_axis: ["generation_time", "receipt_time"],
  realm: ["flight", "rehearsal", "replay", "simulation"],
  data_view: ["canonical", "as_recorded", "all_revisions", "recomputed"],
  limit_mode: ["observed", "current", "recomputed", "compare"],
  scope_kind: [
    "mission",
    "spacecraft",
    "contact",
    "ground_station",
    "source_endpoint",
    "transport",
    "link",
  ],
};
export function readSharedView(
  value: unknown,
  context: OpsPageContext,
  kind: SharedViewKind,
): SharedView {
  const m = exact(value, [
    "version",
    "organization_id",
    "mission_id",
    "id",
    "kind",
    "dashboard_id",
    "data_visibility",
    "data_semantics",
    "created_at",
    "expires_at",
    "loaded_at",
    "runtime_context",
    "definition",
    "canvas",
  ]);
  if (
    m.version !== 1 ||
    m.kind !== kind ||
    id(m.id) !== context.resourceId ||
    id(m.organization_id) !== context.organizationId ||
    id(m.mission_id) !== context.missionId
  )
    fail();
  id(m.dashboard_id);
  if (!["definition_only", "authorized_runtime_data"].includes(m.data_visibility as string)) fail();
  if (
    kind === "share"
      ? m.data_semantics !== "published_definition_current_data"
      : !["definition_at_version_current_data", "frozen_time_window"].includes(
          m.data_semantics as string,
        )
  )
    fail();
  timestamp(m.created_at);
  timestamp(m.loaded_at);
  if (m.expires_at !== null) {
    if (kind !== "share") fail();
    timestamp(m.expires_at);
  }
  if (!record(m.runtime_context)) return fail();
  for (const [k, v] of Object.entries(m.runtime_context)) {
    if (!contextKeys.includes(k)) fail();
    text(v, 256);
    if (Object.hasOwn(contextEnums, k) && !contextEnums[k]?.includes(v as string)) fail();
    if (k === "from" || k === "to") timestamp(v);
  }
  if (m.data_semantics === "frozen_time_window") {
    timestamp(m.runtime_context.from);
    timestamp(m.runtime_context.to);
  }
  let authoredIds: string[] = [],
    sectionIds: string[] = [];
  if (m.definition === null) {
    if (kind !== "share" || m.canvas !== null) fail();
  } else {
    const d = exact(m.definition, [
      "name",
      "description",
      "version",
      "placements",
      "sections",
      "json",
    ]);
    text(d.name, 4096);
    text(d.description, 16384, true);
    integer(d.version, 1, Number.MAX_SAFE_INTEGER - 1);
    integer(d.placements, 0, 1024);
    integer(d.sections, 0, 64);
    const doc: unknown = JSON.parse(text(d.json, 524288));
    if (
      !record(doc) ||
      doc.organization_id !== m.organization_id ||
      doc.mission_id !== m.mission_id ||
      doc.dashboard_id !== m.dashboard_id ||
      doc.name !== d.name ||
      !record(doc.metadata) ||
      (doc.metadata.version ?? doc.metadata.dashboard_version) !== d.version ||
      !Array.isArray(doc.placements) ||
      doc.placements.length !== d.placements ||
      !Array.isArray(doc.sections) ||
      doc.sections.length !== d.sections
    )
      fail();
    authoredIds = doc.placements.map((p: unknown) => id(record(p) ? p.placement_id : null));
    sectionIds = doc.sections.map((s: unknown) => id(record(s) ? s.section_id : null));
    if (
      new Set(authoredIds).size !== authoredIds.length ||
      new Set(sectionIds).size !== sectionIds.length
    )
      fail();
  }
  if (m.data_visibility === "definition_only" && m.canvas !== null) fail();
  if (m.canvas !== null) {
    const canvas = readWorkspaceSnapshot(m.canvas, {
      ...context,
      resourceId: m.dashboard_id as string,
    });
    if (
      canvas.sections.length !== sectionIds.length ||
      canvas.sections.some((s) => !sectionIds.includes(s.id)) ||
      canvas.placements.some((p) => !authoredIds.includes(p.authored_id))
    )
      fail();
    const definition = record(m.definition) ? m.definition : null;
    if (
      !definition ||
      canvas.document_version !== definition.version ||
      canvas.name !== definition.name ||
      canvas.author ||
      canvas.document_mode !== (kind === "share" ? "published" : "snapshot")
    )
      fail();
  } else if (m.definition !== null && m.data_visibility === "authorized_runtime_data") fail();
  return value as SharedView;
}
