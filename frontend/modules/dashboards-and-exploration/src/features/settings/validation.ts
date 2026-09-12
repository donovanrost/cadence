import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { parseRuntimeDefaults } from "../../shared/runtime-defaults";
import type { SettingsModel, SettingsState, SettingsReceipt, SettingsAction } from "./contracts";

const fail = (): never => {
  throw Error("Invalid dashboard settings model");
};
export function exact(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return fail();
  const r = value as Record<string, unknown>;
  if (Object.keys(r).length !== keys.length || keys.some((k) => !Object.hasOwn(r, k))) fail();
  return r;
}
function text(v: unknown, max: number, empty = false): string {
  if (typeof v !== "string" || new TextEncoder().encode(v).length > max || (!empty && !v.trim()))
    return fail();
  return v;
}
function id(v: unknown): string {
  const s = text(v, 256);
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  return /[\u0000-\u001f]/.test(s) ? fail() : s;
}
function version(v: unknown, max = Number.MAX_SAFE_INTEGER - 1): number {
  return typeof v === "number" && Number.isSafeInteger(v) && v >= 1 && v <= max ? v : fail();
}
function choice(v: unknown, values: string[]) {
  if (typeof v !== "string" || !values.includes(v)) fail();
}
function timestamp(v: unknown) {
  const s = text(v, 64);
  if (!/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(s) || !Number.isFinite(Date.parse(s)))
    fail();
}
function optional(v: unknown, check: (value: unknown) => unknown) {
  if (v !== null) check(v);
}
function page(v: unknown, check: (value: unknown) => void) {
  const p = exact(v, ["rows", "next"]);
  if (!Array.isArray(p.rows) || p.rows.length > 25) return fail();
  const ids = p.rows.map((row) => {
    check(row);
    return id((row as Record<string, unknown>).id);
  });
  if (new Set(ids).size !== ids.length) fail();
  optional(p.next, id);
  if (p.next !== null && (ids.length !== 25 || p.next !== ids.at(-1))) fail();
}
const visibility = (v: unknown) => choice(v, ["authorized_runtime_data", "definition_only"]);

export function readSettingsState(value: unknown, context: OpsPageContext): SettingsState {
  const s = exact(value, ["sequence", "phase", "model"]);
  if (
    !Number.isInteger(s.sequence) ||
    (s.sequence as number) < 0 ||
    (s.sequence as number) > 1_000_000
  )
    fail();
  choice(s.phase, ["ready", "review"]);
  readSettingsModel(s.model, context);
  return value as SettingsState;
}

export function readSettingsReceipt(
  value: unknown,
  observed: SettingsModel,
  action: SettingsAction,
): SettingsReceipt {
  const r = exact(value, [
    "version",
    "dashboard_id",
    "event",
    "document_version",
    "revision",
    "resource_id",
  ]);
  if (
    r.version !== 1 ||
    id(r.dashboard_id) !== observed.dashboard_id ||
    r.event !== action ||
    r.document_version !== observed.document_version + (action === "save_settings" ? 1 : 0) ||
    r.revision !==
      observed.revision + (["save_settings", "archive_dashboard"].includes(action) ? 1 : 0)
  )
    fail();
  if (["create_share", "revoke_share", "create_snapshot"].includes(action)) id(r.resource_id);
  else if (r.resource_id !== null) fail();
  return value as SettingsReceipt;
}

export function readSettingsModel(value: unknown, context: OpsPageContext): SettingsModel {
  const m = exact(value, [
    "version",
    "organization_id",
    "mission_id",
    "dashboard_id",
    "document_version",
    "revision",
    "published_version",
    "lifecycle",
    "name",
    "description",
    "tags",
    "defaults_json",
    "loaded_at",
    "query",
    "shares",
    "snapshots",
    "deployments",
  ]);
  if (
    m.version !== 1 ||
    id(m.organization_id) !== context.organizationId ||
    id(m.mission_id) !== context.missionId ||
    id(m.dashboard_id) !== context.resourceId
  )
    fail();
  const latest = version(m.document_version);
  version(m.revision);
  optional(m.published_version, (v) => version(v, latest));
  choice(m.lifecycle, ["active", "archived"]);
  text(m.name, 120);
  text(m.description, 500, true);
  if (!Array.isArray(m.tags) || m.tags.length > 32) return fail();
  const tags = m.tags.map((t) => text(t, 64));
  if (new Set(tags).size !== tags.length || tags.some((t) => t.trim() !== t)) fail();
  parseRuntimeDefaults(m.defaults_json);
  timestamp(m.loaded_at);
  const q = exact(m.query, ["after_share", "after_snapshot", "after_deployment"]);
  Object.values(q).forEach((v) => optional(v, id));
  page(m.shares, (value) => {
    const s = exact(value, ["id", "data_visibility", "state", "expires_at", "created_at"]);
    visibility(s.data_visibility);
    choice(s.state, ["active", "expired", "revoked"]);
    optional(s.expires_at, timestamp);
    if (s.state === "expired" && s.expires_at === null) fail();
    timestamp(s.created_at);
  });
  page(m.snapshots, (value) => {
    const s = exact(value, [
      "id",
      "document_version",
      "data_visibility",
      "data_semantics",
      "created_at",
    ]);
    version(s.document_version, latest);
    visibility(s.data_visibility);
    choice(s.data_semantics, ["definition_at_version_current_data", "frozen_time_window"]);
    timestamp(s.created_at);
  });
  page(m.deployments, (value) => {
    const d = exact(value, [
      "id",
      "document_version",
      "environment",
      "digest_prefix",
      "status",
      "created_at",
    ]);
    version(d.document_version, latest);
    text(d.environment, 120);
    if (!/^[a-f0-9]{12}$/.test(text(d.digest_prefix, 12))) fail();
    choice(d.status, ["validated", "exported"]);
    timestamp(d.created_at);
  });
  return value as SettingsModel;
}
