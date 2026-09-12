/** Read a literal choice from a transport value without asserting its type first. */
export function oneOf<const T extends readonly unknown[]>(
  choices: T,
  value: unknown,
): value is T[number] {
  const candidates: readonly unknown[] = choices;
  return candidates.includes(value);
}

export type Guard<T> = (value: unknown) => value is T;
export function arrayOf<T>(value: unknown, admit: Guard<T>): value is T[] {
  return Array.isArray(value) && value.every((entry: unknown) => admit(entry));
}

/** Admitted server values are snapshots; forms copy the values they own. */
export type Snapshot<T> = T extends object ? { readonly [K in keyof T]: Snapshot<T[K]> } : T;

export const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
