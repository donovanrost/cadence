/** A mounted native contract must fail clearly when a required node or fixture is absent. */
export function required<T>(
  value: T | null | undefined,
  message = "Expected a required test value",
): T {
  if (value === null || value === undefined) throw new Error(message);
  return value;
}
