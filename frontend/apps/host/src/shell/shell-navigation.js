export const navigateAttrs = (href) => ({
  href,
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
});
export const canAdminister = (context) =>
  context.capabilities.some((capability) =>
    ["organization_admin", "platform_admin"].includes(capability),
  );
export function navigation(context, mission) {
  const item = (key, label, href, icon, id) => ({
    key,
    label,
    href,
    icon,
    id,
    active: context.nav_item === key,
  });
  if (!mission) {
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
  const section = (key, label, icon, children) => ({
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
export function opsNavigation(context) {
  const root = `/missions/${encodeURIComponent(context.mission.mission_id)}/ops`;
  const focus = context.ops_context?.pinned_focus;
  const href = (path) =>
    `${root}/${path}${focus?.kind === "command" && focus.id ? `?focus_command_id=${encodeURIComponent(focus.id)}` : ""}`;
  const item = (key, label, icon, path = key.replaceAll("_", "-")) => ({
    key,
    label,
    icon,
    href: href(path),
    active: context.ops_nav_item === key,
  });
  const groups = [
    [
      "observe",
      "Observe",
      [
        item("dashboards", "Dashboards", "hero-squares-2x2"),
        item("explore", "Explore", "hero-magnifying-glass"),
        item("alarms", "Alarms", "hero-bell-alert"),
        item("timeline", "Timeline", "hero-clock"),
      ],
    ],
    [
      "act",
      "Act",
      [
        item("commands", "Commands", "hero-command-line"),
        ...(canAdminister(context) ? [item("activations", "Approvals", "hero-shield-check")] : []),
      ],
    ],
    [
      "plan",
      "Plan",
      [
        item("planning", "Planning", "hero-chart-bar-square"),
        item("requirements", "Requirements", "hero-clipboard-document-list"),
        item("contacts", "Contacts", "hero-calendar-days"),
      ],
    ],
    [
      "system",
      "System",
      [
        item("data_sources", "Data Sources", "hero-circle-stack"),
        item("data_operations", "Data Operations", "hero-arrow-path-rounded-square"),
      ],
    ],
  ].map(([key, label, items], index) => ({
    key,
    label,
    items,
    class: `${index ? "mt-3 border-t border-primary/20 " : ""}px-2 pt-2 space-y-0.5`,
  }));
  const dashboard_groups = [
    ["starred", "Starred", "hero-star-solid"],
    ["recent", "Recent", "hero-clock"],
  ]
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
