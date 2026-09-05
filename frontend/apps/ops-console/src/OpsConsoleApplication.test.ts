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

const expectedSurfaceTable = [
  ["workspace", "overview", "mission", "application_workspace", "cadence.ops.workspace", []],
  [
    "ops",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.console",
    ["validate", "save", "filter", "refresh", "select", "open_data_link", "open_evidence", "set_chart_time_range"],
  ],
  ["contact_requirement_list", "collection", "mission", "ops_workspace", "cadence.ops.contact_requirement_list", []],
  ["contact_requirement_new", "configuration", "mission", "ops_workspace", "cadence.ops.contact_requirement_new", ["validate", "save"]],
  ["contact_requirement_show", "subject_detail", "mission", "ops_workspace", "cadence.ops.contact_requirement_show", ["plan", "toggle-opportunity", "create-plan"]],
  ["contact_requirement_template", "configuration", "mission", "ops_workspace", "cadence.ops.contact_requirement_template", ["validate-template", "create-template", "pause-template", "activate-template", "close-template"]],
  ["contact_schedule", "operations", "mission", "ops_workspace", "cadence.ops.contact_schedule", ["validate", "search", "reserve", "cancel"]],
  ["contact_plan_show", "subject_detail", "mission", "ops_workspace", "cadence.ops.contact_plan_show", ["submit-plan", "approve-plan", "reject-plan", "execute-plan"]],
  ["contact_detail", "subject_detail", "mission", "ops_workspace", "cadence.ops.contact_detail", ["approve-provider-change", "reject-provider-change", "acknowledge-provider-change"]],
  ["contact_record", "subject_detail", "mission", "ops_workspace", "cadence.ops.contact_record", []],
  ["dashboard_directory", "collection", "mission", "ops_workspace", "cadence.ops.dashboard_directory", ["filter_dashboards", "toggle_dashboard_star", "restore_dashboard"]],
  ["dashboard_show", "subject_detail", "mission", "ops_workspace", "cadence.ops.dashboard_show", []],
  ["dashboard_editor", "configuration", "mission", "ops_workspace", "cadence.ops.dashboard_editor", ["layout_changed", "validate_dashboard_section", "save_dashboard_section", "remove_dashboard_section", "move_dashboard_section", "preview_widget_binding", "validate_widget", "save_widget", "remove_widget", "rename", "archive_dashboard", "publish_dashboard", "publish_dashboard_version", "save_runtime_defaults", "restore_version_as_draft", "save_editor", "review_editor", "discard_editor", "reload_editor"]],
  ["dashboard_activity", "activity", "mission", "ops_workspace", "cadence.ops.dashboard_activity", ["publish_version", "restore_version"]],
  ["dashboard_new", "configuration", "mission", "ops_workspace", "cadence.ops.dashboard_new", ["validate", "save"]],
  ["dashboard_library", "collection", "mission", "ops_workspace", "cadence.ops.dashboard_library", ["stage-library-item", "create-library-item", "add-library-version"]],
  ["dashboard_playlists", "collection", "mission", "ops_workspace", "cadence.ops.dashboard_playlists", ["create-playlist"]],
  ["dashboard_playlist_present", "operations", "mission", "ops_workspace", "cadence.ops.dashboard_playlist_present", ["next-dashboard"]],
  ["dashboard_settings", "configuration", "mission", "ops_workspace", "cadence.ops.dashboard_settings", ["validate-settings", "save-settings", "create-share", "revoke-share", "create-snapshot", "archive-dashboard"]],
  ["dashboard_share", "subject_detail", "mission", "ops_workspace", "cadence.ops.dashboard_share", []],
  ["dashboard_snapshot", "subject_detail", "mission", "ops_workspace", "cadence.ops.dashboard_snapshot", []],
  ["dashboard_diagnostics", "activity", "mission", "ops_workspace", "cadence.ops.dashboard_diagnostics", []],
  ["fleet_planning", "operations", "mission", "ops_workspace", "cadence.ops.fleet_planning", ["refresh-planning"]],
  ["fleet_planning_new", "configuration", "mission", "ops_workspace", "cadence.ops.fleet_planning_new", ["validate-fleet-run", "create-fleet-run"]],
  ["fleet_planning_policy", "configuration", "mission", "ops_workspace", "cadence.ops.fleet_planning_policy", ["validate-policy", "save-policy", "approve-policy", "validate-grant", "issue-grant", "revoke-grant"]],
  ["fleet_planning_run", "subject_detail", "mission", "ops_workspace", "cadence.ops.fleet_planning_run", ["refresh-fleet-run", "repair-fleet-run"]],
  ["activation_requests", "operations", "mission", "ops_workspace", "cadence.ops.activation_requests", ["review", "decide"]],
  ["commands", "operations", "mission", "ops_workspace", "cadence.ops.commands", ["filter", "reset_filters", "follow_command", "clear_command_focus"]],
  ["telemetry_explore", "operations", "mission", "ops_workspace", "cadence.ops.telemetry_explore", ["apply_filters", "apply_question", "add_to_dashboard", "clear_selected_sample"]],
  ["data_operations", "operations", "mission", "ops_workspace", "cadence.ops.data_operations", ["validate-request", "record-historical-workflow-request", "transition-group", "retry-group", "request-correction"]],
  ["data_operations_manage", "operations", "mission", "ops_workspace", "cadence.ops.data_operations_manage", ["validate-request", "record-historical-workflow-request", "transition-group", "retry-group", "request-correction"]],
  ["data_sources", "configuration", "mission", "ops_workspace", "cadence.ops.data_sources", ["open-register-source", "cancel-register-source", "register-source", "open-change-binding", "cancel-change-binding", "change-binding", "disable-source", "enable-source", "reconcile-tsdb-backend", "deprovision-tsdb-backend", "provision-tsdb-backend", "probe-source", "rotate-source-credential", "retry-deployment-run", "requeue-deployment-run"]],
  ["data_source_registration", "configuration", "mission", "ops_workspace", "cadence.ops.data_source_registration", ["register-source"]],
  ["data_source_settings", "configuration", "mission", "ops_workspace", "cadence.ops.data_source_settings", ["change-binding", "disable-source", "enable-source", "reconcile-tsdb-backend", "deprovision-tsdb-backend", "provision-tsdb-backend", "probe-source", "rotate-source-credential", "retry-deployment-run", "requeue-deployment-run"]],
  ["alarms", "operations", "mission", "ops_workspace", "cadence.ops.alarms", ["filter", "reset_filters"]],
  ["timeline", "activity", "mission", "ops_workspace", "cadence.ops.timeline", ["apply_timeline_filters", "clear_timeline_selection"]],
] as const;

