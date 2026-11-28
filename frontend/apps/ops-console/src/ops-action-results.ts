import type { OpsConsolePresentation } from "./ops-console";

type JsonRecord = Record<string, unknown>;

const validationActions = new Set(["validate", "validate-template"]);

export function reconcileOpsActionResult(
  presentation: OpsConsolePresentation,
  surfaceId: string,
  actionId: string,
  result: unknown,
): OpsConsolePresentation {
  if (validationActions.has(actionId)) {
    if (!isRecord(result)) throw new Error("Phoenix returned an invalid validation result.");
    return presentation;
  }

  const envelope = requireRecord(result, "Phoenix returned an invalid action result.");
  if (envelope.surfaceId !== surfaceId || envelope.actionId !== actionId) {
    throw new Error("Phoenix returned a cross-surface action result.");
  }

  const patch = requireRecord(envelope.props, "Phoenix returned an invalid presentation patch.");

  switch (`${surfaceId}:${actionId}`) {
    case "contact_schedule:search":
      return reconcileContactSchedule(presentation, patch);
    default:
      throw new Error(`Phoenix returned an unsupported result for ${surfaceId}/${actionId}.`);
  }
}

function reconcileContactSchedule(
  presentation: OpsConsolePresentation,
  patch: JsonRecord,
): OpsConsolePresentation {
  const search = requireRecord(patch.search, "Phoenix returned invalid contact search state.");
  const values = requireRecord(search.values, "Phoenix returned invalid contact search values.");
  const opportunities = requireArray(
    patch.opportunities,
    "Phoenix returned invalid contact opportunities.",
  );

  return withProps(presentation, {
    search: { ...search, values },
    opportunities,
  });
}

function withProps(
  presentation: OpsConsolePresentation,
  patch: JsonRecord,
): OpsConsolePresentation {
  return {
    ...presentation,
    props: { ...presentation.props, ...patch },
  };
}

function requireRecord(value: unknown, message: string): JsonRecord {
  if (!isRecord(value)) throw new Error(message);
  return value;
}

function requireArray(value: unknown, message: string): unknown[] {
  if (!Array.isArray(value)) throw new Error(message);
  return value;
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
