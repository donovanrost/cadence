import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type { HostBridge, HostQueryRequest, MissionHostContext } from "@cadence/plugin-sdk";
import CommsApplication from "./CommsApplication.vue";

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
] as const;

describe("Comms canonical federated application", () => {
  it.each(surfaceIds)("queries and renders the %s surface through Phoenix", async (surfaceId) => {
    const query = vi.fn<TestQuery>().mockResolvedValue(surfacePayload(surfaceId));
    const wrapper = mount(CommsApplication, {
      props: { context, bridge: bridgeFor(query), surfaceId },
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
      props: { context, bridge: bridgeFor(query), surfaceId: "validation" },
    });

    await flushPromises();
    expect(wrapper.find("#comms-application-error").exists()).toBe(true);

    await wrapper.get("#retry-comms-application").trigger("click");
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#comms-application-error").exists()).toBe(false);
    wrapper.unmount();
  });
});

type TestQuery = (request: HostQueryRequest) => Promise<unknown>;

function bridgeFor(query: TestQuery): HostBridge {
  return {
    query: async <TResult>(request: HostQueryRequest) => (await query(request)) as TResult,
    execute: vi.fn(),
    subscribe: vi.fn(),
  };
}

function surfacePayload(surfaceId: (typeof surfaceIds)[number]) {
  if (surfaceId === "overview") return overviewPayload();

  return {
    navigation: {
      fallback_href: `/missions/mission-1/comms/${surfaceId}`,
      breadcrumbs: [
        { label: "Firebird", href: "/missions/mission-1" },
        { label: "Comms", href: "/missions/mission-1/comms" },
        { label: surfaceId, href: null },
      ],
    },
    data: {
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

function overviewPayload() {
  return {
    navigation: {
      fallback_href: "/missions/mission-1/comms",
      breadcrumbs: [
        { label: "Firebird", href: "/missions/mission-1" },
        { label: "Comms", href: null },
      ],
    },
    data: {
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
