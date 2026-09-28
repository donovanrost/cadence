import { producerFixture } from "../../../../../test-support/producer-fixture";
import {
  jsonFixture,
  fixtureRecord,
  fixtureString,
} from "../../../../../test-support/json-fixture";
import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import ConfigurationSurface from "./ConfigurationSurface.vue";
import { admitConfiguration, type ConfigurationPresentation } from "./contracts";

function page(): ConfigurationPresentation {
  return {
    contract_version: 1,
    review: {
      configuration_token: "a".repeat(64),
      mission_token: "b".repeat(64),
      total_count: 0,
      truncated: false,
      configurations: [],
      packet_inputs: [],
    },
    context: { organization_id: "org", mission_id: "mission", spacecraft_id: "spacecraft" },
    configuration: null,
    page: {
      id: "spacecraft-telemetry-decom-page",
      title: "Telemetry Decom",
      subtitle: "Packet configuration",
      breadcrumbs: [],
    },
    card: { id: "telemetry-decom-card" },
    status: {
      state: "not_configured",
      tone: "blocked",
      label: "Not configured",
      description: "Save a catalog revision",
      saved_label: null,
    },
    revision: {
      form_id: "telemetry-decom-revision-form",
      field: {
        id: "telemetry-decom-revision-select",
        name: "catalog_revision_id",
        label: "Catalog revision",
        value: "",
        options: [
          { label: "Revision one", value: "revision-1" },
          { label: "Revision two", value: "revision-2" },
        ],
      },
      action: { id: "telemetry-decom-save-revision", label: "Use revision" },
    },
    no_revisions: null,
    packet_handoff: null,
    preview: null,
    preflight: {
      id: "telemetry-decom-preflight",
      checks_id: "telemetry-decom-preflight-checks",
      state: "blocked",
      activation_ready: false,
      check_count: 1,
      application_version: 1,
      summary: "Configuration required",
      label: "Blocked",
      checks: [
        {
          id: "telemetry-decom-check-configuration",
          check_id: "configuration",
          category: "configuration",
          state: "blocked",
          title: "Configuration required",
          detail: "Choose a revision",
          value: null,
        },
      ],
    },
    pending_activation: null,
    lifecycle_actions: { empty_message: "Save configuration first", enable: null, disable: null },
  };
}

const expected = {
  scope: "spacecraft",
  organizationId: "org",
  missionId: "mission",
  spacecraftId: "spacecraft",
};

test("admits the versioned configuration and rejects scope, identity, readiness and URL substitutions", () => {
  const p = page();
  expect(admitConfiguration(p, expected)).toEqual(p);
  for (const mutate of [
    (p: unknown) => (fixtureRecordAt(p).contract_version = 2),
    (p: unknown) => delete fixtureRecordAt(p).review,
    (p: unknown) => (fixtureRecordAt(p, "review").configuration_token = "foreign"),
    (p: unknown) => (fixtureRecordAt(p, "review").total_count = 2),
    (p: unknown) => (fixtureRecordAt(p, "review").mission_token = null),
    (p: unknown) => (fixtureRecordAt(p, "context").spacecraft_id = "foreign"),
    (p: unknown) => (fixtureRecordAt(p, "preflight").activation_ready = true),
    (p: unknown) => (fixtureRecordAt(p, "preflight").check_count = 3),
    (p: unknown) =>
      fixtureArrayAt(p, "revision", "field", "options").push(
        fixtureArrayAt(p, "revision", "field", "options")[0],
      ),
    (p: unknown) =>
      fixtureArrayAt(p, "page", "breadcrumbs").push({
        id: "foreign",
        label: "Foreign",
        href: "/missions/other",
      }),
    (p: unknown) => (fixtureRecordAt(p, "preflight").checks = []),
    (p: unknown) => (fixtureRecordAt(p, "revision", "field").value = "missing"),
  ]) {
    const bad = structuredClone(p);
    mutate(bad);
    expect(admitConfiguration(bad, expected)).toBeNull();
    const w = mount(ConfigurationSurface, { attrs: { ...bad, hostContext: expected } });
    expect(w.find("#telemetry-decom-contract-unavailable").exists()).toBe(true);
    expect(w.find("form").exists()).toBe(false);
    w.unmount();
  }
});

test("the first configuration is reachable and choosing a revision does not save until submit", async () => {
  const w = mount(ConfigurationSurface, { attrs: { ...page(), hostContext: expected } });
  expect(w.get("#telemetry-decom-save-revision").attributes("disabled")).toBeDefined();
  await w.get("#telemetry-decom-revision-select").setValue("revision-2");
  expect(w.emitted("save_catalog_revision")).toBeUndefined();
  await w.get("#telemetry-decom-revision-form").trigger("submit");
  expect(w.emitted("save_catalog_revision")).toEqual([
    [{ catalog_revision_id: "revision-2", handled_apids: [], expected_review: "a".repeat(64) }],
  ]);
  await w.setProps({ busy: true });
  expect(w.get("#telemetry-decom-save-revision").attributes("disabled")).toBeDefined();
  await w.get("#telemetry-decom-revision-form").trigger("submit");
  expect(w.emitted("save_catalog_revision")).toHaveLength(1);
  w.unmount();
});

