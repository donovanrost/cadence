import type { OpsConsolePresentation } from "./ops-console";

type JsonRecord = Record<string, unknown>;

const validationActions = new Set([
  "validate",
  "validate-template",
  "validate-settings",
  "validate-request",
]);

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
    case "alarms:filter":
    case "alarms:reset_filters":
      return reconcileAlarms(presentation, patch);
    case "timeline:apply_timeline_filters":
    case "timeline:clear_timeline_selection":
      return reconcileTimeline(presentation, patch);
    case "dashboard_directory:filter_dashboards":
      return reconcileDashboardDirectory(presentation, patch);
    case "contact_schedule:search":
      return reconcileContactSchedule(presentation, patch);
    default:
      throw new Error(`Phoenix returned an unsupported result for ${surfaceId}/${actionId}.`);
  }
}

function reconcileAlarms(
  presentation: OpsConsolePresentation,
  patch: JsonRecord,
): OpsConsolePresentation {
  const filters = requireRecord(patch.filters, "Phoenix returned invalid alarm filters.");
  const summary = requireRecord(patch.summary, "Phoenix returned an invalid alarm summary.");
  const alarms = requireArray(patch.alarms, "Phoenix returned invalid alarm rows.");
  const values = requireRecord(filters.values, "Phoenix returned invalid alarm filter values.");

  return withProps(presentation, {
    filters: { ...filters, values },
    summary,
    alarms,
  });
}

function reconcileTimeline(
  presentation: OpsConsolePresentation,
  patch: JsonRecord,
): OpsConsolePresentation {
  const timelinePresentation = requireRecord(
    patch.presentation,
    "Phoenix returned an invalid timeline presentation.",
  );
  const filters = requireRecord(
    timelinePresentation.filters,
    "Phoenix returned invalid timeline filters.",
  );
  const values = requireRecord(filters.values, "Phoenix returned invalid timeline filter values.");
  const events = requireArray(patch.timeline_events, "Phoenix returned invalid timeline events.");
  const currentPresentation = requireRecord(
    presentation.props.presentation,
    "The mounted timeline presentation is invalid.",
  );
  const currentFilters = requireRecord(
    currentPresentation.filters,
    "The mounted timeline filters are invalid.",
  );

  return withProps(presentation, {
    presentation: {
      ...currentPresentation,
      ...timelinePresentation,
      filters: { ...currentFilters, ...filters, values },
    },
    timeline_events: events,
  });
}

function reconcileDashboardDirectory(
  presentation: OpsConsolePresentation,
  patch: JsonRecord,
): OpsConsolePresentation {
  const filters = requireRecord(patch.filters, "Phoenix returned invalid dashboard filters.");
  const values = requireRecord(filters.values, "Phoenix returned invalid dashboard filter values.");
  const dashboards = requireArray(
    patch.dashboard_directory,
    "Phoenix returned invalid dashboard rows.",
  );

  return withProps(presentation, {
    filters: { ...filters, values },
    dashboard_directory: dashboards,
  });
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
