import {
  providerNewSurface,
  providerDetailSurface,
  providerListSurface,
} from "../../../modules/communications/src/features/providers/surface-fixtures.test-support";
import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type {
  CatalogApplication,
  FullPageSurfaceProps,
  HostBridge,
  HostQueryRequest,
  MissionHostContext,
} from "@cadence/plugin-sdk";
import CommsApplication from "./CommsApplication.vue";
import CommsGroundStationForm from "./CommsGroundStationForm.vue";
import { canonicalManifest } from "./federated-application";

const context: MissionHostContext = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
};

const surfaceIds = [
  "overview",
  "validation",
  "transports",
  "transport",
  "routing",
  "routing_detail",
  "ground_stations",
  "ground_station",
  "provider_list",
  "provider_new",
  "provider_show",
  "transport_new",
  "routing_new",
  "ground_station_new",
  "ground_station_edit",
] as const;

describe("Comms canonical federated application", () => {
  it.each(["provider_list", "provider_new", "provider_show"] as const)(
    "contains malformed %s before mounting and recovers through the feature entry",
    async (surface) => {
      const query = vi
        .fn<TestQuery>()
        .mockResolvedValueOnce({ ...surfacePayload(surface), data: {} })
        .mockResolvedValue(surfacePayload(surface));
      const wrapper = mount(CommsApplication, { props: propsFor(surface, query) });
      await flushPromises();
      expect(wrapper.find("#comms-application-error").exists()).toBe(true);
      await wrapper.get("#retry-comms-application").trigger("click");
      await flushPromises();
      expect(wrapper.find("#comms-application-error").exists()).toBe(false);
      expect(wrapper.find("[data-surface-id='" + surface + "']").exists()).toBe(true);
      wrapper.unmount();
    },
  );
  it("does not expose private query failures", async () => {
    const wrapper = mount(CommsApplication, {
      props: propsFor(
        "provider_show",
        vi.fn<TestQuery>().mockRejectedValue(new Error("private upstream diagnostics")),
      ),
    });
    await flushPromises();
    expect(wrapper.find("#comms-application-error").exists()).toBe(true);
    expect(wrapper.text()).not.toContain("private upstream diagnostics");
    wrapper.unmount();
  });
  it.each(["navigation", "completion"])(
    "keeps provider creation scoped through %s",
    async (mode) => {
      let finish!: (value: unknown) => void;
      const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload("provider_new"));
      const props = propsFor("provider_new", query);
      const execute = vi.fn(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          }),
      );
      props.bridge.execute = execute as HostBridge["execute"];
      props.bridge.navigate = vi.fn();
      const wrapper = mount(CommsApplication, { props });
      await flushPromises();
      await wrapper.get("#provider_provider_account_grant_id").setValue("grant-2");
      expect(execute).not.toHaveBeenCalled();
      await wrapper.get("#mission-provider-form").trigger("submit");
      expect(execute).toHaveBeenCalledExactlyOnceWith(
        expect.objectContaining({
          actionId: "create_provider",
          context,
          input: {
            provider: expect.objectContaining({
              provider_account_grant_id: "grant-2",
              provider_account_grant_version: "2",
              provider_account_version: "4",
            }),
          },
        }),
      );
      if (mode === "navigation")
        await wrapper.setProps(
          propsFor(
            "provider_list",
            vi.fn<TestQuery>().mockResolvedValue(surfacePayload("provider_list")),
          ),
        );
      finish({
        result: { provider_id: "saved-provider", version: 1, display_name: "Saved provider" },
      });
      await flushPromises();
      if (mode === "navigation") expect(props.bridge.navigate).not.toHaveBeenCalled();
      else
        expect(props.bridge.navigate).toHaveBeenCalledExactlyOnceWith(
          "/missions/mission-1/comms/providers/saved-provider",
        );
      wrapper.unmount();
    },
  );
  it.each(["transport_new", "routing_new", "ground_station_new", "ground_station_edit"] as const)(
    "rejects malformed %s form props before mount and recovers on retry",
    async (surfaceId) => {
      const query = vi
        .fn<TestQuery>()
        .mockResolvedValueOnce({ ...surfacePayload(surfaceId), data: { form: {} } })
        .mockResolvedValueOnce(surfacePayload(surfaceId));
      const wrapper = mount(CommsApplication, { props: propsFor(surfaceId, query) });
      await flushPromises();
      expect(wrapper.find("#comms-application-error").exists()).toBe(true);
      expect(wrapper.find("form").exists()).toBe(false);
      await wrapper.get("#retry-comms-application").trigger("click");
      await flushPromises();
      expect(wrapper.find("#comms-application-error").exists()).toBe(false);
      expect(wrapper.find("form").exists()).toBe(true);
      wrapper.unmount();
    },
  );

  it("contains a form renderer exception without exposing its private message", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload("ground_station_new"));
    const setup = vi.spyOn(CommsGroundStationForm, "setup").mockImplementation(() => {
      throw new Error("private form failure");
    });
    const wrapper = mount(CommsApplication, { props: propsFor("ground_station_new", query) });
    try {
      await flushPromises();
      expect(setup).toHaveBeenCalled();
      expect(wrapper.find("#comms-application-error").exists()).toBe(true);
      expect(wrapper.text()).not.toContain("private form failure");
    } finally {
      wrapper.unmount();
      setup.mockRestore();
    }
  });

  it("rejects unsupported form versions before presenting a save control", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload("routing_new"));
    const props = propsFor("routing_new", query);
    props.surface = {
      ...props.surface,
      dataContract: { ...props.surface.dataContract, version: 2 },
    };
    const wrapper = mount(CommsApplication, { props });
    await flushPromises();
    expect(wrapper.find("#comms-application-error").exists()).toBe(true);
    expect(wrapper.find("#create-routing-rule-button").exists()).toBe(false);
    wrapper.unmount();
  });
  it("contains malformed feature DTOs and retries without claiming a rendered page", async () => {
    const query = vi
      .fn<TestQuery>()
      .mockResolvedValueOnce({
        navigation: { fallback_href: "/missions/mission-1/comms/transports", breadcrumbs: [] },
        data: { title: "Transports", items: [] },
      })
      .mockResolvedValueOnce(surfacePayload("transports"));
    const wrapper = mount(CommsApplication, { props: propsFor("transports", query) });
    await flushPromises();
    expect(wrapper.find("#comms-read-unavailable").exists()).toBe(true);
    await wrapper.get("#retry-comms-read").trigger("click");
    await flushPromises();
    expect(wrapper.find("#comms-transports-directory").exists()).toBe(true);
    wrapper.unmount();
  });

  it("discards a query from an older surface after navigation", async () => {
    let finish!: (value: unknown) => void;
    const pending = new Promise<unknown>((resolve) => {
      finish = resolve;
    });
    const query = vi
      .fn<TestQuery>()
      .mockReturnValueOnce(pending)
      .mockResolvedValue(surfacePayload("ground_stations"));
    const wrapper = mount(CommsApplication, { props: propsFor("transports", query) });
    await wrapper.setProps(propsFor("ground_stations", query));
    await flushPromises();
    finish(surfacePayload("transports"));
    await flushPromises();
    expect(wrapper.find("#comms-ground-stations-directory").exists()).toBe(true);
    expect(wrapper.find("#comms-transports-directory").exists()).toBe(false);
    wrapper.unmount();
  });

  it.each(["navigation", "unmount"])("ignores a save receipt after %s", async (mode) => {
    let finish!: (value: unknown) => void;
    const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload("ground_station_new"));
    const props = propsFor("ground_station_new", query);
    props.bridge.execute = vi
      .fn()
      .mockResolvedValueOnce({ result: { valid: true } })
      .mockReturnValue(
        new Promise((resolve) => {
          finish = resolve;
        }),
      ) as HostBridge["execute"];
    props.bridge.navigate = vi.fn();
    const wrapper = mount(CommsApplication, { props });
    await flushPromises();
    await wrapper.get("#ground_station_display_name").setValue("Saved station");
    await flushPromises();
    await wrapper.get("#ground-station-form").trigger("submit");
    expect(props.bridge.execute).toHaveBeenLastCalledWith(
      expect.objectContaining({ actionId: "save" }),
    );
    if (mode === "unmount") wrapper.unmount();
    else
      await wrapper.setProps(
        propsFor("transports", vi.fn<TestQuery>().mockResolvedValue(surfacePayload("transports"))),
      );
    finish({ result: { navigation: { href: "/missions/mission-1/comms/ground-stations/old" } } });
    await flushPromises();
    expect(props.bridge.navigate).not.toHaveBeenCalled();
    if (mode === "navigation") {
      expect(wrapper.find("#comms-transports-directory").exists()).toBe(true);
      wrapper.unmount();
    }
  });
  it.each(surfaceIds)("queries and renders the %s surface through Phoenix", async (surfaceId) => {
    const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload(surfaceId));
    const props = propsFor(surfaceId, query);
    const wrapper = mount(CommsApplication, {
      props,
      global: {
        stubs: {
          CommsProviderList: true,
          CommsProviderNew: true,
          CommsProviderShow: true,
        },
      },
    });

    await flushPromises();

    expect(query).toHaveBeenCalledWith({
      queryId: `cadence.comms.${surfaceId}`,
      version: 1,
      context,
    });
    expect(wrapper.find("#comms-application-error").exists()).toBe(false);
    expect(wrapper.find("#comms-read-unavailable").exists()).toBe(false);
    expect(wrapper.find(`[data-surface-id="${surfaceId}"]`).exists()).toBe(true);
    wrapper.unmount();
  });

  it("contains malformed surface responses and retries the approved query", async () => {
    const query = vi
      .fn<TestQuery>()
      .mockResolvedValueOnce({ navigation: {}, data: {} })
      .mockResolvedValueOnce(surfacePayload("validation"));
    const wrapper = mount(CommsApplication, {
      props: propsFor("validation", query),
    });

    await flushPromises();
    expect(wrapper.find("#comms-application-error").exists()).toBe(true);

    await wrapper.get("#retry-comms-application").trigger("click");
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#comms-application-error").exists()).toBe(false);
    wrapper.unmount();
  });

  it("does not supply route params to a detail query", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload("provider_show"));
    const wrapper = mount(CommsApplication, {
      props: propsFor("provider_show", query),
      global: {
        stubs: { CommsProviderShow: true },
      },
    });

    await flushPromises();

    expect(query).toHaveBeenCalledWith({
      queryId: "cadence.comms.provider_show",
      version: 1,
      context,
    });
    wrapper.unmount();
  });

  it("sends validation through the host and preserves the local draft", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload("routing_new"));
    const props = propsFor("routing_new", query);
    const execute = vi.fn().mockResolvedValue({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00Z",
      result: { valid: true },
    });
    props.bridge.execute = execute as HostBridge["execute"];
    const wrapper = mount(CommsApplication, { props });

    await flushPromises();
    await wrapper.get("#routing_rule_display_name").setValue("Downlink");
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "comms",
      applicationVersion: 1,
      actionId: "validate",
      input: {
        routing_rule: {
          display_name: "Downlink",
          purpose_label: "",
          spacecraft_id: "",
          transport_ref: "",
          direction: "",
          role: "",
        },
      },
      context,
    });
    expect(query).toHaveBeenCalledTimes(1);
    expect((wrapper.get("#routing_rule_display_name").element as HTMLInputElement).value).toBe(
      "Downlink",
    );
    wrapper.unmount();
  });

  it("uses a save receipt navigation outcome without requerying", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload("ground_station_new"));
    const props = propsFor("ground_station_new", query);
    const execute = vi
      .fn()
      .mockResolvedValueOnce({ result: { valid: true } })
      .mockResolvedValue({
        receiptId: "receipt-2",
        completedAt: "2026-09-04T00:00:00Z",
        result: {
          navigation: { kind: "navigate", href: "/missions/mission-1/comms/ground-stations/gs-1" },
        },
      });
    props.bridge.execute = execute as HostBridge["execute"];
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => undefined);
    const wrapper = mount(CommsApplication, { props });

    await flushPromises();
    await wrapper.get("#ground_station_display_name").setValue("Saved station");
    await flushPromises();
    await wrapper.get("#ground-station-form").trigger("submit");
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "comms",
      applicationVersion: 1,
      actionId: "save",
      input: {
        ground_station: {
          ground_station_id: "",
          display_name: "Saved station",
          provider: "",
          region: "",
          metadata_json: "{}",
        },
      },
      context,
    });
    expect(assign).toHaveBeenCalledWith("/missions/mission-1/comms/ground-stations/gs-1");
    expect(query).toHaveBeenCalledTimes(1);
    assign.mockRestore();
    wrapper.unmount();
  });
});

