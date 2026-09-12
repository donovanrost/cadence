import { workspaceGroups } from "../../shared/destinations";
import { canAdminister } from "../../../auth-and-navigation";
import type { OpsFrameContext } from "./context-contract";
type OpsNavigationContext = {
  mission: { mission_id: string };
  capabilities: readonly string[];
} & Partial<
  Pick<
    OpsFrameContext,
    | "ops_context"
    | "ops_nav_item"
    | "dashboard_navigation"
    | "active_dashboard_id"
    | "dashboard_author"
  >
>;
export function opsNavigation(context: OpsNavigationContext) {
  const root = `/missions/${encodeURIComponent(context.mission.mission_id)}/ops`;
  const focus = context.ops_context?.pinned_focus;
  const href = (path: string) =>
    `${root}/${path}${focus?.kind === "command" && focus.id ? `?focus_command_id=${encodeURIComponent(focus.id)}` : ""}`;
  const groups = workspaceGroups(href, canAdminister(context), context.ops_nav_item);
  const dashboard_groups = (
    [
      ["starred", "Starred", "hero-star-solid"],
      ["recent", "Recent", "hero-clock"],
    ] as const
  )
    .map(([key, label, icon]) => ({
      key,
      label,
      icon,
      items: (context.dashboard_navigation?.[key] || []).map((dashboard) => ({
        dashboard_id: dashboard.dashboard_id,
        label: dashboard.name,
        href: href(`dashboards/${encodeURIComponent(dashboard.dashboard_id)}`),
        active: context.active_dashboard_id === dashboard.dashboard_id,
      })),
    }))
    .filter((group) => group.items.length);
  return {
    groups,
    dashboard_groups,
    empty_state: dashboard_groups.length ? null : "Star dashboards or open one to keep it close.",
    new_dashboard: context.dashboard_author
      ? {
          label: "New Dashboard",
          title: "New dashboard",
          icon: "hero-plus",
          href: href("dashboards/new"),
        }
      : null,
  };
}
