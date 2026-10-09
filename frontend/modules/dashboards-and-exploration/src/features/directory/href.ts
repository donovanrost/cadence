import type { DirectoryFilters } from "./contracts";

const defaults: Omit<DirectoryFilters, "page"> = {
  query: "",
  tags: [],
  starred: false,
  archived: false,
  sort: "updated",
};

/** The canonical directory URL; default filters are omitted. */
export function directoryHref(
  mission: string,
  filters: Partial<Omit<DirectoryFilters, "page">> = {},
  page = 1,
): string {
  const chosen = { ...defaults, ...filters };
  const params = new URLSearchParams();
  if (chosen.query.trim()) params.set("query", chosen.query.trim());
  if (chosen.tags.length) params.set("tags", chosen.tags.join(","));
  if (chosen.starred) params.set("starred", "true");
  if (chosen.archived) params.set("archived", "true");
  if (chosen.sort !== "updated") params.set("sort", chosen.sort);
  if (page > 1) params.set("page", String(page));
  const search = params.toString();
  return `${dashboardsPath(mission)}${search ? `?${search}` : ""}`;
}

export const dashboardsPath = (mission: string) =>
  `/missions/${encodeURIComponent(mission)}/ops/dashboards`;

export const dashboardHref = (mission: string, id: string) =>
  `${dashboardsPath(mission)}/${encodeURIComponent(id)}`;
