/** Small readers for host-owned envelopes. Feature payloads retain their own decoders. */
export type Reader<T> = (value: unknown) => T;
export const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
export function invalid(): never {
  throw new Error("Invalid host snapshot");
}
export const string: Reader<string> = (value) => (typeof value === "string" ? value : invalid());
export const boolean: Reader<boolean> = (value) => (typeof value === "boolean" ? value : invalid());
export const count: Reader<number> = (value) =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : invalid();
export const instant: Reader<string> = (value) =>
  typeof value === "string" && Number.isFinite(Date.parse(value)) ? value : invalid();
export const nullable =
  <T>(read: Reader<T>): Reader<T | null> =>
  (value) =>
    value === null ? null : read(value);
export const optional =
  <T>(read: Reader<T>): Reader<T | undefined> =>
  (value) =>
    value === undefined ? undefined : read(value);
export const array =
  <T>(read: Reader<T>): Reader<readonly T[]> =>
  (value) => {
    if (!Array.isArray(value)) return invalid();
    const entries: unknown[] = value;
    return entries.map(read);
  };
type Shape = Readonly<Record<string, Reader<unknown>>>;
type Output<S extends Shape> = { readonly [K in keyof S]: ReturnType<S[K]> };
export const object =
  <S extends Shape>(shape: S): Reader<Output<S>> =>
  (value) => {
    if (!record(value)) return invalid();
    // Every key is reconstructed by its own reader. Object.fromEntries loses that mapped-key relation.
    return Object.fromEntries(
      Object.entries(shape).map(([key, read]) => [key, read(value[key])]),
    ) as Output<S>;
  };