type TestQuery = (request: HostQueryRequest) => Promise<unknown>;

function propsFor(surfaceId: (typeof surfaceIds)[number], query: TestQuery): FullPageSurfaceProps {
  const surface = canonicalManifest.surfaces.find((candidate) => candidate.surfaceId === surfaceId);
  if (!surface) throw new Error(`Unknown test surface ${surfaceId}`);

  const application: CatalogApplication = {
    applicationKey: "comms",
    applicationVersion: 1,
    displayName: "Communications",
    description: "Mission communications.",
    package: { packageId: "cadence.comms", version: 1 },
    surface,
    release: {
      federation: "module_federation",
      releaseId: "comms-v1",
      remoteName: "cadence_comms",
      manifestUrl: "/assets/application-host/comms/mf-manifest.json",
      exposedModule: "./Application",
    },
  };

  return {
    application,
    surface,
    context,
    bridge: bridgeFor(query),
  };
}

function formNavigation(label: string) {
  const paths: Record<string, string> = {
    "New Transport": "transports/new",
    "New Routing Rule": "routing/new",
    "New Ground Station": "ground-stations/new",
    "Edit Ground Station": "ground-stations/station-1/edit",
  };
  return {
    fallback_href: `/missions/mission-1/comms/${paths[label]}`,
    breadcrumbs: [
      { label: "Firebird", href: "/missions/mission-1" },
      { label: "Comms", href: "/missions/mission-1/comms" },
      { label, href: null },
    ],
  };
}

