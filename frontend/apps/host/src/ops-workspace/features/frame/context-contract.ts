import {
  array,
  boolean,
  count,
  instant,
  invalid,
  nullable,
  object,
  optional,
  record,
  string,
} from "../../../shell/snapshot-readers";
const maybe = <T>(read: (value: unknown) => T) => optional(nullable(read));
const counts = object({ red: count, yellow: count, blue: count, green: count });
const alarmData = nullable(
  object({
    active_count: optional(count),
    critical_count: optional(count),
    warning_count: optional(count),
    info_count: optional(count),
    latest_transition_at: maybe(instant),
  }),
);
const commandData = nullable(
  object({
    queued_count: optional(count),
    release_pending_count: optional(count),
    in_flight_count: optional(count),
    failed_count: optional(count),
    indeterminate_count: optional(count),
    followed_command: maybe(
      object({
        command_request_id: string,
        command_name: string,
        status: string,
        target: string,
        target_name: nullable(string),
      }),
    ),
  }),
);
const healthData = nullable(
  object({ normalized_state_counts: maybe(counts), violating_points: optional(count) }),
);
const sectionMetadata = object({
  status: nullable(string),
  count: nullable(count),
  freshness: string,
  observed_at: nullable(instant),
});
function section(value: unknown) {
  if (!record(value)) return invalid();
  const metadata = sectionMetadata(value);
  switch (value.key) {
    case "alarms":
      return { ...metadata, key: "alarms" as const, data: alarmData(value.data) };
    case "commands":
      return { ...metadata, key: "commands" as const, data: commandData(value.data) };
    case "fleet_health":
      return { ...metadata, key: "fleet_health" as const, data: healthData(value.data) };
    default:
      return invalid();
  }
}
const dashboard = object({ dashboard_id: string, name: string });
const read = object({
  mission: object({ mission_id: string, display_name: string, slug: string }),
  capabilities: array(string),
  ops_nav_item: optional(string),
  active_dashboard_id: maybe(string),
  dashboard_author: optional(boolean),
  dashboard_navigation: optional(object({ starred: array(dashboard), recent: array(dashboard) })),
  fleet_health: maybe(object({ normalized_state_counts: maybe(counts) })),
  dock_surfaces: array(
    object({ id: string, application_key: string, surface_id: string, label: string }),
  ),
  ops_context: maybe(
    object({
      pinned_focus: maybe(object({ kind: string, id: string })),
      modules: optional(array(section)),
    }),
  ),
});
export type OpsFrameContext = ReturnType<typeof read>;
export function readOpsFrameContext(value: unknown): OpsFrameContext | null {
  try {
    return read(value);
  } catch {
    return null;
  }
}
