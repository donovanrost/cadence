export type Reader<T> = (value: unknown) => T;
export function invalid(): never {
  throw new Error("Invalid spacecraft configuration response.");
}
export function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return invalid();
  // All objects are indexed only as unknown values at this boundary.
  return value as Record<string, unknown>;
}
export const text: Reader<string> = (value) =>
  typeof value === "string" && value.length <= 4096 ? value : invalid();
export const id: Reader<string> = (value) => {
  const result = text(value);
  return /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,254}$/.test(result) ? result : invalid();
};
export const bool: Reader<boolean> = (value) => (typeof value === "boolean" ? value : invalid());
export const count: Reader<number> = (value) =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : invalid();
export const nullable =
  <T>(read: Reader<T>): Reader<T | null> =>
  (value) =>
    value === null ? null : read(value);
export const oneOf =
  <const T extends readonly (string | number)[]>(values: T): Reader<T[number]> =>
  (value) => {
    for (const choice of values) if (choice === value) return choice;
    return invalid();
  };
export const array =
  <T>(read: Reader<T>, max = 100): Reader<readonly T[]> =>
  (value) => {
    if (!Array.isArray(value) || value.length > max) return invalid();
    const items: unknown[] = value;
    return items.map(read);
  };
type Shape = Readonly<Record<string, Reader<unknown>>>;
type Output<S extends Shape> = { readonly [K in keyof S]: ReturnType<S[K]> };
export const object =
  <S extends Shape>(shape: S): Reader<Output<S>> =>
  (value) => {
    const input = record(value);
    // Each declared key is reconstructed with its reader; fromEntries erases that relation.
    return Object.fromEntries(
      Object.entries(shape).map(([key, read]) => [key, read(input[key])]),
    ) as Output<S>;
  };
