let next = 0;
/** Stable-per-instance DOM id for label/description wiring. */
export function fieldId(prefix: string): string {
  next += 1;
  return `${prefix}-${next}`;
}
