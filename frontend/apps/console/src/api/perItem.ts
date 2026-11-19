import { DecodeError, type Reader } from "./decode.ts";
import { isRecord } from "./json.ts";

/**
 * U86: an item a list couldn't read, as its kind words and id were sent (never the payload), so
 * the team the operator tells can find it.
 */
export type Unshown = Readonly<{ kind: readonly string[]; id: string | null }>;
export type PerItem<T> = Readonly<{ items: readonly T[]; unshown: readonly Unshown[] }>;

type Raw = Readonly<Record<string, unknown>>;

/** A short identifier as sent, or null: only a string, and never more than a word's length. */
const word = (value: unknown): string | null =>
  typeof value === "string" && value.trim() !== "" ? value.trim().slice(0, 80) : null;

function describe(raw: unknown, kindOf: (raw: Raw) => readonly unknown[]): Unshown {
  if (!isRecord(raw)) return { kind: [], id: null };
  return {
    kind: kindOf(raw).flatMap((k) => word(k) ?? []),
    id: word(raw["id"]),
  };
}

export type PerItemOptions<T> = Readonly<{
  /** Names the list in console.warn: "Now's queue". */
  label: string;
  /** The raw kind words, in order (e.g. kind, then the attention's source). */
  kindOf: (raw: Raw) => readonly unknown[];
  /** Leaves out an item that reads but that this console has nothing to draw for. */
  shown?: (item: T) => boolean;
}>;

/**
 * A list read item by item (lead, U86): each item is read strictly, and one that doesn't fit is
 * left out and described instead of failing the whole list. The list itself stays strict.
 */
export const perItem =
  <T>(read: Reader<T>, max: number, o: PerItemOptions<T>): Reader<PerItem<T>> =>
  (value, path = "") => {
    if (!Array.isArray(value)) throw new DecodeError(path, "array");
    if (value.length > max) throw new DecodeError(path, `at most ${max} items`);
    const items: T[] = [];
    const unshown: Unshown[] = [];
    value.forEach((raw: unknown, index) => {
      let why: string;
      try {
        const item = read(raw, `${path}[${index}]`);
        if (!o.shown || o.shown(item)) return void items.push(item);
        why = "a kind this console doesn't know";
      } catch (e) {
        if (!(e instanceof DecodeError)) throw e;
        // The path and the expected type only: a DecodeError never carries the value.
        why = e.message;
      }
      const u = describe(raw, o.kindOf);
      unshown.push(u);
      console.warn(`${o.label}: an item isn't shown (${unshownLine(u)}): ${why}`);
    });
    return { items, unshown };
  };

/** ux U86: "attention, contact_start, 0193…", or "An item with no readable kind, 0193…". */
export function unshownLine(u: Unshown): string {
  const kind = u.kind.length ? u.kind.join(", ") : "An item with no readable kind";
  return u.id ? `${kind}, ${u.id}` : kind;
}

/** One item read as `perItem` reads each: unreadable gives no item and its description. */
export const oneItem =
  <T>(read: Reader<T>, o: PerItemOptions<T>): Reader<PerItem<T>> =>
  (value, path = "") =>
    perItem((v: unknown) => read(v, path), 1, o)([value], path);
