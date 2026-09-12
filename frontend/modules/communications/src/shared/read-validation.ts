import type { Collection, Navigation, ReadContext } from "./read-contracts.ts";
export function invalid(): never {
  throw new Error("The Communications read response is invalid.");
}
export function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return invalid();
  return value as Record<string, unknown>;
}
export function text(value: unknown, empty = false, max = 4096): string {
  if (typeof value !== "string" || value.length > max || (!empty && !value.trim()))
    return invalid();
  return value;
}
export function identifier(value: unknown): string {
  const id = text(value, false, 255);
  if (id === "." || id === ".." || /[\\/\u0000-\u001f]/.test(id)) return invalid();
  return id;
}
export function integer(value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < min || value > max)
    return invalid();
  return value;
}
export function boolean(value: unknown): boolean {
  if (typeof value !== "boolean") return invalid();
  return value;
}
export function choice<const T extends readonly string[]>(value: unknown, values: T): T[number] {
  if (typeof value !== "string" || !values.includes(value)) return invalid();
  return value;
}
export function missionPath(context: ReadContext): string {
  return "/missions/" + encodeURIComponent(identifier(context.missionId));
}
export function href(value: unknown, context: ReadContext): string {
  const path = text(value);
  if (!path.startsWith("/") || path.startsWith("//") || /[\\\u0000-\u0020]/.test(path))
    return invalid();
  const pathname = path.split(/[?#]/, 1)[0];
  for (const segment of pathname.split("/")) {
    let decoded: string;
    try {
      decoded = decodeURIComponent(segment);
    } catch {
      return invalid();
    }
    if (decoded === "." || decoded === ".." || /[\\/\u0000-\u001f]/.test(decoded)) return invalid();
  }
  const base = missionPath(context);
  if (!(pathname === base || pathname.startsWith(base + "/"))) return invalid();
  return path;
}
export function exactHref(value: unknown, expected: string, context: ReadContext): string {
  const path = href(value, context);
  if (path !== expected) return invalid();
  return path;
}
export function navigation(value: unknown, context: ReadContext, expected: string): Navigation {
  const input = record(value);
  const items = input.breadcrumbs;
  if (!Array.isArray(items) || items.length > 12) return invalid();
  return {
    fallback_href: exactHref(input.fallback_href, expected, context),
    breadcrumbs: items.map((value) => {
      const item = record(value);
      return {
        label: text(item.label),
        href: item.href === null ? null : href(item.href, context),
      };
    }),
  };
}
export function collection<Row extends { id: string }>(
  value: unknown,
  context: ReadContext,
  section: string,
  readRow: (input: unknown, context: ReadContext) => Row,
): Collection<Row> {
  const input = record(value),
    data = record(input.data);
  const pageSize = integer(data.page_size, 1, 100),
    total = integer(data.total_count),
    pageCount = integer(data.page_count, 1);
  const page = integer(data.page, 1, pageCount);
  if (
    pageCount !== Math.max(1, Math.ceil(total / pageSize)) ||
    !Array.isArray(data.items) ||
    data.items.length > pageSize
  )
    return invalid();
  const items = data.items.map((item) => readRow(item, context));
  if (
    new Set(items.map((item) => item.id)).size !== items.length ||
    items.length !== Math.min(pageSize, Math.max(0, total - (page - 1) * pageSize))
  )
    return invalid();
  return {
    navigation: navigation(input.navigation, context, missionPath(context) + "/comms/" + section),
    data: {
      title: text(data.title),
      items,
      page,
      page_size: pageSize,
      page_count: pageCount,
      total_count: total,
      query: data.query === null ? "" : text(data.query, true, 240),
      sort: choice(data.sort, ["display_name"]),
      dir: choice(data.dir, ["asc", "desc"]),
    },
  };
}
