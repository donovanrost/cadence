export const runtimeDefaultsMaxBytes = 32768;
export type RuntimeDefaults = Record<string, unknown>;
const bytes = (text: string) => new TextEncoder().encode(text).length;
function object(value: unknown): value is RuntimeDefaults {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function bounded(value: unknown, depth: number): boolean {
  if (depth > 8) return false;
  if (value === null || typeof value === "boolean") return true;
  if (typeof value === "number")
    return Number.isFinite(value) && Math.abs(value) <= Number.MAX_SAFE_INTEGER;
  if (typeof value === "string") return bytes(value) <= 4096;
  if (Array.isArray(value)) return value.length <= 100 && value.every((v) => bounded(v, depth + 1));
  if (object(value)) {
    const entries = Object.entries(value);
    return (
      entries.length <= 64 && entries.every(([k, v]) => bytes(k) <= 256 && bounded(v, depth + 1))
    );
  }
  return false;
}
export function parseRuntimeDefaults(json: unknown): RuntimeDefaults {
  if (typeof json !== "string" || bytes(json) > runtimeDefaultsMaxBytes)
    throw Error("Runtime defaults must fit within 32 KiB.");
  let value: unknown;
  try {
    value = JSON.parse(json);
  } catch {
    throw Error("Enter valid JSON for runtime defaults.");
  }
  if (!object(value) || !bounded(value, 0))
    throw Error(
      "Use a JSON object with bounded values, at most 8 nested levels, 64 fields per object and 100 items per list.",
    );
  return value;
}
