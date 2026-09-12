import type { OpsFrameContext } from "./context-contract";
const tones = {
  critical: { badge: "bg-error/20 text-error", dot: "bg-error" },
  warning: { badge: "bg-warning/20 text-warning", dot: "bg-warning" },
  info: { badge: "bg-info/20 text-info", dot: "bg-info" },
  nominal: { badge: "bg-success/20 text-success", dot: "bg-success" },
};
const countClasses = { info: "text-info", warning: "text-warning", error: "text-error" };
export const utcLabel = (value: string | null | undefined) =>
  value ? `${new Date(value).toISOString().slice(11, 19)} UTC` : "not observed";
const badge = (severity: keyof typeof tones, count: number, label: string) => ({
  class: tones[severity].badge,
  count,
  label,
});
export function contextSections(context: OpsFrameContext) {
  const root = `/missions/${encodeURIComponent(context.mission.mission_id)}`;
  const focus = context.ops_context?.pinned_focus;
  return (context.ops_context?.modules || []).map((section) => {
    function presentation<C>(title: string, icon: string, path: string, content: C) {
      const destination =
        focus?.kind === "command" && focus.id
          ? `${path}?focus_command_id=${encodeURIComponent(focus.id)}`
          : path;
      return {
        ...section,
        title,
        icon,
        destination,
        content,
        status_dot_class:
          section.status !== null && Object.hasOwn(tones, section.status)
            ? toneDot(section.status)
            : "bg-base-content/30",
        freshness_label:
          section.freshness === "current"
            ? "Live"
            : section.freshness === "stale"
              ? "Stale"
              : section.freshness === "unavailable"
                ? "Unavailable"
                : "Unknown",
        observed_at_label: utcLabel(section.observed_at),
      };
    }
    if (section.key === "alarms") {
      const data = section.data;
      return presentation("Alarms", "hero-bell-alert", `${root}/ops/alarms`, {
        kind: "alarms" as const,
        active: (data?.active_count ?? 0) > 0,
        badges: [
          badge("critical", data?.critical_count || 0, "Critical"),
          badge("warning", data?.warning_count || 0, "Warning"),
          badge("info", data?.info_count || 0, "Info"),
        ],
        empty_label: "No active limit conditions",
        latest_transition_label: data?.latest_transition_at
          ? `Latest transition ${utcLabel(data?.latest_transition_at)}`
          : null,
      });
    } else if (section.key === "commands") {
      const data = section.data;
      return presentation("Commands", "hero-command-line", `${root}/ops/commands`, {
        kind: "commands" as const,
        counts: (
          [
            ["Queued", data?.queued_count || 0, "info"],
            ["Release pending", data?.release_pending_count || 0, "warning"],
            ["In flight", data?.in_flight_count || 0, "info"],
            ["Failed", (data?.failed_count || 0) + (data?.indeterminate_count || 0), "error"],
          ] as const
        ).map(([label, value, tone]) => ({
          label,
          value,
          class: value ? countClasses[tone] : "text-base-content/35",
        })),
        followed_command: data?.followed_command
          ? {
              ...data.followed_command,
              detail: `${data?.followed_command.status} · ${data?.followed_command.target}`,
            }
          : null,
      });
    } else if (section.key === "fleet_health") {
      const data = section.data;
      const counts = data?.normalized_state_counts;
      return presentation("Fleet health", "hero-rocket-launch", root, {
        kind: "fleet_health" as const,
        available: !!counts,
        badges: counts
          ? [
              badge("critical", counts.red, "Red"),
              badge("warning", counts.yellow, "Yellow"),
              badge("info", counts.blue, "Blue"),
              badge("nominal", counts.green, "Green"),
            ]
          : [],
        violating_points_label: counts ? `${data?.violating_points} violating points` : null,
        unavailable_label: "Fleet health unavailable.",
      });
    }
    return unreachable(section);
  });
}
export const contextRail = {
  id: "ops-context-rail",
  aria_label: "Operational context",
  storage_key: "cadence-ops-context-rail",
  role: "context",
  default_expanded: false,
  resize_title: "Drag to resize",
  toggle_label: "Toggle context panel",
};

function toneDot(tone: string): string {
  switch (tone) {
    case "critical":
      return tones.critical.dot;
    case "warning":
      return tones.warning.dot;
    case "info":
      return tones.info.dot;
    case "nominal":
      return tones.nominal.dot;
    default:
      return "bg-base-content/30";
  }
}
function unreachable(value: never): never {
  throw new Error(`Unknown context section: ${String(value)}`);
}
