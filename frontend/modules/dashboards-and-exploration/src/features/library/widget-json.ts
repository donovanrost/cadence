const bytes = (s: string) => new TextEncoder().encode(s).length;
const object = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === "object" && !Array.isArray(v);
function bounded(v: unknown, depth: number): boolean {
  if (depth > 8) return false;
  if (v === null || typeof v === "boolean") return true;
  if (typeof v === "number")
    return Number.isFinite(v) && Math.abs(v) <= Number.MAX_SAFE_INTEGER - 1;
  if (typeof v === "string") return bytes(v) <= 4096;
  if (Array.isArray(v)) return v.length <= 100 && v.every((i) => bounded(i, depth + 1));
  if (object(v))
    return (
      Object.keys(v).length <= 64 &&
      Object.entries(v).every(([k, i]) => bytes(k) <= 256 && bounded(i, depth + 1))
    );
  return false;
}
export function parseWidgetJson(json: unknown): Record<string, unknown> {
  if (typeof json !== "string" || bytes(json) > 32768)
    throw Error("Widget JSON must fit within 32 KiB.");
  let value: unknown;
  try {
    value = JSON.parse(json);
  } catch {
    throw Error("Enter valid widget JSON.");
  }
  if (
    !object(value) ||
    !bounded(value, 0) ||
    Object.keys(value).some(
      (k) => !["widget_type_id", "widget_type_version", "title", "binding", "options"].includes(k),
    ) ||
    typeof value.widget_type_id !== "string" ||
    !value.widget_type_id ||
    bytes(value.widget_type_id) > 256 ||
    // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
    /[\u0000-\u001f]/u.test(value.widget_type_id) ||
    (value.title !== undefined && value.title !== null && typeof value.title !== "string") ||
    (value.widget_type_version !== undefined &&
      (!Number.isSafeInteger(value.widget_type_version) ||
        (value.widget_type_version as number) < 1)) ||
    !object(value.binding === undefined ? {} : value.binding) ||
    !object(value.options === undefined ? {} : value.options)
  )
    throw Error("Use a bounded widget definition object with a type, binding and options.");
  return value;
}
export const widgetExample = JSON.stringify(
  {
    widget_type_id: "cadence.value_tile",
    widget_type_version: 1,
    title: "Battery voltage",
    binding: { source: "telemetry", observables: ["tlm.hk.battery_voltage"], sampling: "latest" },
    options: { precision: 2, show_unit: true },
  },
  null,
  2,
);
