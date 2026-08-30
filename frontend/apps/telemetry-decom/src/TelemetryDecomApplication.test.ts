import "./env.d.ts";

import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi, afterEach } from "vite-plus/test";
import type { HostContext } from "@cadence/plugin-sdk";
import ApplicationHost from "@cadence/cadence-web-vue/ApplicationHost.vue";
import TelemetryDecomApplication from "./TelemetryDecomApplication.vue";

const context: HostContext = {
  scope: "spacecraft",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: "spacecraft-1",
  spacecraftName: "FB-1",
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
};

afterEach(() => vi.restoreAllMocks());

describe("Telemetry Decom Phoenix host bridge", () => {
  it("queries packet bindings v1 and renders the canonical ApplicationHost DTO", async () => {
    const dto = applicationHostDto();
    const query = vi.fn().mockResolvedValue(dto);
    const action = vi.fn();
    const wrapper = mount(TelemetryDecomApplication, {
      props: { context, host: { query, action } },
    });

    expect(wrapper.find("#telemetry-decom-loading").exists()).toBe(true);
    await flushPromises();

    expect(query).toHaveBeenCalledWith({
      queryId: "cadence.packet_bindings.manage",
      version: 1,
      context,
    });
    expect(wrapper.find("#telemetry-decom-surface").exists()).toBe(true);
    expect(wrapper.find("#packet-bindings").exists()).toBe(true);
    expect(wrapper.find("#packet-group-1").exists()).toBe(true);
    expect(wrapper.text()).toContain("Canonical packet bindings");
    wrapper.unmount();
  });

  it("translates the canonical action event without changing its application_action map", async () => {
    vi.spyOn(globalThis.crypto, "randomUUID").mockReturnValue(
      "00000000-0000-4000-8000-000000000001",
    );
    const query = vi.fn().mockResolvedValue(applicationHostDto());
    const action = vi.fn().mockResolvedValue({ receiptId: "receipt-1" });
    const wrapper = mount(TelemetryDecomApplication, {
      props: { context, host: { query, action } },
    });

    await flushPromises();
    wrapper.findComponent(ApplicationHost).vm.$emit("application_action", {
      "action-id": "save_packet_bindings",
      application_action: {
        source_endpoint: "primary",
        selected_packet_ids: ["packet-1"],
      },
    });
    await flushPromises();

    expect(action).toHaveBeenCalledWith({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      actionId: "save_packet_bindings",
      application_action: {
        source_endpoint: "primary",
        selected_packet_ids: ["packet-1"],
      },
      context,
      idempotencyKey: "00000000-0000-4000-8000-000000000001",
    });
    wrapper.unmount();
  });

  it("refreshes the canonical surface after a successful action", async () => {
    const query = vi
      .fn()
      .mockResolvedValueOnce(applicationHostDto())
      .mockResolvedValueOnce(applicationHostDto("Refreshed packet bindings"));
    const action = vi.fn().mockResolvedValue({ receiptId: "receipt-1" });
    const wrapper = mount(TelemetryDecomApplication, {
      props: { context, host: { query, action } },
    });

    await flushPromises();
    wrapper.findComponent(ApplicationHost).vm.$emit("application_action", {
      "action-id": "save_packet_bindings",
      application_action: {
        source_endpoint: "primary",
        selected_packet_ids: ["packet-1"],
      },
    });
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain("Refreshed packet bindings");
    expect(wrapper.find("#telemetry-decom-action-notice").text()).toContain("refreshed");
    wrapper.unmount();
  });

  it("contains query failures and malformed DTOs as retryable loading errors", async () => {
    const query = vi.fn().mockRejectedValue(new Error("Phoenix query unavailable"));
    const wrapper = mount(TelemetryDecomApplication, {
      props: { context, host: { query, action: vi.fn() } },
    });

    await flushPromises();

    expect(wrapper.find("#telemetry-decom-error").text()).toContain("Phoenix query unavailable");
    expect(wrapper.find("#retry-telemetry-decom").exists()).toBe(true);
    wrapper.unmount();

    const malformedQuery = vi.fn().mockResolvedValue({ host: {} });
    const malformedWrapper = mount(TelemetryDecomApplication, {
      props: { context, host: { query: malformedQuery, action: vi.fn() } },
    });

    await flushPromises();

    expect(malformedWrapper.find("#telemetry-decom-error").text()).toContain(
      "invalid ApplicationHost DTO",
    );
    malformedWrapper.unmount();
  });

  it("contains action failures and ignores unsupported form-change and table-page events", async () => {
    const query = vi.fn().mockResolvedValue(applicationHostDto());
    const action = vi.fn().mockRejectedValue(new Error("Phoenix action unavailable"));
    const wrapper = mount(TelemetryDecomApplication, {
      props: { context, host: { query, action } },
    });

    await flushPromises();
    const applicationHost = wrapper.findComponent(ApplicationHost);
    applicationHost.vm.$emit("application_form_change", {
      application_action: { ignored: "change" },
    });
    applicationHost.vm.$emit("application_table_page", { page: "2" });
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(1);
    expect(action).not.toHaveBeenCalled();

    applicationHost.vm.$emit("application_action", {
      "action-id": "save_packet_bindings",
      application_action: {
        source_endpoint: "primary",
        selected_packet_ids: ["packet-1"],
      },
    });
    await flushPromises();

    expect(action).toHaveBeenCalledTimes(1);
    expect(query).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#telemetry-decom-action-error").text()).toContain(
      "Phoenix action unavailable",
    );
    wrapper.unmount();
  });
});

