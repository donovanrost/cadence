import type { readNavigationContext } from "./contracts";
export function navigation(
  context: NonNullable<ReturnType<typeof readNavigationContext>>,
  mission: boolean,
) {
  const item = (key: string, label: string, href: string, icon?: string, id?: string) => ({
    kind: "link" as const,
    key,
    label,
    href,
    icon,
    id,
    active: context.nav_item === key,
  });
  if (!mission || !context.mission) {
    return [
      item("organization_home", "Home", "/", "hero-home"),
      item("missions", "Missions", "/missions", "hero-rocket-launch"),
    ];
  }
  const root = `/missions/${encodeURIComponent(context.mission.mission_id)}`;
  const section = (
    key: string,
    label: string,
    icon: string,
    children: ReturnType<typeof item>[],
  ) => ({
    kind: "group" as const,
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
  ];
}
