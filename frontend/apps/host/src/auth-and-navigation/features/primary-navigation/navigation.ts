import type { readNavigationContext } from "./contracts";
import { canAdminister } from "../../shared/navigation";
export function navigation(
  context: NonNullable<ReturnType<typeof readNavigationContext>>,
  mission: boolean,
) {
  const item = (key: string, label: string, href: string, icon?: string, id?: string) => ({
    key,
    label,
    href,
    icon,
    id,
    active: context.nav_item === key,
  });
  if (!mission || !context.mission) {
    if (context.nav_context === "admin")
      return [
        item("admin_dashboard", "Dashboard", "/admin", "hero-chart-bar-square"),
        item(
          "admin_organizations",
          "Organizations",
          "/admin/organizations",
          "hero-building-office",
        ),
        item("admin_runtime", "Runtime", "/admin/runtime", "hero-signal"),
      ];
    return [
      item("organization_home", "Home", "/", "hero-home"),
      item("missions", "Missions", "/missions", "hero-rocket-launch"),
      ...(canAdminister(context)
        ? [
            item(
              "provider_accounts",
              "Provider Accounts",
              "/provider-accounts",
              "hero-globe-alt",
              "provider-accounts-nav-link",
            ),
          ]
        : []),
    ];
  }
  const root = `/missions/${encodeURIComponent(context.mission.mission_id)}`;
  const section = (
    key: string,
    label: string,
    icon: string,
    children: ReturnType<typeof item>[],
  ) => ({
    key,
    label,
    icon,
    children,
    active: children.some((child) => child.active),
  });
  return [
    item("mission_overview", "Overview", root, "hero-chart-bar-square"),
    item("spacecraft", "Spacecraft", `${root}/spacecraft`, "hero-rocket-launch"),
    item("mission_applications", "Applications", `${root}/applications`, "hero-squares-2x2"),
    item("catalog", "Catalog", `${root}/catalog`, "hero-circle-stack"),
    section("ops", "Ops", "hero-presentation-chart-line", [
      item("ops_dashboards", "Dashboards", `${root}/ops/dashboards`),
    ]),
    section(
      "comms",
      "Comms",
      "hero-signal",
      [
        ["overview", "Overview", ""],
        ["transports", "Transports", "/transports"],
        ["ground_stations", "Ground Stations", "/ground-stations"],
        ["routing", "Routing", "/routing"],
        ["validation", "Validation", "/validation"],
      ].map(([key, label, path]) => item(`comms_${key}`, label, `${root}/comms${path}`)),
    ),
  ];
}
