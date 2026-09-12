type DefinedProperties<T> = T extends object
  ? { [K in keyof T as undefined extends T[K] ? never : K]: T[K] } & {
      [K in keyof T as undefined extends T[K] ? K : never]?: Exclude<T[K], undefined>;
    }
  : never;

/** Vue resolves omitted props to undefined; snapshot contracts represent absence by omission. */
export function definedProperties<T extends object>(value: T): DefinedProperties<T> {
  // Every retained key keeps its original value. Only undefined properties are omitted.
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  ) as DefinedProperties<T>;
}
