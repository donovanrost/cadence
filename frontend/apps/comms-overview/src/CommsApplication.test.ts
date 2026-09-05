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
] as const;

describe("Comms canonical federated application", () => {
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
    expect(wrapper.find(".space-y-6").exists()).toBe(true);
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

function bridgeFor(query: TestQuery): HostBridge {
  return {
    query: async <TResult>(request: HostQueryRequest) => (await query(request)) as TResult,
    execute: vi.fn(),
    subscribe: vi.fn(),
  };
}

function surfacePayload(surfaceId: (typeof surfaceIds)[number]) {
  if (surfaceId === "overview") return overviewPayload();

  if (surfaceId === "provider_list") {
    return {
      navigation: providerNavigation("providers"),
      trusted_surface: {
        presentation: {
          root: { attrs: { id: "comms-providers-page", class: "space-y-6" } },
          header: {
            attrs: {},
            body: { attrs: {} },
            content: { attrs: {} },
            breadcrumbs: { attrs: {}, items: [] },
            title: { attrs: {}, text: "Providers", suffix: { attrs: {}, text: "0 configured" } },
            subtitle: { attrs: {}, text: "Providers" },
            actions: { attrs: {}, new_provider: { attrs: {}, icon: { attrs: {} }, text: "New" } },
          },
          empty_state: null,
          card: null,
        },
      },
    };
  }

  if (surfaceId === "provider_new") {
    return {
      navigation: providerNavigation("New Provider"),
      trusted_surface: {
        page: {
          id: "comms-provider-new-page",
          title: "New Mission Provider",
          subtitle: "Provider setup.",
          breadcrumbs: [{ label: "New", href: null }],
        },
        accounts: {
          empty: true,
          options: [],
          selected: null,
          empty_state: {
            id: "mission-provider-no-grants",
            heading: "No grants",
            message: "Grant an account.",
            action: { id: "open-provider-accounts-link", label: "Open", href: "/provider-accounts" },
          },
        },
        notes: { secret_boundary: { id: "secret", text: "Secret boundary." }, resource_boundary: { id: "resource", text: "Resource boundary." } },
        form: providerFormPayload(),
      },
    };
  }

  if (surfaceId === "provider_show") {
    return {
      navigation: providerNavigation("Provider"),
      trusted_surface: {
        navigation: providerNavigation("Provider"),
        provider: {
          page_id: "comms-provider-show-page",
          display_name: "Simulator",
          provider_id: "provider-1",
          simulated_badge: { id: "simulated-provider-badge", label: "Simulated" },
          version: "v1",
          summary_tiles: [],
        },
        actions: {
          validate: { id: "validate-provider-button", label: "Validate", disabled: false },
          sync: { id: "sync-provider-button", label: "Sync", disabled: false },
          archive: { id: "archive-provider-button", label: "Archive", confirm: "Archive?", disabled: false },
        },
        profiles: {
          service: { id: "service", heading: "Service", subtitle: "", empty: true, empty_copy: "", table_id: "service-table", table_body_id: "service-body", columns: [] },
          delivery: { id: "delivery", heading: "Delivery", subtitle: "", empty: true, empty_copy: "", table_id: "delivery-table", table_body_id: "delivery-body", columns: [] },
        },
        details: {
          configuration: { id: "configuration", title: "Configuration", rows: [] },
          delivery_policy: { id: "policy", title: "Policy", rows: [] },
          capabilities: { id: "capabilities", title: "Capabilities", empty: true, empty_copy: "", items: [] },
          version_history: { id: "history", title: "History", stream_id: "history" },
        },
        diagnostics: { id: "diagnostics", label: "Diagnostics", json_id: "diagnostics-json", rows: [], json: "{}" },
        service_profiles: [],
        delivery_profiles: [],
        provider_versions: [],
      },
    };
  }

  return {
    navigation: {
      fallback_href: `/missions/mission-1/comms/${surfaceId}`,
      breadcrumbs: [
        { label: "Firebird", href: "/missions/mission-1" },
        { label: "Comms", href: "/missions/mission-1/comms" },
        { label: surfaceId, href: null },
      ],
    },
    trusted_surface: {
      id: `comms-${surfaceId.replaceAll("_", "-")}-surface`,
      title: surfaceId,
      empty: true,
      items: [],
      findings: [],
      finding_groups: [],
      status: "ready",
    },
  };
}

function providerFormPayload() {
  const keys = [
    "display_name",
    "provider_account_grant_id",
    "permitted_resource_refs",
    "policy_mode",
    "maximum_earlier_start_shift_seconds",
    "maximum_later_start_shift_seconds",
    "maximum_earlier_end_shift_seconds",
    "maximum_later_end_shift_seconds",
    "minimum_retained_duration_seconds",
    "approved_station_substitutions",
    "deadline_behavior",
  ];
  const fields = Object.fromEntries(
    keys.map((key) => [
      key,
      { key, id: `provider_${key}`, name: `provider[${key}]`, type: "text", label: key, required: false, placeholder: null, min: null, options: [], value: "" },
    ]),
  );
  return {
    id: "mission-provider-form",
    sections: {
      binding: { id: "binding", number: "01", title: "Binding", field_keys: ["display_name", "provider_account_grant_id"] },
      resource_scope: { id: "resource", number: "02", title: "Resource", field_keys: ["permitted_resource_refs"] },
      delivery_policy: { id: "policy", number: "03", title: "Policy", field_keys: ["policy_mode", "deadline_behavior"] },
    },
    fields,
    conditional: {
      approval_guidance: { id: "approval", active: false, visible_when: { field: "policy_mode", equals: "approval_required" }, text: "" },
      bounded_policy: { id: "bounded", active: false, visible_when: { field: "policy_mode", equals: "bounded_automatic" }, field_keys: [] },
    },
    actions: { submit: { id: "submit", label: "Create" }, cancel: { id: "cancel", label: "Cancel", href: "/comms/providers" } },
  };
}

function providerNavigation(label: string) {
  return {
    fallback_href: "/missions/mission-1/comms/providers",
    breadcrumbs: [
      { label: "Firebird", href: "/missions/mission-1" },
      { label: "Comms", href: "/missions/mission-1/comms" },
      { label, href: null },
    ],
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
