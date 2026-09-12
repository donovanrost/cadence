export type WorkspaceDestination = {
  key: string;
  label: string;
  icon: string;
  href: string;
  active: boolean;
};
export type WorkspaceGroup = {
  key: string;
  label: string;
  items: WorkspaceDestination[];
  class: string;
};

export function workspaceGroups(
  href: (path: string) => string,
  canAdminister: boolean,
  activeKey?: string,
): WorkspaceGroup[] {
  const item = (key: string, label: string, icon: string, path = key.replaceAll("_", "-")) => ({
    key,
    label,
    icon,
    href: href(path),
    active: activeKey === key,
  });
  return (
    [
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
          ...(canAdminister ? [item("activations", "Approvals", "hero-shield-check")] : []),
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
    ] satisfies [string, string, WorkspaceDestination[]][]
  ).map(([key, label, items], index) => ({
    key,
    label,
    items,
    class: `${index ? "mt-3 border-t border-primary/20 " : ""}px-2 pt-2 space-y-0.5`,
  }));
}
