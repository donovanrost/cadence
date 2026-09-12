import { commandStates, type MonitorQuery } from "./monitor.contracts";
export function queryText(value: unknown): value is string {
  return (
    typeof value === "string" &&
    new TextEncoder().encode(value).length <= 256 &&
    !/[\x00-\x1f\x7f]/.test(value)
  );
}
export function readMonitorQuery(value: unknown): MonitorQuery {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid command query");
  const entries = Object.entries(value);
  if (
    entries.some(
      ([key, val]) =>
        !["status", "target", "query", "page", "focus_command_id"].includes(key) || !queryText(val),
    )
  )
    throw Error("Invalid command query");
  const query = { status: "all", target: "all", query: "", page: "1", ...value } as MonitorQuery;
  if (query.status === "") query.status = "all";
  if (query.target === "") query.target = "all";
  query.query = query.query.trim();
  if (
    (query.status !== "all" &&
      !commandStates.includes(query.status as (typeof commandStates)[number])) ||
    !/^\d+$/.test(query.page) ||
    Number(query.page) < 1 ||
    Number(query.page) > 1_000_000 ||
    query.focus_command_id === ""
  )
    throw Error("Invalid command query");
  query.page = String(Number(query.page));
  return query;
}
export function monitorHref(mission: string, query: MonitorQuery): string {
  if (!queryText(mission) || !mission || [".", ".."].includes(mission))
    throw Error("Invalid command mission");
  const admitted = readMonitorQuery(query),
    search = new URLSearchParams();
  for (const key of ["status", "target", "query", "focus_command_id", "page"] as const) {
    const value = admitted[key];
    if (
      value &&
      !((key === "status" || key === "target") && value === "all") &&
      !(key === "page" && value === "1")
    )
      search.set(key, value);
  }
  return `/missions/${encodeURIComponent(mission)}/ops/commands${search.size ? `?${search}` : ""}`;
}