function transportFormPayload() {
  const field = (key: string, id: string, type = "text", value = "") => ({
    key,
    id,
    name: `transport[${key}]`,
    type,
    label: key,
    required: false,
    placeholder: null,
    options: [],
    value,
    provider_managed_id: null,
  });
  return {
    page: {
      id: "comms-transport-new-page",
      title: "New Transport",
      subtitle: "Transport",
      breadcrumbs: [],
    },
    form: {
      id: "transport-form",
      selected_origin: "direct",
      can_submit: false,
      sections: {
        identity: { id: "identity", number: "01", title: "Identity" },
        origin: { id: "origin", number: "02", title: "Origin" },
        source: { id: "source", number: "03", title: "Source" },
        provider_capability: { id: "capability", number: "04", title: "Capability" },
        review: { id: "review", number: "06", title: "Review" },
      },
      fields: {
        display_name: field("display_name", "transport-display-name"),
        origin: field("origin", "transport-origin", "select", "direct"),
        transport_kind: field("transport_kind", "transport-kind", "select", "tcp_socket"),
        mission_provider_id: field("mission_provider_id", "transport-provider", "select"),
        service_profile_id: field("service_profile_id", "transport-service-profile", "select"),
        delivery_profile_id: field("delivery_profile_id", "transport-delivery-profile", "select"),
      },
      origin_cards: [],
      direct_configuration: {
        id: "transport-direct-configuration",
        kind: "transport_kind",
        description: null,
        active: true,
        sections: [],
      },
      provider: {
        active: false,
        versions: [],
        profile_fields_id: "profiles",
        ready_count: 0,
        selected: null,
        empty_state: {
          id: "empty",
          visible: true,
          message: "",
          action: { label: "", href: "/missions/mission-1/comms/providers" },
        },
        operator_summary: null,
        derivation_error: null,
      },
      provider_derived: {
        active: false,
        id: "derived",
        number: "05",
        title: "Derived",
        description: "",
        configuration: { id: "configuration", rows: [], empty_text: "" },
      },
      review: {
        configuration_summary_id: "summary",
        ownership: { label: "", value: "", source: "" },
        readiness: { label: "", status: "attention", value: "", endpoint: "" },
        error: null,
        error_id: "error",
        diagnostics: { id: "diagnostics", label: "", json_id: "json", json: "{}" },
      },
      actions: {
        submit: { id: "create-transport-button", label: "Create" },
        cancel: { id: "cancel", label: "Cancel", href: "/missions/mission-1/comms/transports" },
      },
    },
  };
}

