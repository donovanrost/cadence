import { DecodeError, integer, token, type Reader } from "./decode.ts";

/**
 * Branded resource ids (typing plan §12C, audit §1.2). A `MissionId` and a `SpacecraftId` are
 * both strings on the wire, but passing one where the other belongs is a compile error here.
 * Only this module mints them: decoders for server data, `*Param` helpers for route params.
 * Outside `api/`, a brand comes from one of these, never from `as`.
 *
 * - `MissionId`: the mission's id. Routes carry the slug; the session maps slug → id.
 * - `SpacecraftId`: the spacecraft's id (setup routes' `:scId`).
 * - `Scid`: the numeric spacecraft control id (ops `fleet/:scId(\d+)`). A number, not an id.
 * - `StationId`: the station's id, never its code.
 * - `OrganizationId`: the organization's id. Routes carry its slug.
 * - `DashboardId`: a dashboard's id (`telemetry/dashboards/:dashboardId`).
 * - `PointId`: a telemetry point's id, which Investigate's reads take beside a `SpacecraftId`.
 */
declare const brand: unique symbol;
type Brand<T, Name extends string> = T & { readonly [brand]: Name };

export type MissionId = Brand<string, "MissionId">;
export type SpacecraftId = Brand<string, "SpacecraftId">;
export type StationId = Brand<string, "StationId">;
export type Scid = Brand<number, "Scid">;
export type OrganizationId = Brand<string, "OrganizationId">;
export type DashboardId = Brand<string, "DashboardId">;
export type PointId = Brand<string, "PointId">;

/** The one place a checked value becomes branded. */
function mint<B>(value: string | number): B {
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- the brand's only constructor (§12C)
  return value as B;
}

const tokenId =
  <B>(): Reader<B> =>
  (value, path = "") =>
    mint<B>(token(value, path));

export const missionId: Reader<MissionId> = tokenId<MissionId>();
export const spacecraftId: Reader<SpacecraftId> = tokenId<SpacecraftId>();
export const stationId: Reader<StationId> = tokenId<StationId>();
export const organizationId: Reader<OrganizationId> = tokenId<OrganizationId>();
export const dashboardId: Reader<DashboardId> = tokenId<DashboardId>();
export const pointId: Reader<PointId> = tokenId<PointId>();

export const scid: Reader<Scid> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 0) throw new DecodeError(path, "non-negative integer");
  return mint<Scid>(n);
};

type ParamValue = string | readonly string[] | undefined;
const single = (value: ParamValue): string | null => {
  const text = typeof value === "string" ? value : value?.[0];
  return typeof text === "string" && text !== "" && text.trim() === text ? text : null;
};

/** A route param as a spacecraft id; null when absent or blank. */
export const spacecraftIdParam = (value: ParamValue): SpacecraftId | null => {
  const text = single(value);
  return text === null ? null : mint<SpacecraftId>(text);
};

/** A route param as a station id; null when absent or blank. */
export const stationIdParam = (value: ParamValue): StationId | null => {
  const text = single(value);
  return text === null ? null : mint<StationId>(text);
};

/** A route param as a dashboard id; null when absent or blank. */
export const dashboardIdParam = (value: ParamValue): DashboardId | null => {
  const text = single(value);
  return text === null ? null : mint<DashboardId>(text);
};

/**
 * A required route segment as a dashboard id (`telemetry/dashboards/:dashboardId`). The router only
 * matches the route with that segment present, so it is never absent; a wrong one reads as not found.
 */
export const dashboardIdSegment = (value: string): DashboardId => mint<DashboardId>(value);

/** A route param as a point id; null when absent or blank. */
export const pointIdParam = (value: ParamValue): PointId | null => {
  const text = single(value);
  return text === null ? null : mint<PointId>(text);
};

/** A route param as a SCID; null unless it's all digits. */
export const scidParam = (value: ParamValue): Scid | null => {
  const text = single(value);
  return text !== null && /^\d+$/.test(text) ? mint<Scid>(Number(text)) : null;
};

/** The SCID as a route param (`fleet/:scId`). */
export const scidText = (value: Scid): string => String(value);
