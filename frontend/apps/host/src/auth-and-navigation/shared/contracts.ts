export function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
export function text(value: unknown, max = 4096): value is string {
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  return typeof value === "string" && value.length <= max && !/[\u0000-\u001f\u007f]/u.test(value);
}
export function present(value: unknown, max = 4096): value is string {
  return text(value, max) && value.trim().length > 0;
}
export function count(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) >= 0;
}
export function sessionPage(
  value: unknown,
): value is Record<string, unknown> & { version: 1; csrf_token: string } {
  return record(value) && value.version === 1 && present(value.csrf_token);
}
