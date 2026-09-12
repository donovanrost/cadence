import type { DirectoryModel } from "./contracts";
import type { DirectoryPresentationProps, FilterValues } from "./presentation.contracts";
export function directoryHref(mission: string, filters: FilterValues, page = 1) {
  const search = new URLSearchParams({ ...filters, page: String(page) });
  return `/missions/${encodeURIComponent(mission)}/ops/dashboards?${search}`;
}
export function presentation(model: DirectoryModel, locked: boolean): DirectoryPresentationProps {
  const root = `/missions/${encodeURIComponent(model.mission_id)}/ops/dashboards`;
  const select = (key: string, label: string, options: { label: string; value: string }[]) => ({
    id: `directory_${key}`,
    name: `directory[${key}]`,
    type: "select" as const,
    label,
    options,
  });
  const action = (id: string, label: string, href: string, icon: string, classes: string) => ({
    id,
    label,
    href,
    icon,
    icon_class: "h-4 w-4",
    class: classes,
  });
  return {
    page: {
      id: "ops-dashboards-page",
      header: {
        eyebrow: "Observe / Dashboards",
        heading: "Dashboard Directory",
        copy: "Find mission telemetry workspaces without crowding the navigation rail. Stars and recents are personal; dashboard definitions and tags remain mission shared.",
        count: { id: "dashboard-directory-count", value: model.total, suffix: "matching" },
        author_actions: model.author
          ? [
              action(
                "dashboard-directory-new",
                "New Dashboard",
                root + "/new",
                "hero-plus",
                "btn btn-primary btn-sm",
              ),
              action(
                "dashboard-directory-import",
                "Import",
                root + "/new?mode=import",
                "hero-arrow-down-tray",
                "btn btn-outline btn-sm",
              ),
              action(
                "dashboard-directory-library",
                "Library",
                root + "/library",
                "hero-squares-plus",
                "btn btn-ghost btn-sm",
              ),
              action(
                "dashboard-directory-playlists",
                "Playlists",
                root + "/playlists",
                "hero-play",
                "btn btn-ghost btn-sm",
              ),
            ]
          : [],
      },
      list: {
        id: "dashboard-directory-list",
        empty: {
          id: "dashboard-directory-empty",
          icon: "hero-magnifying-glass",
          heading: "No matching dashboards",
          copy: "Change the search, tag, or lifecycle filter. The filter state is preserved in the URL.",
        },
      },
    },
    filters: {
      id: "dashboard-directory-filter-form",
      values: model.filters,
      fields: {
        query: {
          id: "directory_query",
          name: "directory[query]",
          type: "search",
          label: "Search",
          placeholder: "Name, description, or tag",
          debounce_ms: 250,
        },
        lifecycle: select(
          "lifecycle",
          "Lifecycle",
          ["active", "archived", "all"].map((value) => ({
            value,
            label: value.charAt(0).toUpperCase() + value.slice(1),
          })),
        ),
        tag: select("tag", "Tag", [
          { value: "all", label: "All tags" },
          ...model.available_tags
            .filter((value) => value !== "all")
            .map((value) => ({ value, label: value })),
        ]),
        sort: select("sort", "Sort", [
          { value: "updated", label: "Recently updated" },
          { value: "name", label: "Name" },
          { value: "widgets", label: "Widget count" },
        ]),
      },
    },
    dashboard_directory: model.rows.map((row) => {
      const label = row.starred ? "Unstar dashboard" : "Star dashboard";
      return {
        id: row.id,
        __dom_id: `dashboard-${row.id}`,
        dashboard_id: row.id,
        name: row.name,
        description: row.description,
        tags: row.tags,
        lifecycle: {
          state: row.lifecycle,
          class: row.lifecycle === "active" ? "badge badge-success" : "badge badge-ghost",
        },
        starred: row.starred,
        open:
          row.lifecycle === "active"
            ? {
                id: `open-${row.id}`,
                href:
                  root +
                  "/" +
                  encodeURIComponent(row.id) +
                  (row.published_version === null && model.author ? "/edit" : ""),
              }
            : null,
        star: {
          id: `star-${row.id}`,
          payload: { "dashboard-id": row.id, starred: String(!row.starred) },
          aria_label: label,
          aria_pressed: row.starred ? "true" : "false",
          disabled: locked || row.lifecycle !== "active",
          title: label,
          icon: row.starred ? "hero-star-solid" : "hero-star",
        },
        widget_version_label: `${row.widget_count} widgets · v${row.version}${row.published_version === null ? " · Unpublished" : ""}`,
        ...(model.author && row.lifecycle === "active"
          ? {
              clone: {
                id: `clone-${row.id}`,
                label: "Clone",
                icon: "hero-document-duplicate",
                href: root + "/new?mode=clone&source_dashboard_id=" + encodeURIComponent(row.id),
              },
            }
          : {}),
        restore:
          model.author && row.lifecycle === "archived"
            ? {
                id: `restore-${row.id}`,
                label: "Restore",
                icon: "hero-arrow-uturn-left",
                payload: { "dashboard-id": row.id, "expected-version": String(row.version) },
                disabled: locked,
                lifecycle_action: "restore",
                action_available: "true",
              }
            : null,
      };
    }),
  };
}
