/** Untrusted producer documents retain unknown fields until the feature reader admits them. */
export function fixtureRecord(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value))
    throw new Error("Expected a fixture object");
  return value as Record<string, unknown>;
}

export function jsonFixture(source: string): Record<string, unknown> {
  return fixtureRecord(JSON.parse(source));
}

export function fixtureString(value: unknown): string {
  if (typeof value !== "string") throw Error("Expected a fixture string");
  return value;
}

export function fixtureRows(source: string | undefined): Record<string, unknown>[] {
  if (source === undefined) throw Error("Missing producer fixture argument");
  const value: unknown = JSON.parse(source);
  if (!Array.isArray(value)) throw Error("Expected a fixture array");
  return value.map(fixtureRecord);
}
export function fixtureValue(node: object | null | undefined): string {
  if (!node || !("value" in node) || typeof node.value !== "string")
    throw Error("Expected a fixture form value");
  return node.value;
}
export function fixtureDisabled(node: object | null | undefined): boolean {
  if (!node || !("disabled" in node) || typeof node.disabled !== "boolean")
    throw Error("Expected a fixture control");
  return node.disabled;
}
export function fixtureNumber(value: unknown): number {
  if (typeof value !== "number") throw Error("Expected a fixture number");
  return value;
}
export function fixtureContext(value: unknown): {
  organizationId: string;
  missionId: string;
  resourceId?: string;
} {
  const context = fixtureRecord(value);
  return {
    organizationId: fixtureString(context.organizationId),
    missionId: fixtureString(context.missionId),
    ...(context.resourceId === undefined ? {} : { resourceId: fixtureString(context.resourceId) }),
  };
}

/** Negative tests navigate owned raw documents without claiming a valid domain model. */
export function fixtureAt(value: unknown, ...path: readonly (string | number)[]): unknown {
  let current = value;
  for (const key of path) {
    if (typeof key === "number") {
      const array = fixtureArrayAt(current);
      if (!Object.hasOwn(array, key)) throw Error("Missing fixture array entry");
      current = array[key];
    } else {
      const record = fixtureRecord(current);
      if (!Object.hasOwn(record, key)) throw Error("Missing fixture object field");
      current = record[key];
    }
  }
  return current;
}
export function fixtureRecordAt(
  value: unknown,
  ...path: readonly (string | number)[]
): Record<string, unknown> {
  return fixtureRecord(fixtureAt(value, ...path));
}
export function fixtureArrayAt(value: unknown, ...path: readonly (string | number)[]): unknown[] {
  const array = fixtureAt(value, ...path);
  if (!Array.isArray(array)) throw Error("Expected a fixture array");
  return array;
}
