export type Page<T> = {
  items: T[];
  total_count: number;
  page: number;
  page_size: 25;
  previous_href: string | null;
  next_href: string | null;
};
export const record = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
export const text = (v: unknown, max = 240): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
export const id = (v: unknown): v is string => text(v) && v.length > 0 && !/[/?#\s]/.test(v);
export const name = (v: unknown): v is string => text(v) && v.trim().length > 0;
export const integer = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
export const stamp = (v: unknown): v is string => text(v, 64) && Number.isFinite(Date.parse(v));
export const nullable = (v: unknown, test: (v: unknown) => boolean) => v === null || test(v);
const numbers = ["page", "history_page", "activation_page", "points_page", "spacecraft_page"];
const strings = [
  "q",
  "points_q",
  "spacecraft_q",
  "spacecraft",
  "definition",
  "point",
  "set",
  "severity",
];
function localLink(v: unknown, base: string): v is string {
  if (
    !text(v, 8192) ||
    !v.startsWith(base + "?") ||
    /[\\#]/.test(v) ||
    v.split("").some((c) => c.charCodeAt(0) <= 32)
  )
    return false;
  const q = new URLSearchParams(v.slice(base.length + 1));
  return (
    new Set(q.keys()).size === [...q.keys()].length &&
    [...q].every(([k, x]) =>
      numbers.includes(k) || k === "version"
        ? /^[1-9][0-9]{0,5}$/.test(x) && Number(x) <= 100000
        : strings.includes(k) && text(x),
    )
  );
}
export function page<T>(
  v: unknown,
  row: (v: unknown) => v is T,
  base: string,
  link: (v: unknown) => boolean = (v) => localLink(v, base),
): v is Page<T> {
  return (
    record(v) &&
    Array.isArray(v.items) &&
    v.items.every(row) &&
    v.items.length <= 25 &&
    integer(v.total_count) &&
    integer(v.page) &&
    v.page >= 1 &&
    v.page <= Math.max(1, Math.ceil(v.total_count / 25)) &&
    v.page_size === 25 &&
    v.items.length === Math.min(25, Math.max(0, v.total_count - (v.page - 1) * 25)) &&
    (v.previous_href === null ? v.page === 1 : v.page > 1 && link(v.previous_href)) &&
    (v.next_href === null
      ? v.page * 25 >= v.total_count
      : v.page * 25 < v.total_count && link(v.next_href))
  );
}
export function definitionLink(v: unknown, base: string, id: string, version: number) {
  if (!localLink(v, base)) return false;
  const q = new URLSearchParams(v.slice(base.length + 1));
  return q.get("definition") === id && q.get("version") === String(version);
}