function routingFormPayload() {
  const field = (key: string, type = "text") => ({
    id: `routing_rule_${key}`,
    name: `routing_rule[${key}]`,
    type,
    label: key,
    required: true,
    value: "",
  });
  return {
    page: {
      id: "comms-routing-new-page",
      title: "New Routing Rule",
      subtitle: "Routing",
      breadcrumbs: [],
    },
    form: {
      id: "routing-rule-form",
      sections: {
        intent: { number: "01", title: "Intent" },
        transport: { number: "02", title: "Transport" },
        policy: { number: "03", title: "Policy" },
      },
      fields: {
        display_name: field("display_name"),
        purpose_label: field("purpose_label"),
        spacecraft_id: field("spacecraft_id", "select"),
        transport_ref: field("transport_ref", "select"),
        direction: field("direction", "select"),
        role: field("role", "select"),
      },
      actions: {
        submit: { id: "create-routing-rule-button", label: "Create" },
        cancel: { id: "cancel", label: "Cancel", href: "/missions/mission-1/comms/routing" },
      },
    },
    options: { spacecraft: [], transports: [], directions: [], roles: [] },
  };
}

function groundStationFormPayload(mode: "new" | "edit") {
  const field = (key: string, type = "text") => ({
    id: `ground_station_${key}`,
    name: `ground_station[${key}]`,
    type,
    label: key,
    required: false,
    disabled: mode === "edit" && key === "ground_station_id",
    placeholder: null,
    value:
      key === "metadata_json"
        ? "{}"
        : mode === "edit" && key === "ground_station_id"
          ? "station-1"
          : "",
  });
  return {
    page: {
      id: "comms-ground-station-form-page",
      heading: mode === "new" ? "New Ground Station" : "Edit Ground Station",
      subtitle: "Ground station",
      breadcrumbs: [],
    },
    mode,
    form: {
      id: "ground-station-form",
      sections: {
        identity: { id: "identity", number: "01", title: "Identity" },
        network: { id: "network", number: "02", title: "Network" },
        metadata: { id: "metadata", number: "03", title: "Metadata" },
      },
      fields: {
        ground_station_id: field("ground_station_id"),
        display_name: field("display_name"),
        provider: field("provider"),
        region: field("region"),
        metadata_json: field("metadata_json", "textarea"),
      },
      actions: {
        submit: {
          id: mode === "new" ? "create-ground-station-button" : "save-ground-station-button",
          label: "Save",
        },
        cancel: {
          id: "cancel",
          label: "Cancel",
          href: "/missions/mission-1/comms/ground-stations" + (mode === "edit" ? "/station-1" : ""),
        },
      },
    },
  };
}

