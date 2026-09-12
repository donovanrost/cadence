import type { Roster } from "./contracts";

export function directoryHref(
  roster: Roster,
  changes: Record<string, string | number> = {},
): string {
  const query = new URLSearchParams({
    q: roster.search,
    sort: roster.sort_by,
    dir: roster.sort_dir,
    page: String(roster.page),
    pageSize: String(roster.page_size),
    filter: roster.filter,
  });
  for (const [key, value] of Object.entries(changes)) query.set(key, String(value));
  // oxlint-disable-next-line unicorn/no-useless-spread -- Iterate a snapshot because the loop can mutate its source.
  for (const [key, value] of [...query]) if (!value) query.delete(key);
  return `${roster.href}?${query}`;
}
