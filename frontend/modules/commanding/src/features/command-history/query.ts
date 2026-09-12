import type { HistoryQuery } from "./types";
export const identity = (v: unknown): v is string =>
  typeof v === "string" &&
  v.length > 0 &&
  new TextEncoder().encode(v).length <= 256 &&
  !/[\uD800-\uDFFF]/u.test(v) &&
  !/[\x00-\x1f\x7f]/.test(v);
const keys = ["release", "release_after", "verifier_after", "verifier"] as const;
export function readHistoryQuery(value: unknown): HistoryQuery {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid command history query");
  const v = value as Record<string, unknown>;
  if (Object.keys(v).some((k) => !(keys as readonly string[]).includes(k)))
    throw Error("Unknown command history query");
  const result = Object.fromEntries(
    keys.map((k) => [k, Object.hasOwn(v, k) ? v[k] : ""]),
  ) as HistoryQuery;
  if (
    !Object.values(result).every((v) => v === "" || identity(v)) ||
    (result.verifier && !result.release)
  )
    throw Error("Invalid command history selection");
  return result;
}
export function commandHistoryHref(
  mission: string,
  request: string,
  query: Partial<HistoryQuery> = {},
): string {
  if (
    !identity(mission) ||
    !identity(request) ||
    [".", ".."].includes(mission) ||
    [".", ".."].includes(request)
  )
    throw Error("Invalid command history identity");
  const admitted = readHistoryQuery(query),
    search = new URLSearchParams();
  for (const key of keys) if (admitted[key]) search.set(key, admitted[key]);
  return `/missions/${encodeURIComponent(mission)}/ops/commands/requests/${encodeURIComponent(request)}/history${search.size ? `?${search}` : ""}`;
}
