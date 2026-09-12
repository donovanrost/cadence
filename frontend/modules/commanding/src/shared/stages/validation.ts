import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
export const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
export const bytes = (v: string) => new TextEncoder().encode(v).length;
export const text = (v: unknown, max = 4000): v is string =>
  typeof v === "string" && bytes(v) <= max && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v);
export const id = (v: unknown): v is string =>
  typeof v === "string" && v.length <= 120 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(v);
export const digest = (v: unknown): v is string =>
  typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
export const order = (v: unknown): v is number =>
  Number.isSafeInteger(v) && Number(v) >= 0 && Number(v) <= 2147483647;
export const time = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
export const nullableText = (v: unknown, max = 4000) => v === null || text(v, max);
export const stageStates = [
  "draft",
  "in_review",
  "ready_to_submit",
  "submitted",
  "canceled",
] as const;
export type StageState = (typeof stageStates)[number];
export const stageState = (v: unknown): v is StageState => stageStates.includes(v as StageState);
export const visibility = (v: unknown): v is "private" | "shared" =>
  v === "private" || v === "shared";
export function fail(): never {
  throw Error("Unavailable command stage data");
}
export type Identity<V extends 1 | 2 = 1> = {
  version: V;
  context: OpsPageContext;
  actor_id: string;
  mission_name: string;
};
export function identity(
  v: unknown,
  context: OpsPageContext,
): asserts v is Identity & Record<string, unknown>;
export function identity(
  v: unknown,
  context: OpsPageContext,
  version: 2,
): asserts v is Identity<2> & Record<string, unknown>;
export function identity(
  v: unknown,
  context: OpsPageContext,
  version: 1 | 2 = 1,
): asserts v is Identity<1 | 2> & Record<string, unknown> {
  if (
    !record(v) ||
    v.version !== version ||
    !record(v.context) ||
    !id(context.organizationId) ||
    !id(context.missionId) ||
    v.context.organizationId !== context.organizationId ||
    v.context.missionId !== context.missionId ||
    !id(v.actor_id) ||
    !text(v.mission_name, 2000)
  )
    fail();
}
export function bounded(v: unknown, limit = 800000): asserts v is Record<string, unknown> {
  if (!record(v) || bytes(JSON.stringify(v)) > limit) fail();
}
