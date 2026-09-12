export type Check = (value: unknown) => boolean;
export const record = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
export const text: Check = (value) => typeof value === "string";
export const bool: Check = (value) => typeof value === "boolean";
export const count: Check = (value) => Number.isSafeInteger(value) && Number(value) >= 0;
export const choice =
  (...values: unknown[]): Check =>
  (value) =>
    values.includes(value);
export const nullable =
  (check: Check): Check =>
  (value) =>
    value === null || check(value);
export const list =
  (check: Check): Check =>
  (value) =>
    Array.isArray(value) && value.length <= 10000 && value.every(check);
export const shape =
  (fields: Record<string, Check>): Check =>
  (value) =>
    record(value) && Object.entries(fields).every(([key, check]) => check(value[key]));
export const href: Check = (value) =>
  typeof value === "string" &&
  /^\/missions(?:\/[^\\\s?#]*)?(?:\?[^\\\s#]*)?(?:#[^\\\s]*)?$/.test(value);
const allowedAttrs: Record<string, Check> = {
  id: text,
  class: text,
  href,
  "data-phx-link": choice("redirect", "patch"),
  "data-phx-link-state": choice("push", "replace"),
};
export const attrs: Check = (value) =>
  record(value) &&
  Object.entries(value).every(
    ([key, item]) => Object.hasOwn(allowedAttrs, key) && allowedAttrs[key]!(item),
  );
export const tone = choice("info", "ready", "attention", "blocked");
export const status = shape({ tone, label: text });
export function assertShape(check: Check, value: unknown): void {
  if (!check(value)) throw new Error("Invalid mission presentation.");
}