function applicationHostDto(title = "Canonical packet bindings") {
  return {
    host: {
      dom_id: "telemetry-decom-host",
      application_key: "telemetry_decom",
      application_version: 1,
      application_installation_id: "installation-1",
      surface_id: "packet_bindings",
      renderer: "declarative",
    },
    navigation: null,
    declarative_surface: {
      id: "telemetry-decom-surface",
      page: { title, subtitle: "Server-owned spacecraft packet routing." },
      action_feedback: null,
      stats: [],
      diagnostics: null,
      form: null,
      packet_bindings: {
        id: "packet-bindings",
        activation_state: "ready",
        tone: "ready",
        tone_label: "Ready",
        state_label: "Configured",
        title: "Packet inputs",
        description: "Canonical packet input routing.",
        configured_version_label: "v1",
        applied_version_label: "v1",
        save_enabled: true,
        application_display_name: "Telemetry Decom",
        form: {
          id: "packet-bindings-form",
          hidden_fields: [],
          source_endpoint: {
            id: "packet-source-endpoint",
            field: "source_endpoint",
            name: "application_action[source_endpoint]",
            type: "select",
            value: "primary",
            errors: [],
            label: "Source endpoint",
            disabled: false,
            options: [{ label: "Primary", value: "primary", disabled: false }],
          },
          selected_packet_ids: ["packet-1"],
        },
        action: {
          id: "save-packet-bindings",
          action_id: "save_packet_bindings",
          label: "Save packet bindings",
          version: 1,
          intent: "save",
          scope: "spacecraft",
          effect: "persist",
          execution: "synchronous",
          confirmation: null,
          disabled: false,
        },
        instructions: {
          shared_input: "Changes are applied to the spacecraft input.",
          save_status: "Save to publish packet routing.",
        },
        empty: {
          id: "packet-bindings-empty",
          title: "No packet bindings",
          description: null,
        },
      },
      table: null,
      activity: null,
    },
    application_surface_rows: [],
    application_surface_activity: [],
    application_surface_packet_groups: [
      {
        id: "packet-group-1",
        __dom_id: "packet-group-1",
        packet_id: "packet-1",
        packet_name: "THERM",
        apid: 42,
        selector_summary: "APID 42",
        model_label: "Housekeeping",
        selected: true,
        expanded: false,
        selectable: true,
        state: "selected",
        reason: null,
        consumers: [],
        resources: [],
      },
    ],
  };
}