function bridgeFor(query: TestQuery): HostBridge {
  return {
    query: async <TResult>(request: HostQueryRequest) => (await query(request)) as TResult,
    execute: vi.fn(),
    subscribe: vi.fn(),
  };
}

function surfacePayload(surfaceId: (typeof surfaceIds)[number]) {
  if (surfaceId === "overview") return overviewPayload();

  if (surfaceId === "provider_list") return providerListSurface();
  if (surfaceId === "provider_new") return providerNewSurface();
  if (surfaceId === "provider_show") return providerDetailSurface();

  if (surfaceId === "transport_new") {
    return {
      navigation: formNavigation("New Transport"),
      data: transportFormPayload(),
    };
  }

  if (surfaceId === "routing_new") {
    return {
      navigation: formNavigation("New Routing Rule"),
      data: routingFormPayload(),
    };
  }

  if (surfaceId === "ground_station_new" || surfaceId === "ground_station_edit") {
    return {
      navigation: formNavigation(
        surfaceId === "ground_station_new" ? "New Ground Station" : "Edit Ground Station",
      ),
      data: groundStationFormPayload(surfaceId === "ground_station_new" ? "new" : "edit"),
    };
  }

  const detailFixtures: Record<string, Record<string, unknown>> = {
    transport: {
      id: "transports-1",
      display_name: "Saved Transport",
      href: "/missions/mission-1/comms/transports/transports-1",
      list_href: "/missions/mission-1/comms/transports",
      version: 1,
      lifecycle_state: "active",
      origin: "direct",
      transport_kind: "tcp_socket",
      direction_capability: "inbound",
      provider_managed: false,
    },
    routing_detail: {
      id: "routing-1",
      display_name: "Saved Routing",
      href: "/missions/mission-1/comms/routing/routing-1",
      list_href: "/missions/mission-1/comms/routing",
      enabled: true,
      lifecycle_state: "active",
      spacecraft_id: "spacecraft-1",
      spacecraft_name: "Firebird",
      purpose_label: "Telemetry",
      direction: "inbound",
      transport_id: "transport-1",
      transport_name: "Lab TCP",
      transport_version: 1,
      role: "primary",
    },
    ground_station: {
      id: "ground-stations-1",
      display_name: "Saved GroundStation",
      href: "/missions/mission-1/comms/ground-stations/ground-stations-1",
      list_href: "/missions/mission-1/comms/ground-stations",
      lifecycle_state: "active",
      provider: "DSN",
      region: "Goldstone",
      edit_href: "/missions/mission-1/comms/ground-stations/ground-stations-1/edit",
    },
  };
  const detail = detailFixtures[surfaceId];
  const section = surfaceId === "ground_stations" ? "ground-stations" : surfaceId;
  const path = detail ? String(detail.href) : "/missions/mission-1/comms/" + section;
  return {
    navigation: {
      fallback_href: path,
      breadcrumbs: [{ label: "Firebird", href: "/missions/mission-1" }],
    },
    trusted_surface:
      detail ??
      (surfaceId === "validation"
        ? {
            id: "comms-validation-page",
            title: "Validation",
            finding_count: 0,
            empty: true,
            href: path,
            findings: [],
            finding_groups: [],
            status: "ready",
          }
        : {
            title: section,
            items: [],
            page: 1,
            page_size: 50,
            page_count: 1,
            total_count: 0,
            query: "",
            sort: "display_name",
            dir: "asc",
          }),
  };
}

