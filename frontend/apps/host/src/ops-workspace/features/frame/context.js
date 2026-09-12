const tones = {
  critical: { badge: "bg-error/20 text-error", dot: "bg-error" },
  warning: { badge: "bg-warning/20 text-warning", dot: "bg-warning" },
  info: { badge: "bg-info/20 text-info", dot: "bg-info" },
  nominal: { badge: "bg-success/20 text-success", dot: "bg-success" },
};
const countClasses = { info: "text-info", warning: "text-warning", error: "text-error" };
export const utcLabel = (value) =>
  value ? `${new Date(value).toISOString().slice(11, 19)} UTC` : "not observed";
const badge = (severity, count, label) => ({
  class: tones[severity].badge,
  count,
  label,
});
export function contextSections(context) {
  const root = `/missions/${encodeURIComponent(context.mission.mission_id)}`;
  const focus = context.ops_context?.pinned_focus;
  return (context.ops_context?.modules || []).map((section) => {
    const data = section.data || {};
    let content = { kind: "empty" };
    let title, icon, destination;
    if (section.key === "alarms") {
      title = "Alarms";
      icon = "hero-bell-alert";
      destination = `${root}/ops/alarms`;
      content = {
        kind: "alarms",
        active: data.active_count > 0,
        badges: [
          badge("critical", data.critical_count || 0, "Critical"),
          badge("warning", data.warning_count || 0, "Warning"),
          badge("info", data.info_count || 0, "Info"),
        ],
        empty_label: "No active limit conditions",
        latest_transition_label: data.latest_transition_at
          ? `Latest transition ${utcLabel(data.latest_transition_at)}`
          : null,
      };
    } else if (section.key === "commands") {
      title = "Commands";
      icon = "hero-command-line";
      destination = `${root}/ops/commands`;
      content = {
        kind: "commands",
        counts: [
          ["Queued", data.queued_count || 0, "info"],
          ["Release pending", data.release_pending_count || 0, "warning"],
          ["In flight", data.in_flight_count || 0, "info"],
          ["Failed", (data.failed_count || 0) + (data.indeterminate_count || 0), "error"],
        ].map(([label, value, tone]) => ({
          label,
          value,
          class: value ? countClasses[tone] : "text-base-content/35",
        })),
        followed_command: data.followed_command
          ? {
              ...data.followed_command,
              detail: `${data.followed_command.status} · ${data.followed_command.target}`,
            }
          : null,
      };
    } else if (section.key === "fleet_health") {
      title = "Fleet health";
      icon = "hero-rocket-launch";
      destination = root;
      const counts = data.normalized_state_counts;
      content = {
        kind: "fleet_health",
        available: !!counts,
        badges: counts
          ? [
              badge("critical", counts.red, "Red"),
              badge("warning", counts.yellow, "Yellow"),
              badge("info", counts.blue, "Blue"),
              badge("nominal", counts.green, "Green"),
            ]
          : [],
        violating_points_label: counts ? `${data.violating_points} violating points` : null,
        unavailable_label: "Fleet health unavailable.",
      };
    }
    if (focus?.kind === "command" && focus.id)
      destination += `?focus_command_id=${encodeURIComponent(focus.id)}`;
    return {
      ...section,
      title,
      icon,
      destination,
      content,
      status_dot_class: tones[section.status]?.dot || "bg-base-content/30",
      freshness_label:
        { current: "Live", stale: "Stale", unavailable: "Unavailable" }[section.freshness] ||
        "Unknown",
      observed_at_label: utcLabel(section.observed_at),
    };
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
