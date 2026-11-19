/** A plain JSON object (not null, not an array). Ported from `@cadence/plugin-sdk/admission`. */
export const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
