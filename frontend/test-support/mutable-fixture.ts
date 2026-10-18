/** Tests build independent mutable fixtures, then pass them through production readers. */
export type MutableFixture<T> = T extends object
  ? { -readonly [K in keyof T]: MutableFixture<T[K]> }
  : T;

/** A new structured clone belongs to the test, so removing readonly cannot mutate its source. */
export function mutableFixture<T>(value: T): MutableFixture<T> {
  return structuredClone(value) as MutableFixture<T>;
}
