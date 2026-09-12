import "./env.d.ts";
import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import {
  assertReleaseMatchesModule,
  type CatalogApplication,
  type HostContext,
  type HostBridge,
} from "@cadence/plugin-sdk";
import DerivedTelemetryApplication from "./DerivedTelemetryApplication.vue";
import { manifest } from "./derived-telemetry";
test("the separate derived exposure matches admission and passes immutable action keys through its feature port", async () => {
  const context: HostContext = {
    scope: "mission",
    organizationId: "org",
    missionId: "mission",
    missionName: "Nova",
    spacecraftId: null,
    spacecraftName: null,
    actor: { displayName: "Operator", permissions: ["operate_mission"] },
  };
  const application: CatalogApplication = {
    applicationKey: "derived_telemetry",
    applicationVersion: 1,
    displayName: manifest.application.displayName,
    description: manifest.application.description,
    package: { packageId: "cadence.telemetry-applications", version: 1 },
    surface: manifest.surfaces[0],
    release: {
      federation: "module_federation",
      releaseId: "ops-console-v1",
      remoteName: "cadence_ops_console",
      manifestUrl: "/assets/application-host/ops-console/mf-manifest.json",
      exposedModule: "./DerivedTelemetry",
    },
  };
  expect(() =>
    assertReleaseMatchesModule(application, { manifest, default: DerivedTelemetryApplication }),
  ).not.toThrow();
  const query = vi
      .fn<HostBridge["query"]>()
      .mockResolvedValue({ trusted_surface: { contract_version: 1 } }),
    execute = vi
      .fn<HostBridge["execute"]>()
      .mockResolvedValue({ receiptId: "receipt", completedAt: "2026-09-09T00:00:00Z", result: {} }),
    navigate = vi.fn();
  const w = mount(DerivedTelemetryApplication, {
    props: {
      application,
      surface: application.surface,
      context,
      bridge: {
        query: query as HostBridge["query"],
        execute: execute as HostBridge["execute"],
        navigate,
        subscribe: vi.fn(),
      },
    },
    global: {
      stubs: {
        DefinitionsSurface: {
          name: "DefinitionsSurface",
          props: ["document", "port", "hostContext"],
          template: "<span />",
        },
      },
    },
  });
  await flushPromises();
  const feature = w.findComponent({ name: "DefinitionsSurface" });
  expect(feature.props("document")).toEqual({ contract_version: 1 });
  expect(query).toHaveBeenCalledWith({
    queryId: "cadence.derived_telemetry.manage",
    version: 1,
    context,
  });
  const port = feature.props("port");
  const input = {
    point_id: "DERIVED.power",
    point_name: "Power",
    expression: "HK.voltage * 2",
    expected_definition_id: null,
    expected_version: 0,
  };
  await port.save(input, "same-key");
  expect(execute).toHaveBeenCalledWith({
    applicationKey: "derived_telemetry",
    applicationVersion: 1,
    surfaceId: "manage",
    surfaceVersion: 1,
    actionId: "save_definition",
    context,
    input,
    idempotencyKey: "same-key",
  });
  w.unmount();
});
