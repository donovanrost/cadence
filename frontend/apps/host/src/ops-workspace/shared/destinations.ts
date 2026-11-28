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
      ["observe", "Observe", [item("dashboards", "Dashboards", "hero-squares-2x2")]],
      ["act", "Act", [item("commands", "Commands", "hero-command-line")]],
      ["system", "System", [item("data_sources", "Data Sources", "hero-circle-stack")]],
    ] satisfies [string, string, WorkspaceDestination[]][]
  ).map(([key, label, items], index) => ({
    key,
    label,
    items,
    class: `${index ? "mt-3 border-t border-primary/20 " : ""}px-2 pt-2 space-y-0.5`,
  }));
}
