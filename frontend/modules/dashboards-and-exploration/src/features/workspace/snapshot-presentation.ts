import type DashboardWidget from "./DashboardWidget.vue";
import type { WorkspacePlacement, WorkspaceSnapshot } from "./contracts";
import { muted, snapshotWidgetBody } from "./snapshot-widgets.ts";

type Header = InstanceType<typeof DashboardWidget>["$props"]["presentation"]["header"];
// Length-framed UTF-8 hex keeps arbitrary domain IDs out of CSS selectors and
// separates a section ID from an equal placement ID without lossy slugging.
export function workspaceDomId(instance: string, ...parts: string[]): string {
  return [
    instance,
    ...parts.map((part) => {
      const bytes = new TextEncoder().encode(part);
      return `${bytes.length}_${Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
    }),
  ].join("-");
}
function header(placement: WorkspacePlacement, id: string): Header {
  const title = placement.widget?.title || placement.authored_id;
  return {
    component_id: `${id}-header`,
    root: {
      class: "flex items-center justify-between gap-2 border-b border-base-300/50 px-3 py-2",
      attrs: {},
    },
    title: { class: "min-w-0 truncate text-xs font-medium", text: title },
    status_indicators: {
      class: "flex gap-1",
      attrs: {},
      limit: null,
      comparison: null,
      quality: null,
      lifecycle: null,
    },
    actions: {
      class: "flex items-center",
      edit: [],
      details: {
        overlay: { id: `${id}-details`, class: "", attrs: {} },
        trigger: {
          id: `${id}-details-trigger`,
          type: "button",
          class: "btn btn-ghost btn-xs",
          attrs: { "aria-label": `Details for ${title}` },
          content: {
            class: "flex",
            attrs: {},
            icon: { name: "hero-information-circle", class: "h-4 w-4" },
          },
        },
        panel: {
          id: `${id}-details-panel`,
          class: "w-72 border border-base-300 bg-base-200 p-3 shadow-xl",
          hidden: true,
          attrs: {},
        },
        body: {
          class: "space-y-2",
          heading: {
            class: "space-y-1",
            title: { class: "text-sm font-medium", text: title },
            binding: {
              class: `${muted} break-all`,
              text: `${placement.widget?.type ?? "Unavailable widget"} · ${placement.authored_id}`,
            },
          },
          indicators: {
            class: "",
            attrs: {},
            lifecycle: null,
            source: null,
            data_management: [],
            warnings: [],
          },
          actions: {
            class: "hidden",
            attrs: {},
            query: null,
            frame_evidence: null,
            data_links: null,
            inspector: null,
          },
        },
      },
    },
  };
}

/** Module-local presentation; no browser-selected imports, attributes or actions. */
export function snapshotPresentation(snapshot: WorkspaceSnapshot, instance: string) {
  if (!/^[a-zA-Z][a-zA-Z0-9_-]{0,127}$/.test(instance)) throw Error("Invalid workspace instance");
  const rootId = workspaceDomId(
    instance,
    snapshot.organization_id,
    snapshot.mission_id,
    snapshot.dashboard_id,
  );
  const groups = [
    ...snapshot.sections.map((section) => ({
      section,
      placements: snapshot.placements.filter((p) => p.section_id === section.id),
    })),
    ...(snapshot.placements.some((p) => p.section_id === null)
      ? [{ section: null, placements: snapshot.placements.filter((p) => p.section_id === null) }]
      : []),
  ];
  return {
    root: { attrs: { id: rootId, "data-workspace-snapshot": snapshot.dashboard_id } },
    content: { attrs: { class: "space-y-4" } },
    groups: groups.map(({ section, placements }) => {
      const groupId = section
        ? workspaceDomId(rootId, "section", section.id)
        : workspaceDomId(rootId, "unsectioned");
      const gridId = `${groupId}-grid`;
      return {
        key: JSON.stringify([section?.id ?? null]),
        root: { attrs: { id: groupId } },
        header: null,
        section: section
          ? {
              root: {
                attrs: { id: `${groupId}-disclosure`, ...(!section.collapsed ? { open: "" } : {}) },
              },
              summary: {
                attrs: {
                  id: `${groupId}-trigger`,
                  class: "flex w-full items-center gap-2 py-3 text-left",
                },
                icon: { attrs: { class: "hero-chevron-down h-4 w-4 text-base-content/50" } },
                copy: {
                  attrs: { class: "min-w-0 flex-1" },
                  title: { attrs: { class: "text-sm font-semibold" }, text: section.title },
                  description: section.description
                    ? { attrs: { class: muted }, text: section.description }
                    : null,
                },
                count: {
                  attrs: { class: muted },
                  text: `${placements.length} ${placements.length === 1 ? "widget" : "widgets"}`,
                },
              },
            }
          : null,
        grid: {
          root: { attrs: { id: gridId, class: "grid-stack" } },
          widgets: placements.map((placement) => {
            const id = workspaceDomId(rootId, "placement", placement.id);
            const layout = placement.layout;
            return {
              key: placement.id,
              shell: {
                attrs: {
                  id,
                  class: "grid-stack-item",
                  "gs-id": placement.id,
                  ...(layout.x === null ? {} : { "gs-x": String(layout.x) }),
                  ...(layout.y === null ? {} : { "gs-y": String(layout.y) }),
                  "gs-w": String(layout.w),
                  "gs-h": String(layout.h),
                },
              },
              content: {
                attrs: {
                  class: "grid-stack-item-content rounded border border-base-300/60 bg-base-200/50",
                },
              },
              host: { attrs: { id: `${id}-host`, class: "flex h-full min-h-0 flex-col" } },
              presentation: {
                component_id: `${id}-component`,
                header: header(placement, id),
                body: snapshotWidgetBody(placement, snapshot, id, rootId),
              },
            };
          }),
          controller: {
            host: { attrs: { id: `${gridId}-controller` } },
            props: {
              target_id: gridId,
              item_ids: placements.map((p) => p.id),
              edit_mode: false,
              columns: snapshot.grid.columns,
              row_height_px: snapshot.grid.row_height_px,
              gap_px: snapshot.grid.gap_px,
            },
          },
        },
      };
    }),
    comparison_inspector: null,
    empty_state: snapshot.placements.length
      ? null
      : {
          wrapper: { attrs: { class: "py-12" } },
          card: { attrs: { class: "border border-dashed border-base-300 p-8 text-center" } },
          icon: { attrs: { class: "hero-squares-2x2 h-8 w-8 text-base-content/40" } },
          title: {
            attrs: { class: "mt-3 text-sm font-medium" },
            text: "No widgets in this dashboard",
          },
          message: {
            attrs: { class: `mt-1 ${muted}` },
            text: "This document has no widget placements.",
          },
          actions: { attrs: {}, action: null },
        },
  };
}
