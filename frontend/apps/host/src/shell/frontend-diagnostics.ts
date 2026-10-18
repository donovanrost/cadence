export type FrontendFailureKind = "admission" | "render" | "retry" | "load";
export type FrontendDiagnosticContext = {
  boundary: string;
  contributionId: string;
  version?: number;
  organizationId?: string;
  missionId?: string;
  spacecraftId?: string;
  resourceId?: string;
  releaseId?: string;
};
export type FrontendDiagnostic = FrontendDiagnosticContext & {
  id: string;
  kind: FrontendFailureKind;
  errorType: string;
  timestamp: string;
};
// Retain the cause for local inspection without copying error messages, payloads or credentials
// into diagnostic events. The bounded buffer belongs to the current document only.
const failures = new Map<string, { diagnostic: FrontendDiagnostic; cause: unknown }>();
export function readFrontendDiagnostic(id: string) {
  return failures.get(id);
}
export function reportFrontendFailure(
  context: FrontendDiagnosticContext,
  kind: FrontendFailureKind,
  cause: unknown,
): FrontendDiagnostic {
  const identifier = (value: unknown) =>
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 255 &&
    !/[^a-zA-Z0-9_.:-]/.test(value)
      ? value
      : undefined;
  const safe: FrontendDiagnosticContext = {
    boundary: identifier(context.boundary) ?? "unknown",
    contributionId: identifier(context.contributionId) ?? "unknown",
  };
  for (const key of [
    "organizationId",
    "missionId",
    "spacecraftId",
    "resourceId",
    "releaseId",
  ] as const) {
    const value = identifier(context[key]);
    if (value) safe[key] = value;
  }
  if (Number.isInteger(context.version) && context.version !== undefined && context.version > 0)
    safe.version = context.version;
  const diagnostic = {
    ...safe,
    id: crypto.randomUUID(),
    kind,
    timestamp: new Date().toISOString(),
    errorType:
      cause instanceof TypeError
        ? "TypeError"
        : cause instanceof SyntaxError
          ? "SyntaxError"
          : cause instanceof RangeError
            ? "RangeError"
            : "Error",
  };
  failures.set(diagnostic.id, { diagnostic, cause });
  if (failures.size > 50) {
    const first = failures.keys().next();
    if (!first.done) failures.delete(first.value);
  }
  console.error(`[Cadence frontend failure] ${diagnostic.id}`, diagnostic);
  return diagnostic;
}
