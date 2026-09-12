export function workspaceFixture() {
  const header = {
    component_id: "widget-header",
    root: { class: "flex", attrs: {} },
    title: { class: "font-bold", text: "Battery voltage" },
    status_indicators: {
      class: "",
      attrs: {},
      limit: null,
      comparison: null,
      quality: null,
      lifecycle: null,
    },
    actions: {
      class: "",
      edit: [],
      details: {
        overlay: { id: "widget-details", class: "", attrs: {} },
        trigger: {
          id: "widget-details-trigger",
          type: "button",
          class: "",
          attrs: { "aria-label": "Widget details" },
          content: {
            class: "",
            attrs: {},
            icon: { name: "hero-information-circle", class: "h-4 w-4" },
          },
        },
        panel: { id: "widget-details-panel", class: "", hidden: true, attrs: {} },
        body: {
          class: "",
          heading: {
            class: "",
            title: { class: "", text: "Battery voltage" },
            binding: { class: "", text: "tlm.hk.battery_voltage" },
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
            class: "",
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
  const point = {
    kind: "value_tile",
    component_id: "widget-value",
    host: { class: "" },
    value: {
      container_class: "",
      text: "28.4",
      class: "text-3xl",
      attrs: { "data-value": "voltage" },
      unit: { text: "V", class: "" },
    },
    timestamp: { text: "Observed just now", class: "" },
    comparison: null,
  };
  const widget = {
    key: "battery",
    shell: {
      attrs: {
        id: "battery-widget",
        class: "grid-stack-item",
        "gs-id": "battery",
        "gs-x": "0",
        "gs-y": "0",
        "gs-w": "4",
        "gs-h": "2",
      },
    },
    content: { attrs: { class: "grid-stack-item-content" } },
    host: { attrs: { id: "battery-host" } },
    presentation: {
      component_id: "battery-component",
      header,
      body: {
        kind: "value_tile",
        root: { class: "", attrs: {} },
        notice: null,
        content: { component: "WidgetPoint", presentation: point },
      },
    },
  };
  const grid = {
    root: { attrs: { id: "workspace-grid", class: "grid-stack" } },
    widgets: [widget],
    controller: {
      host: { attrs: { id: "workspace-grid-controller" } },
      props: { target_id: "workspace-grid", item_ids: ["battery"], edit_mode: false },
    },
  };
  return {
    root: { attrs: { id: "workspace-canvas" } },
    content: { attrs: { class: "space-y-4" } },
    groups: [
      {
        key: "power",
        root: { attrs: { id: "power-section" } },
        section: {
          root: { attrs: { id: "power-section-disclosure", open: "" } },
          summary: {
            attrs: { id: "power-section-trigger", class: "w-full flex" },
            icon: { attrs: { class: "hero-chevron-down" } },
            copy: { attrs: {}, title: { attrs: {}, text: "Power" }, description: null },
            count: { attrs: {}, text: "1 widget" },
          },
        },
        grid,
      },
    ],
    comparison_inspector: null,
    empty_state: null,
  };
}
export function chartFixture() {
  const start = Date.UTC(2026, 8, 5, 18, 40);
  return {
    chart_id: "workspace-chart",
    widget_id: "temperature",
    placement_id: "temperature-placement",
    window_seconds: 300,
    correlation_group: "workspace",
    label: "Battery temperature",
    unit: "°C",
    time_mode: "historical",
    time_from: new Date(start).toISOString(),
    time_to: new Date(start + 300_000).toISOString(),
    backfill: Array.from({ length: 31 }, (_, i) => [start + i * 10_000, 18 + Math.sin(i / 4) * 2]),
  };
}