test("refresh retains a revision draft and requires explicit review when the saved revision changes", async () => {
  const p = page();
  const w = mount(ConfigurationSurface, { attrs: p });
  await w.get("#telemetry-decom-revision-select").setValue("revision-2");
  const fresh = structuredClone(p);
  fresh.configuration = {
    catalog_revision_id: "revision-1",
    source_endpoint_id: "endpoint",
    configuration_version: 1,
    enabled: true,
    handled_apids: [],
  };
  required(fresh.revision).field.value = "revision-1";
  fresh.review.configuration_token = "c".repeat(64);
  await w.setProps(fresh);
  expect((w.get("#telemetry-decom-revision-select").element as HTMLSelectElement).value).toBe(
    "revision-2",
  );
  expect(w.get("#telemetry-decom-save-revision").attributes("disabled")).toBeDefined();
  await w.get("#telemetry-decom-stale-revision button").trigger("click");
  expect((w.get("#telemetry-decom-revision-select").element as HTMLSelectElement).value).toBe(
    "revision-1",
  );
  await w.get("#telemetry-decom-revision-select").setValue("revision-2");
  vi.stubGlobal(
    "confirm",
    vi.fn(() => false),
  );
  await w.get("#telemetry-decom-revision-form").trigger("submit");
  expect(w.emitted("save_catalog_revision")).toBeUndefined();
  vi.unstubAllGlobals();
  w.unmount();
});

const producer = producerFixture("CADENCE_DECOM", import.meta.url);
test.skipIf(!producer.available)(
  "producer supplied configuration mounts the public feature and emits the selected revision",
  async () => {
    const supplied = jsonFixture(producer.read());
    expect(admitConfiguration(supplied.page)).not.toBeNull();
    const w = mount(ConfigurationSurface, { attrs: fixtureRecord(supplied.page) });
    await w.get("#telemetry-decom-revision-select").setValue(fixtureString(supplied.revision_id));
    expect(w.emitted("save_catalog_revision")).toBeUndefined();
    await w.get("#telemetry-decom-revision-form").trigger("submit");
    await flushPromises();
    const events = required(w.emitted("save_catalog_revision"));
    expect(events).toHaveLength(1);
    process.stdout.write("CADENCE_DECOM_INPUT=" + JSON.stringify(required(events[0])[0]) + "\n");
    w.unmount();
  },
);

test("same-revision configuration changes retain the draft and reject save until review", async () => {
  const p = page();
  const w = mount(ConfigurationSurface, { attrs: p });
  await w.get("#telemetry-decom-revision-select").setValue("revision-2");
  await w.setProps({ review: { ...p.review, configuration_token: "c".repeat(64) } });
  expect(w.find("#telemetry-decom-stale-revision").exists()).toBe(true);
  await w.get("#telemetry-decom-revision-form").trigger("submit");
  expect(w.emitted("save_catalog_revision")).toBeUndefined();
  await w.get("#telemetry-decom-stale-revision button").trigger("click");
  await w.get("#telemetry-decom-revision-select").setValue("revision-2");
  await w.get("#telemetry-decom-revision-form").trigger("submit");
  expect(w.emitted("save_catalog_revision")?.[0]?.[0]).toMatchObject({
    expected_review: "c".repeat(64),
  });
  w.unmount();
});

test("mission submission requires review and a refresh cannot silently acknowledge another spacecraft change", async () => {
  const p = page();
  p.configuration = {
    catalog_revision_id: "revision-1",
    source_endpoint_id: "endpoint",
    configuration_version: 1,
    enabled: true,
    handled_apids: [],
  };
  required(p.revision).field.value = "revision-1";
  p.review.total_count = 1;
  p.review.configurations = [
    {
      spacecraft_id: "spacecraft",
      spacecraft_name: "Aurora",
      source_endpoint_name: "Aurora command endpoint",
      ...p.configuration,
    },
  ];
  p.preflight.state = "ready";
  p.preflight.activation_ready = true;
  required(p.preflight.checks[0]).state = "ready";
  p.lifecycle_actions = {
    empty_message: null,
    disable: null,
    enable: {
      id: "request-mission",
      action_id: "request_activation",
      event: "enable",
      label: "Request mission changes",
      variant: "primary",
      effect: "configuration",
      execution: "approval_required",
      confirmation: null,
      disabled: false,
    },
  };
  const w = mount(ConfigurationSurface, { attrs: p });
  expect(w.get("#request-mission").attributes("disabled")).toBeDefined();
  await w.get("#telemetry-decom-review-confirmation").setValue(true);
  await w.get("#request-mission").trigger("click");
  expect(w.emitted("enable")).toEqual([
    [{ "action-id": "request_activation", expected_review: "b".repeat(64) }],
  ]);
  const review = {
    ...p.review,
    mission_token: "c".repeat(64),
    total_count: 2,
    configurations: [
      ...p.review.configurations,
      {
        ...p.review.configurations[0],
        spacecraft_id: "other-spacecraft",
        spacecraft_name: "Kestrel",
      },
    ],
  };
  await w.setProps({ review });
  expect(w.get("#telemetry-decom-mission-review").text()).toContain("Kestrel");
  expect(w.get("#telemetry-decom-mission-review").text()).not.toContain("other-spacecraft");
  expect(w.get("#request-mission").attributes("disabled")).toBeDefined();
  await w.get("#request-mission").trigger("click");
  expect(w.emitted("enable")).toHaveLength(1);
  await w.get("#telemetry-decom-stale-mission button").trigger("click");
  expect(w.get("#request-mission").attributes("disabled")).toBeDefined();
  await w.get("#telemetry-decom-review-confirmation").setValue(true);
  await w.get("#request-mission").trigger("click");
  expect(w.emitted("enable")?.[1]?.[0]).toMatchObject({ expected_review: "c".repeat(64) });
  w.unmount();
});
