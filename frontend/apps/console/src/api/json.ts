import { DecodeError, type Reader } from "./decode.ts";

/**
 * Schema-driven JSON documents (planning templates and policy, profile documents, kind schemas):
 * the server owns the shape, so values are read through schema paths, not decoded up front.
 * These helpers narrow with guards instead of `as` (typing plan §12 A1).
 */
export type JsonObject = Readonly<Record<string, unknown>>;

/** A plain JSON object: not null, not an array. */
export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/**
 * Typing rule A (plan §12B): a word map for open server text (provider reason codes, setup gaps)
 * is keyed by its own literal keys, the vocabulary the console words, and looked up through this
 * guard, so a misspelled key is a compile error and text the console doesn't word finds nothing.
 */
export const isKeyOf = <M extends object>(
  map: M,
  key: string | null | undefined,
): key is Extract<keyof M, string> => key !== null && key !== undefined && Object.hasOwn(map, key);

/** The value as a JSON object, or null when it isn't one. */
export const recordOf = (value: unknown): Record<string, unknown> | null =>
  isRecord(value) ? value : null;

/** Reader for a server document read later through schema paths. */
export const jsonObject: Reader<JsonObject> = (value, path = "") => {
  if (!isRecord(value)) throw new DecodeError(path, "object");
  return value;
};

/** The value at `keys` inside nested objects, or undefined when any step isn't an object. */
export function pathGet(doc: unknown, keys: readonly string[]): unknown {
  let at: unknown = doc;
  for (const key of keys) {
    if (!isRecord(at)) return undefined;
    at = at[key];
  }
  return at;
}

/** The child object at `key`, created (or replacing a non-object) when missing. */
export function childRecord(parent: Record<string, unknown>, key: string): Record<string, unknown> {
  const current = parent[key];
  if (isRecord(current)) return current;
  const fresh: Record<string, unknown> = {};
  parent[key] = fresh;
  return fresh;
}

/** Sets `value` at `keys`, creating intermediate objects as needed. */
export function pathSet(doc: Record<string, unknown>, keys: readonly string[], value: unknown) {
  const last = keys.at(-1);
  if (last === undefined) return;
  let at = doc;
  for (const key of keys.slice(0, -1)) at = childRecord(at, key);
  at[last] = value;
}
