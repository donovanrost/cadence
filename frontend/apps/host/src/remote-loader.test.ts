import {
  APPLICATION_HOST_CONTRACT,
  type CatalogApplication,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import { describe, expect, it, vi } from "vite-plus/test";
import {
  createReleaseAwareRuntime,
  loadFederatedApplication,
  type FederatedRuntime,
  type ReleaseAwareModuleFederationClient,
} from "./remote-loader";

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
  it("reuses per-release runtimes across N-1 -> N -> N-1 without stale modules", async () => {
    const clients: Array<{
      registerRemotes: ReturnType<typeof vi.fn>;
      loadRemote: ReturnType<typeof vi.fn>;
    }> = [];
    const createClient = vi.fn((identity: string) => {
      let registration: { entry: string; type: "module" } | undefined;
      const registerRemotes = vi.fn(
        (remotes: Array<{ name: string; entry: string; type: "module" }>) => {
          registration = remotes[0];
        },
      );
      const loadRemote = vi.fn(async <T = unknown>(id: string): Promise<T | null> => {
        if (!registration) throw new Error(`missing registration for ${id}`);
        return { identity, entry: registration.entry } as T;
      });
      clients.push({ registerRemotes, loadRemote });
      return { registerRemotes, loadRemote } as ReleaseAwareModuleFederationClient;
    });
    const runtime = createReleaseAwareRuntime(createClient);
    const release = (releaseId: string) => ({
      ...application,
      release: {
        ...application.release,
        releaseId,
        manifestUrl: `http://127.0.0.1:4175/${releaseId}/mf-manifest.json`,
      },
    });

    const nMinus1 = await runtime.load(release("sha256:" + "1".repeat(64)));
    const n = await runtime.load(release("sha256:" + "2".repeat(64)));
    const rolledBack = await runtime.load(release("sha256:" + "1".repeat(64)));

    expect(nMinus1).toMatchObject({
      entry:
        "http://127.0.0.1:4175/sha256:1111111111111111111111111111111111111111111111111111111111111111/mf-manifest.json",
    });
    expect(n).toEqual({
      identity: expect.any(String),
      entry:
        "http://127.0.0.1:4175/sha256:2222222222222222222222222222222222222222222222222222222222222222/mf-manifest.json",
    });
    expect(rolledBack).toEqual(nMinus1);
    expect(createClient).toHaveBeenCalledTimes(2);
    expect(new Set(createClient.mock.calls.map(([identity]) => identity)).size).toBe(2);
    expect(clients[0].registerRemotes).toHaveBeenCalledTimes(1);
    expect(clients[1].registerRemotes).toHaveBeenCalledTimes(1);
    expect(clients[0].loadRemote).toHaveBeenCalledTimes(2);
    expect(clients[1].loadRemote).toHaveBeenCalledTimes(1);
    expect(() => runtime.load(release("sha256:" + "3".repeat(64)))).toThrow(
      "current and fallback release already",
    );
    expect(createClient).toHaveBeenCalledTimes(2);
  });

  it("registers and loads the exact release approved by the catalog", async () => {
    const load = vi.fn(async () => ({ manifest, default: { name: "ContractProbe" } }));
    const runtime: FederatedRuntime = { load };

    await loadFederatedApplication(application, runtime);

    expect(load).toHaveBeenCalledWith(application, { signal: expect.any(AbortSignal) });
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

  it("bounds a late runtime result and never returns it after the deadline", async () => {
    let resolveLoad: ((value: unknown) => void) | undefined;
    const runtime: FederatedRuntime = {
      load: vi.fn(
        () =>
          new Promise((resolve) => {
            resolveLoad = resolve;
          }),
      ),
    };

    const pending = loadFederatedApplication(application, runtime, { timeoutMs: 10 });
    await expect(pending).rejects.toThrow(
      "Approved release 2026.08.22.1 could not be loaded.",
    );

    resolveLoad?.({ manifest, default: { name: "LateRemote" } });
    await Promise.resolve();
    expect(runtime.load).toHaveBeenCalledTimes(1);
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
