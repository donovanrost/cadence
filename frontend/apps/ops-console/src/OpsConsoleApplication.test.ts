import { required } from "../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
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
    props: {
      model: {
        version: 1,
        context: { organization_id: "org-1", mission_id: "mission-1" },
        mission_name: "Firebird",
        can_administer: false,
      },
    },
  },
};

const dashboardResponse = {
  queryVersion: 1,
  presentation: {
    component: "OpsDashboardDirectory",
    props: {
      model: {
        version: 2,
        context: { organization_id: "org-1", mission_id: "mission-1" },
        filters: {
          query: "Flight",
          tags: ["thermal"],
          starred: false,
          archived: true,
          sort: "name",
          page: 2,
        },
      },
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

function propsFor(query: TestQuery, execute: TestExecute = vi.fn(), surfaceId = "fleet_planning") {
  const surface = required(surfaceContracts.find((candidate) => candidate.surfaceId === surfaceId));
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
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "workspace"),
    );
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const baseProps = propsFor(query);
    // The host draws the title and the mission in its breadcrumbs; the landing describes it.
    const header = pageHeaderHarness("/missions/:mission_id/ops");
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
      global: { provide: header.provide },
    });

    expect(wrapper.find("#ops-console-loading").exists()).toBe(true);
    await flushPromises();

    expect(query).toHaveBeenCalledWith({
      queryId: surface.dataContract.id,
      version: surface.dataContract.version,
      context,
    });
    expect(wrapper.find("#ops-console-application").exists()).toBe(true);
    expect(header.header().description).toBeTypeOf("string");
    wrapper.unmount();
  });

  it("binds legacy landing responses to host identity and removes links after context changes", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const baseProps = propsFor(query);
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "workspace"),
    );
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });
    await flushPromises();
    expect(wrapper.get("#ops-entry-dashboards").attributes("href")).toBe(
      "/missions/mission-1/ops/dashboards",
    );
    await wrapper.setProps({ context: { ...context, missionId: "mission-2" } });
    expect(wrapper.find("#ops-workspace-landing-unavailable").exists()).toBe(true);
    expect(wrapper.find("#ops-entry-dashboards").exists()).toBe(false);
    wrapper.unmount();
  });

  it("ignores response-supplied host identity when a workspace model belongs to another mission", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue({
      ...response,
      presentation: {
        ...response.presentation,
        props: {
          organizationId: "org-foreign",
          missionId: "mission-foreign",
          model: {
            ...response.presentation.props.model,
            context: { organization_id: "org-foreign", mission_id: "mission-foreign" },
          },
        },
      },
    });
    const baseProps = propsFor(query);
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "workspace"),
    );
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });
    await flushPromises();
    expect(wrapper.find("#ops-workspace-landing-unavailable").exists()).toBe(true);
    expect(wrapper.findAll("#ops-workspace-landing a")).toHaveLength(0);
    wrapper.unmount();
  });

  it("binds creation destinations to the host identity and drops them when the context changes", async () => {
    const model = {
      version: 1,
      context: { organization_id: "org-1", mission_id: "mission-1" },
      mode: "clone",
      source_dashboard_id: "source-1",
    };
    const query = vi.fn<TestQuery>().mockResolvedValue({
      queryVersion: 1,
      presentation: { component: "OpsDashboardNew", props: { model } },
    });
    const baseProps = propsFor(query);
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "dashboard_new"),
    );
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });
    await flushPromises();
    expect(wrapper.get("#dashboard-creation-destination-open").attributes("href")).toBe(
      "/missions/mission-1/ops/dashboards/new?mode=clone&source_dashboard_id=source-1",
    );
    await wrapper.setProps({ context: { ...context, missionId: "mission-2" } });
    expect(wrapper.find("#dashboard-creation-destination-open").exists()).toBe(false);
    wrapper.unmount();
  });

  it("does not accept response-supplied context for a foreign creation destination", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue({
      queryVersion: 1,
      presentation: {
        component: "OpsDashboardNew",
        props: {
          organizationId: "foreign",
          missionId: "foreign",
          model: {
            version: 1,
            context: { organization_id: "foreign", mission_id: "foreign" },
            mode: "new",
            source_dashboard_id: null,
          },
        },
      },
    });
    const baseProps = propsFor(query);
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "dashboard_new"),
    );
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });
    await flushPromises();
    expect(wrapper.find("#dashboard-creation-destination-open").exists()).toBe(false);
    expect(wrapper.find("#dashboard-creation-destination [role=status]").exists()).toBe(true);
    wrapper.unmount();
  });

  it("preserves directory filters through the owner and removes destinations on host context change", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(dashboardResponse);
    const baseProps = propsFor(query);
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "dashboard_directory"),
    );
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });
    await flushPromises();
    expect(wrapper.get("#dashboard-directory-destination-open").attributes("href")).toBe(
      "/missions/mission-1/ops/dashboards?query=Flight&tags=thermal&archived=true&sort=name&page=2",
    );
    expect(wrapper.findAll("form")).toHaveLength(0);
    await wrapper.setProps({ context: { ...context, missionId: "mission-2" } });
    expect(wrapper.find("#dashboard-directory-destination-open").exists()).toBe(false);
    wrapper.unmount();
  });

  it("does not let a directory response override the actual host context", async () => {
    const model = {
      ...dashboardResponse.presentation.props.model,
      context: { organization_id: "foreign", mission_id: "foreign" },
    };
    const query = vi.fn<TestQuery>().mockResolvedValue({
      ...dashboardResponse,
      presentation: {
        component: "OpsDashboardDirectory",
        props: { model, organizationId: "foreign", missionId: "foreign" },
      },
    });
    const baseProps = propsFor(query);
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "dashboard_directory"),
    );
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });
    await flushPromises();
    expect(wrapper.find("#dashboard-directory-destination-open").exists()).toBe(false);
    expect(wrapper.find("#dashboard-directory-destination [role=status]").exists()).toBe(true);
    wrapper.unmount();
  });

  it("links the legacy telemetry contract to the canonical host page without containment", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue({
      ...telemetryResponse,
      presentation: {
        component: "OpsTelemetryExplore",
        props: { mission_id: "mission-a", query: { point_id: "HK.temp" } },
      },
    });
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "telemetry_explore"),
    );
    const baseProps = propsFor(query);
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });

    await flushPromises();

    expect(wrapper.get("#exploration-open-workspace").attributes("href")).toBe(
      "/missions/mission-a/ops/explore?point_id=HK.temp",
    );
    expect(wrapper.find("#telemetry-explore-filter-form").exists()).toBe(false);
    expect(wrapper.find("#ops-console-error").exists()).toBe(false);
    wrapper.unmount();
  });

  it("delegates the legacy timeline entry to the core owner with its event link", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue({
      queryVersion: 1,
      presentation: {
        component: "OpsTimeline",
        props: {
          mission_id: "mission-a",
          query: { event_id: "mission_event:one", severity: "warning" },
        },
      },
    });
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query, vi.fn(), "timeline") });
    await flushPromises();
    expect(wrapper.get("#timeline-destination a").attributes("href")).toBe(
      "/missions/mission-a/ops/timeline?severity=warning&event_id=mission_event%3Aone",
    );
    expect(wrapper.find("#timeline-filter-form").exists()).toBe(false);
    expect(wrapper.find("#ops-console-error").exists()).toBe(false);
    wrapper.unmount();
  });

  it("never supplies route params to the host query bridge", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query) });

    await flushPromises();

    expect(query).toHaveBeenCalledOnce();
    expect(query.mock.calls[0]?.[0]).toEqual({
      queryId: required(
        surfaceContracts.find((candidate) => candidate.surfaceId === "fleet_planning"),
      ).dataContract.id,
      version: required(
        surfaceContracts.find((candidate) => candidate.surfaceId === "fleet_planning"),
      ).dataContract.version,
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
    const wrapper = mount(OpsConsoleApplication, {
      props: propsFor(query, execute, "dashboard_directory"),
    });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "toggle_dashboard_star", payload: { dashboard_id: "dashboard-1" } },
      }),
    );
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "ops_console",
      applicationVersion: 1,
      surfaceId: "dashboard_directory",
      surfaceVersion: 1,
      actionId: "toggle_dashboard_star",
      input: { dashboard_id: "dashboard-1" },
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
    const wrapper = mount(OpsConsoleApplication, {
      props: propsFor(query, execute, "dashboard_directory"),
    });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "toggle_dashboard_star", payload: { dashboard_id: "dashboard-1" } },
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
    const wrapper = mount(OpsConsoleApplication, {
      props: propsFor(query, execute, "dashboard_directory"),
    });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "toggle_dashboard_star", payload: { dashboard_id: "dashboard-1" } },
      }),
    );
    await flushPromises();

    expect(execute).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#ops-console-action-notice").exists()).toBe(true);
    wrapper.unmount();
  });

  it("admits native route roots and excludes obsolete widgets and inherited object names", () => {
    const required = [
      "OpsActivationRequests",
      "OpsAlarms",
      "OpsCommands",
      "OpsConsoleLanding",
      "OpsContactDetail",
      "OpsContactPlanShow",
      "OpsContactRecord",
      "OpsContactRequirementList",
      "OpsContactRequirementNew",
      "OpsContactRequirementShow",
      "OpsContactRequirementTemplate",
      "OpsContactSchedule",
      "OpsDashboardActivitySurface",
      "OpsDashboardDiagnostics",
      "OpsDashboardDirectory",
      "OpsDashboardLibrary",
      "OpsDashboardNew",
      "OpsDashboardPlaylistPresent",
      "OpsDashboardPlaylists",
      "OpsDashboardSettings",
      "OpsDashboardShare",
      "OpsDashboardShow",
      "OpsDashboardSnapshot",
      "OpsDataOperations",
      "OpsDataOperationsManage",
      "OpsDataSourceRegistration",
      "OpsDataSourceSettings",
      "OpsDataSources",
      "OpsFleetPlanning",
      "OpsFleetPlanningNew",
      "OpsFleetPlanningPolicy",
      "OpsFleetPlanningRun",
      "OpsTelemetryExplore",
      "OpsTimeline",
    ];
    expect(OPS_COMPONENT_NAMES).toEqual(required);
    for (const component of [
      "OpsDashboardActivity",
      "DashboardCanvas",
      "WidgetForm",
      "HistoricalWorkflowControls",
      "unknown",
      "toString",
      "constructor",
      "__proto__",
    ]) {
      expect(() =>
        unwrapOpsConsoleResponse(
          { queryVersion: 1, presentation: { component, props: {} } },
          OPS_COMPONENTS,
        ),
      ).toThrow("presentation component is invalid");
    }
    expect(routeQueryContracts.dashboard_playlist_present).toEqual({
      subjectParam: "playlist_id",
      queryParams: ["playlist_id", "index"],
    });
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
            : surface.surfaceId === "dashboard_activity"
              ? "OpsDashboardActivitySurface"
              : `Ops${surface.surfaceId.replace(/(^|_)(\w)/g, (_: string, _prefix: string, letter: string) => letter.toUpperCase())}`;
        return Boolean(OPS_COMPONENTS[componentName]);
      }),
    ).toBe(true);
  });

  it("publishes exact deep-route subject and query contracts", () => {
    expect(routeQueryContracts.dashboard_directory.queryParams).toEqual([
      "query",
      "tags",
      "starred",
      "archived",
      "sort",
      "page",
      "lifecycle",
      "tag",
    ]);
    expect(routeQueryContracts.dashboard_new.queryParams).toEqual(["mode", "source_dashboard_id"]);
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
