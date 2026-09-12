export function identity(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    new TextEncoder().encode(value).length <= 256 &&
    // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
    !/[\u0000-\u001f\u007f\ud800-\udfff]/u.test(value)
  );
}

export function queryText(
  value: unknown,
  allowed: readonly string[],
): Record<string, string> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const entries = Object.entries(value);
  if (entries.some(([key, text]) => !allowed.includes(key) || !identity(text))) return null;
  return Object.fromEntries(entries);
}

export function pathIdentity(value: unknown): value is string {
  return identity(value) && value !== "." && value !== "..";
}

export function destination(
  mission: unknown,
  suffix: string,
  query: Record<string, string>,
): string | null {
  if (!pathIdentity(mission)) return null;
  const search = new URLSearchParams(query);
  return `/missions/${encodeURIComponent(mission)}/ops/dashboards/${suffix}${search.size ? `?${search}` : ""}`;
}
