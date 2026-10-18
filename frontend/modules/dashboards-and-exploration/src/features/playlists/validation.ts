import { arrayOf, record } from "@cadence/plugin-sdk/admission";
import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { readWorkspaceSnapshot } from "../../workspace";
import type { DirectoryState, Directory, Search, Presentation, Receipt } from "./contracts";
const bytes = (s: string) => new TextEncoder().encode(s).length;
const fail = (): never => {
  throw Error("Invalid playlist contract");
};
export function exact(value: unknown, keys: string[]): Record<string, unknown> {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.keys(value).sort().join("|") !== [...keys].sort().join("|")
  )
    return fail();
  return value as Record<string, unknown>;
}
const text = (v: unknown, max = 4096): v is string => typeof v === "string" && bytes(v) <= max;
const id = (v: unknown): v is string => text(v, 256) && v.length > 0;
const integer = (v: unknown, min: number, max = Number.MAX_SAFE_INTEGER - 1) =>
  Number.isSafeInteger(v) && (v as number) >= min && (v as number) <= max;
function identity(v: Record<string, unknown>, context: OpsPageContext) {
  if (
    v.version !== 1 ||
    !id(context.organizationId) ||
    !id(context.missionId) ||
    v.organization_id !== context.organizationId ||
    v.mission_id !== context.missionId
  )
    fail();
}
function query(value: unknown) {
  const v = exact(value, ["q", "after"]);
  if (!text(v.q, 120) || v.q.trim() !== v.q || !(v.after === null || id(v.after))) fail();
}
function page(value: unknown, row: (v: unknown) => void) {
  const p = exact(value, ["rows", "next"]);
  if (!arrayOf(p.rows, record) || p.rows.length > 25) return fail();
  p.rows.forEach((value) => row(value));
  const ids = p.rows.map((r) => r.id);
  if (new Set(ids).size !== ids.length) fail();
  if (p.next !== null && (p.rows.length !== 25 || p.next !== ids[24])) fail();
}
function playlist(value: unknown, present = false) {
  const v = exact(value, [
    "id",
    "name",
    "description",
    "dwell_seconds",
    "wallboard_mode",
    ...(present ? [] : ["count"]),
  ]);
  if (
    !id(v.id) ||
    !text(v.name, 120) ||
    !v.name ||
    !(v.description === null || text(v.description)) ||
    !integer(v.dwell_seconds, 5, 900) ||
    typeof v.wallboard_mode !== "boolean" ||
    (!present && !integer(v.count, 1, 100))
  )
    fail();
}
function choice(value: unknown) {
  const v = exact(value, ["id", "name", "published_version"]);
  if (
    !id(v.id) ||
    !text(v.name) ||
    !(v.published_version === null || integer(v.published_version, 1))
  )
    fail();
}
export function readDirectory(value: unknown, context: OpsPageContext): Directory {
  const v = exact(value, [
    "version",
    "organization_id",
    "mission_id",
    "query",
    "playlists",
    "choices",
  ]);
  identity(v, context);
  if (context.resourceId !== undefined) fail();
  query(v.query);
  page(v.playlists, playlist);
  page(v.choices, choice);
  return value as Directory;
}
export function readState(value: unknown, context: OpsPageContext): DirectoryState {
  const v = exact(value, ["model", "sequence", "phase"]);
  if (!integer(v.sequence, 0, 1_000_000) || !["ready", "review"].includes(v.phase as string))
    fail();
  readDirectory(v.model, context);
  return value as DirectoryState;
}
export function readSearch(value: unknown, context: OpsPageContext): Search {
  const v = exact(value, ["version", "organization_id", "mission_id", "query", "choices"]);
  identity(v, context);
  if (context.resourceId !== undefined) fail();
  query(v.query);
  page(v.choices, choice);
  return value as Search;
}
export function readReceipt(value: unknown): Receipt {
  const v = exact(value, ["id", "name", "count"]);
  if (!id(v.id) || !text(v.name, 120) || !v.name || !integer(v.count, 1, 100)) fail();
  return value as Receipt;
}
export function readPresentation(value: unknown, context: OpsPageContext): Presentation {
  const v = exact(value, [
    "version",
    "organization_id",
    "mission_id",
    "playlist",
    "index",
    "total",
    "playing",
    "loaded_at",
    "current",
  ]);
  identity(v, context);
  playlist(v.playlist, true);
  const p = v.playlist as Presentation["playlist"];
  if (
    p.id !== context.resourceId ||
    !integer(v.total, 1, 100) ||
    !integer(v.index, 0, (v.total as number) - 1) ||
    typeof v.playing !== "boolean" ||
    !text(v.loaded_at, 64) ||
    !Number.isFinite(Date.parse(v.loaded_at))
  )
    fail();
  const current = exact(v.current, ["id", "name", "snapshot"]);
  if (!id(current.id) || !(current.name === null || text(current.name))) fail();
  if (current.snapshot !== null) {
    const model = readWorkspaceSnapshot(current.snapshot, {
      ...context,
      resourceId: current.id as string,
    });
    if (model.document_mode !== "published" || current.name === null) fail();
  }
  return value as Presentation;
}