type TestQuery = (request: HostQueryRequest) => Promise<unknown>;
type TestExecute = (request: HostActionRequest<unknown>) => Promise<HostActionReceipt<unknown>>;

function propsFor(query: TestQuery, execute: TestExecute = vi.fn()) {
  const surface = surfaceContracts[1];
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
    const surface = surfaceContracts[1];
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

  it("never supplies route params to the host query bridge", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query) });

    await flushPromises();

    expect(query).toHaveBeenCalledOnce();
    expect(query.mock.calls[0]?.[0]).toEqual({
      queryId: surfaceContracts[1].dataContract.id,
      version: surfaceContracts[1].dataContract.version,
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
        detail: { eventName: "refresh", payload: { reason: "operator" } },
      }),
    );
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "ops_console",
      applicationVersion: 1,
      actionId: "refresh",
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
        detail: { eventName: "refresh", payload: {} },
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
        detail: { eventName: "refresh", payload: {} },
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
    expect(surfaceContracts).toHaveLength(36);
    expect(new Set(surfaceContracts.map((surface) => surface.surfaceId)).size).toBe(36);
    expect(new Set(surfaceContracts.flatMap((surface) => surface.actions)).size).toBe(103);
    expect(
      surfaceContracts
        .slice(2)
        .every((surface) => {
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
    expect(routeQueryContracts.data_source_registration).toEqual({ subjectParam: null, queryParams: [] });
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