function overviewPayload() {
  return {
    navigation: {
      fallback_href: "/missions/mission-1/comms",
      breadcrumbs: [
        { label: "Firebird", href: "/missions/mission-1" },
        { label: "Comms", href: null },
      ],
    },
    trusted_surface: {
      root: { attrs: { class: "space-y-6", id: "comms-overview-page" } },
      header: {
        attrs: { class: "border-b border-primary/20 pb-4" },
        body: { attrs: {} },
        content: { attrs: {} },
        eyebrow: { attrs: { class: "hud-label" }, text: "Communications" },
        title: { attrs: { class: "mission-title" }, text: "Firebird" },
        title_suffix: { attrs: { class: "mission-title-suffix" }, text: "· Mission Comms" },
      },
      overview: {
        transport: {
          id: "comms-transports",
          eyebrow: "Transport",
          count: 0,
          count_label: "transports configured",
          description: "Mission transport readiness.",
          status: { tone: "attention", label: "Needs Work" },
          empty: true,
          empty_state: {
            title: "No transports configured",
            description: "Add a transport.",
            action_label: "Add a transport",
            action_href: "/missions/mission-1/comms/transports/new",
          },
          rows: [],
          manage_label: "Manage transports →",
          manage_href: "/missions/mission-1/comms/transports",
          add_label: "+ Add a transport",
          add_href: "/missions/mission-1/comms/transports/new",
        },
        validation: {
          id: "comms-validation-page",
          eyebrow: "Setup Checks",
          title: "What's missing or broken",
          description: "Checks on saved configuration.",
          status: { tone: "ready", label: "No Findings" },
          empty: true,
          empty_state: {
            title: "All clear",
            description: "The saved configuration is consistent.",
          },
          findings_id: "comms-validation-findings",
          finding_groups: [],
        },
      },
    },
  };
}

it.each(["unknown", "toString", "constructor", "__proto__"])(
  "rejects unsupported renderer %s before querying",
  async (surfaceId) => {
    const query = vi.fn<TestQuery>().mockRejectedValue(new Error("unexpected query"));
    const props = propsFor("overview", query);
    const wrapper = mount(CommsApplication, {
      props: { ...props, surface: { ...props.surface, surfaceId } },
    });
    await flushPromises();
    expect(query).not.toHaveBeenCalled();
    expect(wrapper.find("#comms-application-error").exists()).toBe(true);
    wrapper.unmount();
  },
);
