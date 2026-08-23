import {
  APPLICATION_HOST_CONTRACT,
  type CatalogApplication,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import { describe, expect, it, vi } from "vite-plus/test";
import { loadFederatedApplication, type FederatedRuntime } from "./remote-loader";

const application: CatalogApplication = {
  applicationKey: "contract_probe",
  applicationVersion: 1,
  displayName: "Contract Probe",
  description: "Fixture remote",
  package: { packageId: "cadence.frontend-fixtures", version: 1 },
  surface: {
    surfaceId: "runtime_contracts",
    version: 1,
    purpose: "overview",
    scope: "spacecraft",
    placement: "application_workspace",
    navigation: { label: "Runtime contracts", order: 90 },
    dataContract: { id: "cadence.contract_probe.snapshot", version: 1 },
    actions: [],
    renderer: { kind: "federated-vue", exposedModule: "./Application" },
  },
  release: {
    federation: "module_federation",
    releaseId: "2026.08.22.1",
    remoteName: "contract_probe_current_2026_08_22_1",
    manifestUrl: "http://127.0.0.1:4175/mf-manifest.json",
    exposedModule: "./Application",
  },
};

const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: { packageId: "cadence.frontend-fixtures", version: 1, trust: "first_party" },
  compatibility: {
    cadenceApplicationContract: 1,
    cadenceSurfaceContract: 1,
    cadenceFederatedRendererContract: 1,
    cadenceThemeContract: 1,
  },
  application: {
    applicationKey: "contract_probe",
    version: 1,
    displayName: "Contract Probe",
    description: "Fixture remote",
    installableScopes: ["spacecraft"],
  },
  surfaces: [application.surface],
});

describe("the generic federated application loader", () => {
  it("registers and loads the exact release approved by the catalog", async () => {
    const load = vi.fn(async () => ({ manifest, default: { name: "ContractProbe" } }));
    const runtime: FederatedRuntime = { load };

    await loadFederatedApplication(application, runtime);

    expect(load).toHaveBeenCalledWith(application);
  });

  it("rejects a remote that claims a different application version", async () => {
    const runtime: FederatedRuntime = {
      load: vi.fn(async () => ({
        manifest,
        default: { name: "ContractProbe" },
      })),
    };

    await expect(
      loadFederatedApplication({ ...application, applicationVersion: 2 }, runtime),
    ).rejects.toThrow("does not match the host-approved application contract");
  });

  it("contains federation transport details behind a stable host message", async () => {
    const runtime: FederatedRuntime = {
      load: vi.fn(async () => {
        throw new Error("RUNTIME-003 internal loader details");
      }),
    };

    await expect(loadFederatedApplication(application, runtime)).rejects.toThrow(
      "Approved release 2026.08.22.1 could not be loaded.",
    );
  });

  it("fails closed when a catalog release uses an unregistered transport", async () => {
    const unsupportedApplication: CatalogApplication = {
      ...application,
      release: { ...application.release, federation: "native_federation" },
    };

    try {
      await loadFederatedApplication(unsupportedApplication);
      throw new Error("Expected the unsupported release to be rejected.");
    } catch (reason) {
      expect(reason).toBeInstanceOf(Error);
      if (!(reason instanceof Error)) return;

      expect(reason.message).toBe("Approved release 2026.08.22.1 could not be loaded.");
      expect(reason.cause).toMatchObject({
        message: "Federation transport native_federation is not supported by this host.",
      });
    }
  });
});
