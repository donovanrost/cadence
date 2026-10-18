import { oneOf, arrayOf, record, type Snapshot } from "@cadence/plugin-sdk/admission";
import type { SpacecraftPageContext } from "@cadence/plugin-sdk/spacecraft-pages";

export type ProfileEvidence = Snapshot<{
  status: "unbound" | "unavailable" | "ready";
  id: string | null;
  version: number | null;
  name: string | null;
  lifecycle: "active" | "deleted" | null;
  uplink: "tc" | "uslp" | null;
  packet: "space_packet" | null;
}>;
export type SpacecraftCommandingModel = Snapshot<{
  version: 1;
  context: SpacecraftPageContext;
  mission_name: string;
  spacecraft_name: string;
  scid: number | null;
  profile: ProfileEvidence;
  query: { page: number; query: string };
  endpoints: {
    page: number;
    total_count: number;
    items: { id: string; name: string | null; scid: number | null }[];
  };
}>;
export type SpacecraftCommandingProps = { mission_id?: string; spacecraft_id?: string };
export const identifier = (v: unknown): v is string =>
  typeof v === "string" && v.length <= 120 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(v);
const text = (v: unknown, max = 800): v is string =>
  typeof v === "string" &&
  new TextEncoder().encode(v).length <= max &&
  !v.split("").some((c) => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127);
const integer = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) >= 0;
const nullableScid = (v: unknown) => v === null || integer(v);
export function spacecraftCommandingHref(mission: unknown, spacecraft: unknown): string {
  if (!identifier(mission) || !identifier(spacecraft)) throw Error("Invalid spacecraft identity");
  return `/missions/${encodeURIComponent(mission)}/spacecraft/${encodeURIComponent(spacecraft)}/commanding`;
}
export function readSpacecraftCommanding(
  value: unknown,
  context: SpacecraftPageContext,
): SpacecraftCommandingModel {
  if (!validSpacecraftCommanding(value, context)) throw Error("Invalid commanding document");
  return value;
}
function validSpacecraftCommanding(
  value: unknown,
  context: SpacecraftPageContext,
): value is SpacecraftCommandingModel {
  if (!record(value) || value.version !== 1 || !record(value.context))
    throw Error("Invalid commanding document");
  for (const key of ["organizationId", "missionId", "spacecraftId"] as const) {
    if (!identifier(context[key]) || value.context[key] !== context[key])
      throw Error("Invalid commanding context");
  }
  if (
    !text(value.mission_name) ||
    !value.mission_name ||
    !text(value.spacecraft_name) ||
    !value.spacecraft_name ||
    !nullableScid(value.scid)
  )
    throw Error("Invalid spacecraft evidence");
  const p = value.profile;
  if (
    !record(p) ||
    !oneOf(["unbound", "unavailable", "ready"], p.status) ||
    !(p.id === null || identifier(p.id)) ||
    !(p.version === null || (integer(p.version) && p.version > 0))
  )
    throw Error("Invalid pinned profile");
  if (p.status === "ready") {
    if (
      !identifier(p.id) ||
      !integer(p.version) ||
      p.version < 1 ||
      !text(p.name) ||
      !p.name ||
      !oneOf(["active", "deleted"], p.lifecycle) ||
      !oneOf(["tc", "uslp"], p.uplink) ||
      p.packet !== "space_packet"
    )
      throw Error("Invalid profile evidence");
  } else if (
    [p.name, p.lifecycle, p.uplink, p.packet].some((v) => v !== null) ||
    (p.status === "unbound" && (p.id !== null || p.version !== null)) ||
    (p.status === "unavailable" && p.id === null && p.version === null)
  )
    throw Error("Invalid unavailable profile");
  const q = value.query,
    endpoints = value.endpoints;
  if (
    !record(q) ||
    !integer(q.page) ||
    q.page < 1 ||
    q.page > 100_000 ||
    !text(q.query, 240) ||
    q.query !== q.query.trim() ||
    !record(endpoints) ||
    endpoints.page !== q.page ||
    !integer(endpoints.total_count) ||
    !arrayOf(endpoints.items, record)
  )
    throw Error("Invalid endpoint page");
  const last = Math.max(1, Math.ceil(endpoints.total_count / 25));
  if (
    q.page > last ||
    endpoints.items.length !== Math.min(25, Math.max(0, endpoints.total_count - (q.page - 1) * 25))
  )
    throw Error("Incomplete endpoint page");
  const seen = new Set<string>();
  for (const row of endpoints.items) {
    if (
      !record(row) ||
      !identifier(row.id) ||
      seen.has(row.id) ||
      !(row.name === null || text(row.name)) ||
      !nullableScid(row.scid)
    )
      throw Error("Invalid source endpoint");
    seen.add(row.id);
  }
  return true;
}
export function endpointPageHref(model: SpacecraftCommandingModel, page: number): string {
  const query = new URLSearchParams();
  if (model.query.query) query.set("query", model.query.query);
  if (page > 1) query.set("page", String(page));
  return (
    spacecraftCommandingHref(model.context.missionId, model.context.spacecraftId) +
    (query.size ? `?${query}` : "")
  );
}
