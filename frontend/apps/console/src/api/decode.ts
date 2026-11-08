/**
 * Composable runtime readers for external data (HTTP bodies, channel payloads, storage).
 * A reader either returns a value that satisfies its static type or throws DecodeError
 * with the JSON path of the first violation. Static types are inferred from readers so
 * each accepted shape has one definition: `type Session = Decoded<typeof session>`.
 */

export class DecodeError extends Error {
  readonly path: string;
  constructor(path: string, expected: string) {
    super(`${path || "<root>"}: expected ${expected}`);
    this.name = "DecodeError";
    this.path = path;
  }
}

export type Reader<T> = (value: unknown, path?: string) => T;
export type Decoded<R> = R extends Reader<infer T> ? T : never;

const at = (path: string | undefined, key: string | number) =>
  typeof key === "number" ? `${path ?? ""}[${key}]` : path ? `${path}.${key}` : key;

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  value !== null && typeof value === "object" && !Array.isArray(value);

export const string: Reader<string> = (value, path = "") => {
  if (typeof value !== "string") throw new DecodeError(path, "string");
  return value;
};

/** A non-empty string without surrounding whitespace: ids, slugs, codes. */
export const token: Reader<string> = (value, path = "") => {
  const text = string(value, path);
  if (text.length === 0 || text.trim() !== text) throw new DecodeError(path, "token");
  return text;
};

export const number: Reader<number> = (value, path = "") => {
  if (typeof value !== "number" || !Number.isFinite(value))
    throw new DecodeError(path, "finite number");
  return value;
};

export const integer: Reader<number> = (value, path = "") => {
  const n = number(value, path);
  if (!Number.isInteger(n)) throw new DecodeError(path, "integer");
  return n;
};

export const boolean: Reader<boolean> = (value, path = "") => {
  if (typeof value !== "boolean") throw new DecodeError(path, "boolean");
  return value;
};

/** ISO-8601 timestamp text, kept as text so exact server values survive. */
export const timestamp: Reader<string> = (value, path = "") => {
  const text = string(value, path);
  if (Number.isNaN(Date.parse(text))) throw new DecodeError(path, "ISO-8601 timestamp");
  return text;
};

export const literal =
  <const T extends string | number | boolean>(expected: T): Reader<T> =>
  (value, path = "") => {
    if (value !== expected) throw new DecodeError(path, JSON.stringify(expected));
    return expected;
  };

export const oneOf =
  <const T extends readonly string[]>(values: T): Reader<T[number]> =>
  (value, path = "") => {
    const found = values.find((candidate) => candidate === value);
    if (found === undefined) throw new DecodeError(path, `one of ${values.join("|")}`);
    return found;
  };

export const nullable =
  <T>(read: Reader<T>): Reader<T | null> =>
  (value, path = "") =>
    value === null ? null : read(value, path);

export const array =
  <T>(read: Reader<T>, max = 10_000): Reader<readonly T[]> =>
  (value, path = "") => {
    if (!Array.isArray(value)) throw new DecodeError(path, "array");
    if (value.length > max) throw new DecodeError(path, `at most ${max} items`);
    return value.map((item: unknown, index) => read(item, at(path, index)));
  };

type Shape = Readonly<Record<string, Reader<unknown>>>;
type FromShape<S extends Shape> = { readonly [K in keyof S]: Decoded<S[K]> };

/** Reads exactly the listed keys. A key absent from the input is passed to its reader as undefined. */
export function object<S extends Shape>(shape: S): Reader<FromShape<S>> {
  return (value, path = "") => {
    if (!isRecord(value)) throw new DecodeError(path, "object");
    const result: Record<string, unknown> = {};
    for (const [key, read] of Object.entries(shape)) result[key] = read(value[key], at(path, key));
    // Sound: every key of S was assigned from its own reader above.
    return result as FromShape<S>;
  };
}

/** Optional key: absent or undefined reads as undefined; null is not absence. */
export const optional =
  <T>(read: Reader<T>): Reader<T | undefined> =>
  (value, path = "") =>
    value === undefined ? undefined : read(value, path);

/** Discriminated union on `key`; each variant reader receives the whole object. */
export function variant<K extends string, M extends Readonly<Record<string, Reader<unknown>>>>(
  key: K,
  variants: M,
): Reader<Decoded<M[keyof M]>> {
  return (value, path = "") => {
    if (!isRecord(value)) throw new DecodeError(path, "object");
    const tag = value[key];
    const read =
      typeof tag === "string" && Object.hasOwn(variants, tag) ? variants[tag] : undefined;
    if (read === undefined)
      throw new DecodeError(at(path, key), `one of ${Object.keys(variants).join("|")}`);
    // Sound: read is one of M's readers, so its output is a member of the union.
    return read(value, path) as Decoded<M[keyof M]>;
  };
}

/** Decode at a boundary without throwing. */
export function decode<T>(
  read: Reader<T>,
  value: unknown,
): { ok: true; value: T } | { ok: false; error: DecodeError } {
  try {
    return { ok: true, value: read(value) };
  } catch (error) {
    if (error instanceof DecodeError) return { ok: false, error };
    throw error;
  }
}
