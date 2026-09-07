import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
  MissionHostContext,
} from "@cadence/plugin-sdk";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";
import { manifest, routeQueryContracts, surfaceContracts } from "./federated-application";
import { OPS_COMPONENTS, OPS_COMPONENT_NAMES } from "./ops-components";
import { unwrapOpsConsoleResponse } from "./ops-console";

const context: MissionHostContext = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["ops:view"] },
};

const response = {
  queryVersion: 1,
  presentation: {
    component: "OpsConsoleLanding",
    props: { missionId: "mission-1", missionName: "Firebird", componentCount: 90 },
  },
};

const dashboardResponse = {
  queryVersion: 1,
  presentation: {
    component: "OpsDashboardDirectory",
    props: {
      page: {
        id: "ops-dashboards-page",
        header: {
          eyebrow: "Observe / Dashboards",
          heading: "Dashboard Directory",
          copy: "Find mission telemetry workspaces without crowding the navigation rail. Stars and recents are personal; dashboard definitions and tags remain mission shared.",
          count: { id: "dashboard-directory-count", value: 1, suffix: "matching" },
          author_actions: [
            {
              id: "dashboard-directory-new",
              label: "New Dashboard",
              icon: "hero-plus",
              icon_class: "h-4 w-4",
              href: "/missions/mission-1/ops/dashboards/new",
              class: "btn btn-primary btn-sm",
            },
          ],
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
        values: { query: "", lifecycle: "active", tag: "all", sort: "updated" },
        fields: {
          query: {
            id: "directory_query",
            name: "directory[query]",
            type: "search",
            label: "Search",
            placeholder: "Name, description, or tag",
            debounce_ms: 250,
          },
          lifecycle: {
            id: "directory_lifecycle",
            name: "directory[lifecycle]",
            type: "select",
            label: "Lifecycle",
            options: [
              { label: "Active", value: "active" },
              { label: "Archived", value: "archived" },
              { label: "All", value: "all" },
            ],
          },
          tag: {
            id: "directory_tag",
            name: "directory[tag]",
            type: "select",
            label: "Tag",
            options: [{ label: "All tags", value: "all" }],
          },
          sort: {
            id: "directory_sort",
            name: "directory[sort]",
            type: "select",
            label: "Sort",
            options: [
              { label: "Recently updated", value: "updated" },
              { label: "Name", value: "name" },
              { label: "Widget count", value: "widgets" },
            ],
          },
        },
      },
      dashboard_directory: [
        {
          id: "dashboard-1",
          __dom_id: "dashboard-dashboard-1",
          dashboard_id: "dashboard-1",
          name: "Firebird overview",
          description: "Mission overview dashboard",
          tags: ["flight"],
          lifecycle: { state: "active", class: "badge-success" },
          starred: false,
          open: { id: "dashboard-directory-open-dashboard-1", href: "#" },
          star: {
            id: "dashboard-directory-star-dashboard-1",
            payload: { "dashboard-id": "dashboard-1", starred: "true" },
            aria_label: "Star Firebird overview",
            aria_pressed: "false",
            disabled: false,
            title: null,
            icon: "hero-star",
          },
          widget_version_label: "2 widgets · v1",
          clone: null,
          restore: null,
        },
      ],
    },
  },
};

const telemetrySelectField = (key: string) => ({
  id: `explore_${key}`,
  name: `explore[${key}]`,
  type: "select",
  label: key,
  options: [{ label: "All", value: "" }],
});

const telemetryResponse = {
  queryVersion: 1,
  presentation: {
    component: "OpsTelemetryExplore",
    props: {
      page: {
        id: "ops-telemetry-explore-page",
        heading: "Telemetry Explore",
        point_label: "No point selected",
        realm: null,
        time_mode: "latest",
        source_state: "none",
        data_source_id: "",
        source_binding_id: "",
        logical_source: "",
        source_realm: "",
        selected_sample_state: "none",
        selected_sample_id: "",
        selected_sample_status: null,
        samples_summary: "0 rows",
        empty_samples_message: "No physical samples matched this context.",
      },
      clipboard: {
        button_id: "telemetry-explore-copy-link",
        text: "#",
        class: "btn btn-ghost btn-sm",
        icon: "hero-link",
        icon_class: "h-4 w-4",
        label: "Copy link",
        copied_message: "Copied",
        failed_message: "Copy failed",
      },
      investigation: {
        id: "telemetry-investigation",
        label: "Investigation",
        path: "#",
        fingerprint: "",
      },
      navigation: { back_to_dashboard: null },
      questions: [],
      question_briefing: null,
      filter_form: {
        id: "telemetry-explore-filter-form",
        values: {
          point_id: "",
          spacecraft_id: "",
          scope_kind: "",
          scope_id: "",
          time_mode: "latest",
          time_axis: "",
          from: "",
          to: "",
          replay_run_id: "",
          order: "desc",
          limit: "100",
          selection_view: "",
          validity_state: "",
          realm: "",
          logical_source: "",
          data_source_id: "",
          source_binding_id: "",
          source_dashboard_id: "",
          sample_id: "",
          selected_time: "",
          question: "",
          limit_mode: "",
        },
        fields: {
          point_id: telemetrySelectField("point_id"),
          spacecraft_id: telemetrySelectField("spacecraft_id"),
          time_mode: telemetrySelectField("time_mode"),
          from: { id: "explore_from", name: "explore[from]", type: "text", label: "From" },
          to: { id: "explore_to", name: "explore[to]", type: "text", label: "To" },
          order: telemetrySelectField("order"),
          limit: {
            id: "explore_limit",
            name: "explore[limit]",
            type: "number",
            label: "Limit",
            min: "1",
            max: "1000",
          },
          realm: telemetrySelectField("realm"),
          logical_source: telemetrySelectField("logical_source"),
          data_source_id: telemetrySelectField("data_source_id"),
          source_binding_id: telemetrySelectField("source_binding_id"),
          selection_view: telemetrySelectField("selection_view"),
          validity_state: telemetrySelectField("validity_state"),
        },
        submit: { id: "telemetry-explore-apply-filters", label: "Load", icon: "hero-arrow-path" },
      },
      point: {
        id: "telemetry-explore-point-card",
        requested_point_id: "",
        rows: [],
        missing: false,
      },
      selected_sample: null,
      source_context: {
        id: "telemetry-explore-source-card",
        state: "none",
        data_source_id: "",
        source_binding_id: "",
        logical_source: "",
        realm: "",
        matched_data_source_id: "",
        matched_source_binding_id: "",
        rows: [],
        actions: [],
      },
      context_rows: [],
      diagnostics: { id: "telemetry-explore-diagnostics-card", rows: [] },
      samples: [],
    },
  },
};

const expectedSurfaceTable = [
  ["workspace", "overview", "mission", "application_workspace", "cadence.ops.workspace", []],
  [
    "contact_requirement_list",
    "collection",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_requirement_list",
    [],
  ],
  [
    "contact_requirement_new",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_requirement_new",
    ["validate", "save"],
  ],
  [
    "contact_requirement_show",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_requirement_show",
    ["plan", "create-plan"],
  ],
  [
    "contact_requirement_template",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_requirement_template",
    [
      "validate-template",
      "create-template",
      "pause-template",
      "activate-template",
      "close-template",
    ],
  ],
  [
    "contact_schedule",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_schedule",
    ["validate", "search", "reserve", "cancel"],
  ],
  [
    "contact_plan_show",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_plan_show",
    ["submit-plan", "approve-plan", "reject-plan", "execute-plan"],
  ],
  [
    "contact_detail",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_detail",
    ["approve-provider-change", "reject-provider-change", "acknowledge-provider-change"],
  ],
  [
    "contact_record",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_record",
    [],
  ],
  [
    "dashboard_directory",
    "collection",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_directory",
    ["filter_dashboards", "toggle_dashboard_star", "restore_dashboard"],
  ],
  [
    "dashboard_show",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_show",
    [],
  ],
  [
    "dashboard_editor",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_editor",
    [
      "layout_changed",
      "validate_dashboard_section",
      "save_dashboard_section",
      "remove_dashboard_section",
      "move_dashboard_section",
      "preview_widget_binding",
      "validate_widget",
      "save_widget",
      "remove_widget",
      "rename",
      "archive_dashboard",
      "publish_dashboard",
      "publish_dashboard_version",
      "save_runtime_defaults",
      "restore_version_as_draft",
      "save_editor",
      "review_editor",
      "discard_editor",
      "reload_editor",
    ],
  ],
  [
    "dashboard_activity",
    "activity",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_activity",
    ["publish_version", "restore_version"],
  ],
  [
    "dashboard_new",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_new",
    ["validate", "save"],
  ],
  [
    "dashboard_library",
    "collection",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_library",
    ["stage-library-item", "create-library-item", "add-library-version"],
  ],
  [
    "dashboard_playlists",
    "collection",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_playlists",
    ["create-playlist"],
  ],
  [
    "dashboard_playlist_present",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_playlist_present",
    ["next-dashboard"],
  ],
  [
    "dashboard_settings",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_settings",
    [
      "validate-settings",
      "save-settings",
      "create-share",
      "revoke-share",
      "create-snapshot",
      "archive-dashboard",
    ],
  ],
  [
    "dashboard_share",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_share",
    [],
  ],
  [
    "dashboard_snapshot",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_snapshot",
    [],
  ],
  [
    "dashboard_diagnostics",
    "activity",
    "mission",
    "ops_workspace",
    "cadence.ops.dashboard_diagnostics",
    [],
  ],
  [
    "fleet_planning",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.fleet_planning",
    ["refresh-planning"],
  ],
  [
    "fleet_planning_new",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.fleet_planning_new",
    ["validate-fleet-run", "create-fleet-run"],
  ],
  [
    "fleet_planning_policy",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.fleet_planning_policy",
    [
      "validate-policy",
      "save-policy",
      "approve-policy",
      "validate-grant",
      "issue-grant",
      "revoke-grant",
    ],
  ],
  [
    "fleet_planning_run",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.fleet_planning_run",
    ["refresh-fleet-run", "repair-fleet-run"],
  ],
  [
    "activation_requests",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.activation_requests",
    ["decide"],
  ],
  ["commands", "operations", "mission", "ops_workspace", "cadence.ops.commands", []],
  [
    "telemetry_explore",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.telemetry_explore",
    ["apply_filters", "apply_question", "add_to_dashboard"],
  ],
  [
    "data_operations",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.data_operations",
    [
      "validate-request",
      "record-historical-workflow-request",
      "transition-group",
      "retry-group",
      "request-correction",
    ],
  ],
  [
    "data_operations_manage",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.data_operations_manage",
    [
      "validate-request",
      "record-historical-workflow-request",
      "transition-group",
      "retry-group",
      "request-correction",
    ],
  ],
  [
    "data_sources",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.data_sources",
    [
      "register-source",
      "change-binding",
      "disable-source",
      "enable-source",
      "reconcile-tsdb-backend",
      "deprovision-tsdb-backend",
      "provision-tsdb-backend",
      "probe-source",
      "rotate-source-credential",
      "retry-deployment-run",
      "requeue-deployment-run",
    ],
  ],
  [
    "data_source_registration",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.data_source_registration",
    ["register-source"],
  ],
  [
    "data_source_settings",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.data_source_settings",
    [
      "change-binding",
      "disable-source",
      "enable-source",
      "reconcile-tsdb-backend",
      "deprovision-tsdb-backend",
      "provision-tsdb-backend",
      "probe-source",
      "rotate-source-credential",
      "retry-deployment-run",
      "requeue-deployment-run",
    ],
  ],
  [
    "alarms",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.alarms",
    ["filter", "reset_filters"],
  ],
  [
    "timeline",
    "activity",
    "mission",
    "ops_workspace",
    "cadence.ops.timeline",
    ["apply_timeline_filters", "clear_timeline_selection"],
  ],
] as const;

type TestQuery = (request: HostQueryRequest) => Promise<unknown>;
type TestExecute = (request: HostActionRequest<unknown>) => Promise<HostActionReceipt<unknown>>;

function propsFor(query: TestQuery, execute: TestExecute = vi.fn()) {
  const surface = surfaceContracts.find((candidate) => candidate.surfaceId === "fleet_planning")!;
  return {
    application: {
      applicationKey: "ops_console",
      applicationVersion: 1,
      displayName: "Ops Console",
      description: "Mission operations.",
      package: { packageId: "cadence.ops_console", version: 1 },
      surface,
      release: {
        federation: "module_federation" as const,
        releaseId: "ops-console-v1",
        remoteName: "cadence_ops_console",
        manifestUrl: "/assets/application-host/ops-console/mf-manifest.json",
        exposedModule: "./Application",
      },
    },
    surface,
    context,
    bridge: {
      query: async <TResult>(request: HostQueryRequest) => (await query(request)) as TResult,
      execute: async <TInput, TResult>(request: HostActionRequest<TInput>) =>
        (await execute(request as HostActionRequest<unknown>)) as HostActionReceipt<TResult>,
      subscribe: vi.fn(),
    },
  } satisfies FullPageSurfaceProps;
}

describe("Ops Console federated application", () => {
  it("queries the preserved Ops workspace surface and renders its Phoenix DTO", async () => {
    const surface = surfaceContracts.find((candidate) => candidate.surfaceId === "fleet_planning")!;
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const baseProps = propsFor(query);
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });

    expect(wrapper.find("#ops-console-loading").exists()).toBe(true);
    await flushPromises();

    expect(query).toHaveBeenCalledWith({
      queryId: surface.dataContract.id,
      version: surface.dataContract.version,
      context,
    });
    expect(wrapper.find("#ops-console-application").exists()).toBe(true);
    expect(wrapper.text()).toContain("Firebird");
    wrapper.unmount();
  });

  it("renders the backend-shaped dashboard directory DTO without optional props", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(dashboardResponse);
    const surface = surfaceContracts.find(
      (candidate) => candidate.surfaceId === "dashboard_directory",
    )!;
    const baseProps = propsFor(query);
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });

    await flushPromises();

    expect(wrapper.find("#ops-dashboards-page").exists()).toBe(true);
    expect(wrapper.find("#dashboard-directory-count").text()).toContain("1 matching");
    expect(wrapper.find("#dashboard-directory-new").exists()).toBe(true);
    expect(wrapper.find("#dashboard-dashboard-1").exists()).toBe(true);
    expect(wrapper.find("[data-dashboard-directory-id='dashboard-1']").exists()).toBe(true);
    wrapper.unmount();
  });

  it("mounts the Phoenix telemetry contract without containment", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(telemetryResponse);
    const surface = surfaceContracts.find(
      (candidate) => candidate.surfaceId === "telemetry_explore",
    )!;
    const baseProps = propsFor(query);
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });

    await flushPromises();

    expect(wrapper.find("#ops-telemetry-explore-page").exists()).toBe(true);
    expect(wrapper.find("#telemetry-explore-filter-form").exists()).toBe(true);
    expect(wrapper.find("#ops-console-error").exists()).toBe(false);
    wrapper.unmount();
  });

  it("never supplies route params to the host query bridge", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query) });

    await flushPromises();

    expect(query).toHaveBeenCalledOnce();
    expect(query.mock.calls[0]?.[0]).toEqual({
      queryId: surfaceContracts.find((candidate) => candidate.surfaceId === "fleet_planning")!
        .dataContract.id,
      version: surfaceContracts.find((candidate) => candidate.surfaceId === "fleet_planning")!
        .dataContract.version,
      context,
    });
    expect(query.mock.calls[0]?.[0]).not.toHaveProperty("params");
    wrapper.unmount();
  });

  it("contains query failures and retries the same Phoenix-owned contract", async () => {
    const query = vi
      .fn<TestQuery>()
      .mockRejectedValueOnce(new Error("query unavailable"))
      .mockResolvedValueOnce(response);
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query) });

    await flushPromises();
    expect(wrapper.find("#ops-console-error").text()).toContain("query unavailable");
    await wrapper.get("#retry-ops-console").trigger("click");
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#ops-console-application").exists()).toBe(true);
    wrapper.unmount();
  });

  it("dispatches remote events through the Phoenix-owned action bridge", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const execute = vi.fn<TestExecute>().mockResolvedValue({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00.000Z",
      result: {},
    });
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query, execute) });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "refresh-planning", payload: { reason: "operator" } },
      }),
    );
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "ops_console",
      applicationVersion: 1,
      surfaceId: "fleet_planning",
      surfaceVersion: 1,
      actionId: "refresh-planning",
      input: { reason: "operator" },
      context,
    });
    expect(wrapper.find("#ops-console-action-notice").exists()).toBe(true);
    wrapper.unmount();
  });

  it("shows the server receipt and refreshes the Phoenix presentation after completion", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const execute = vi.fn<TestExecute>().mockResolvedValue({
      receiptId: "receipt-complete",
      completedAt: "2026-09-04T00:00:00.000Z",
      result: { status: "completed" },
    });
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query, execute) });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "refresh-planning", payload: {} },
      }),
    );
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#ops-console-action-notice").text()).toContain("completed");
    wrapper.unmount();
  });

  it("forwards a visible dashboard action from the federated surface", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const execute = vi.fn<TestExecute>().mockResolvedValue({
      receiptId: "receipt-layout",
      completedAt: "2026-09-04T00:00:00.000Z",
      result: { status: "completed" },
    });
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query, execute) });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "refresh-planning", payload: {} },
      }),
    );
    await flushPromises();

    expect(execute).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#ops-console-action-notice").exists()).toBe(true);
    wrapper.unmount();
  });

  it("keeps the complete frozen Ops family in the remote component registry", () => {
    const required = [
      "OpsActivationRequests",
      "OpsAlarms",
      "OpsCommands",
      "OpsDashboardDirectory",
      "OpsDashboardNew",
      "OpsDataOperations",
      "OpsDataSources",
      "OpsFleetPlanning",
      "OpsTelemetryExplore",
      "DashboardCanvas",
      "DashboardWidget",
      "HistoricalWorkflowControls",
      "RuntimeDiagnosticsPanel",
      "SourceHealth",
      "SelectedActivityActions",
      "ActivityTimeline",
      "ComparisonReviewActivityDetails",
      "EvidenceInspectorPanel",
      "WidgetForm",
      "TelemetryChart",
    ];

    expect(required.every((name) => Boolean(OPS_COMPONENTS[name]))).toBe(true);
    expect(OPS_COMPONENT_NAMES).toContain("OpsConsoleLanding");
  });

  it("publishes the exact first-party mission identity", () => {
    expect(manifest.package).toMatchObject({ packageId: "cadence.ops_console", version: 1 });
    expect(manifest.application).toMatchObject({ applicationKey: "ops_console", version: 1 });
    expect(manifest.application.installableScopes).toEqual(["mission"]);
    expect(manifest.surfaces).toEqual(surfaceContracts);
    expect(surfaceContracts).toHaveLength(35);
    expect(new Set(surfaceContracts.map((surface) => surface.surfaceId)).size).toBe(35);
    expect(surfaceContracts.flatMap((surface) => surface.actions)).toHaveLength(108);
    expect(
      new Set(
        surfaceContracts.flatMap((surface) =>
          surface.actions.map((action) => `${surface.surfaceId}:${action}`),
        ),
      ).size,
    ).toBe(108);
    expect(new Set(surfaceContracts.flatMap((surface) => surface.actions)).size).toBe(89);
    expect(
      surfaceContracts.slice(2).every((surface) => {
        const componentName =
          surface.surfaceId === "dashboard_editor"
            ? "OpsDashboardShow"
            : `Ops${surface.surfaceId.replace(/(^|_)(\w)/g, (_, _prefix, letter) => letter.toUpperCase())}`;
        return Boolean(OPS_COMPONENTS[componentName]);
      }),
    ).toBe(true);
  });

  it("publishes exact deep-route subject and query contracts", () => {
    expect(routeQueryContracts.dashboard_show.subjectParam).toBe("dashboard_id");
    expect(routeQueryContracts.dashboard_editor.queryParams).toEqual(["dashboard_id"]);
    expect(routeQueryContracts.dashboard_activity.queryParams).toEqual([
      "dashboard_id",
      "version",
      "selected_publish_issue",
    ]);
    expect(routeQueryContracts.data_source_registration).toEqual({
      subjectParam: null,
      queryParams: [],
    });
    expect(routeQueryContracts.data_operations_manage.queryParams).toEqual(["group"]);

    for (const surfaceId of [
      "dashboard_show",
      "dashboard_editor",
      "dashboard_activity",
      "data_source_registration",
      "data_source_settings",
      "data_operations_manage",
    ]) {
      const surface = surfaceContracts.find((candidate) => candidate.surfaceId === surfaceId);
      expect(surface?.actions).toBeDefined();
    }
  });

  it("matches the complete Phoenix Ops purpose, scope, placement, query, and action table", () => {
    expect(
      surfaceContracts.map((surface) => [
        surface.surfaceId,
        surface.purpose,
        surface.scope,
        surface.placement,
        surface.dataContract.id,
        [...surface.actions],
      ]),
    ).toEqual(expectedSurfaceTable);
  });
});

describe("Ops Console response boundary", () => {
  it("rejects an unknown component instead of evaluating server input", () => {
    expect(() =>
      unwrapOpsConsoleResponse(
        {
          queryVersion: 1,
          presentation: { component: "NotAnOpsComponent", props: {} },
        },
        OPS_COMPONENTS,
      ),
    ).toThrow("presentation component is invalid");
  });

  it("accepts the authenticated host response envelope", () => {
    expect(unwrapOpsConsoleResponse({ trusted_surface: response }, OPS_COMPONENTS)).toEqual(
      response.presentation,
    );
  });
});
