export type Check = (value: unknown) => boolean;
export const text: Check = (value) => typeof value === "string";
export const bool: Check = (value) => typeof value === "boolean";
export const count: Check = (value) => Number.isSafeInteger(value) && Number(value) >= 0;
export const nullable =
  (check: Check): Check =>
  (value) =>
    value === null || check(value);
export const list =
  (check: Check): Check =>
  (value) =>
    Array.isArray(value) && value.length <= 10000 && value.every(check);
export const choice =
  (...values: unknown[]): Check =>
  (value) =>
    values.includes(value);
export const record = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
export const shape =
  (fields: Record<string, Check>): Check =>
  (value) =>
    record(value) && Object.entries(fields).every(([key, check]) => check(value[key]));
export const href: Check = (value) =>
  typeof value === "string" &&
  /^\/missions(?:\/[^\\\s?#]*)?(?:\?[^\\\s#]*)?(?:#[^\\\s]*)?$/.test(value);
// Legacy presentation DTOs carry markup attributes. Do not admit event handlers,
// arbitrary URLs, or arbitrary DOM properties through v-bind.
const attributeChecks: Record<string, Check> = {
  id: text,
  class: text,
  href,
  "aria-label": text,
  "aria-hidden": choice("true", "false"),
  "data-phx-link": choice("redirect", "patch"),
  "data-phx-link-state": choice("push", "replace"),
};
export const attrs: Check = (value) =>
  record(value) &&
  Object.entries(value).every(
    ([key, item]) => Object.hasOwn(attributeChecks, key) && (attributeChecks[key]?.(item) ?? false),
  );
export const element = shape({ attrs });
export const label = shape({ attrs, text });
export const breadcrumb = shape({ label: text, href: nullable(href) });
export const breadcrumbs = shape({ breadcrumbs: list(breadcrumb) });
export const tone = choice("info", "ready", "blocked");
export const detailCard = shape({
  id: text,
  title: text,
  rows: list(
    shape({
      label: text,
      value: (value) => value === null || text(value) || typeof value === "number",
      href: nullable(href),
      style: choice("default", "mono", "hash"),
    }),
  ),
});
export function assertShape(check: Check, value: unknown): void {
  if (!check(value)) throw new Error("Invalid Catalog presentation.");
}
