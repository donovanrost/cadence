import { required } from "../../../test-support/required";
import { describe, expect, it } from "vite-plus/test";
import {
  APPLICATION_HOST_CONTRACT,
  assertHostContext,
  assertFrontendApplicationCatalog,
  assertCompatibleManifest,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  FRONTEND_APPLICATION_CATALOG_SCHEMA,
  isHostContext,
} from "./index";

const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: { packageId: "cadence.telemetry-applications", version: 1, trust: "first_party" },
  compatibility: {
    cadenceApplicationContract: 1,
    cadenceSurfaceContract: 1,
    cadenceFederatedRendererContract: 1,
    cadenceThemeContract: 1,
  },
  application: {
    applicationKey: "telemetry_decom",
    version: 1,
    displayName: "Telemetry Decom",
    description: "Decode selected packet inputs.",
    installableScopes: ["spacecraft"],
  },
  surfaces: [
    {
      surfaceId: "packet_bindings",
      version: 1,
      purpose: "configuration",
      scope: "spacecraft",
      placement: "application_workspace",
      navigation: { label: "Packet bindings", order: 20 },
      dataContract: { id: "cadence.packet_bindings.manage", version: 1 },
      actions: ["save_packet_bindings"],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
  ],
});

describe("first-party federated application manifests", () => {
  it("accepts the current host and surface contracts", () => {
    expect(() => assertCompatibleManifest(manifest)).not.toThrow();
  });

  it("accepts collection surfaces used by server application definitions", () => {
    const collectionManifest = {
      ...manifest,
      surfaces: [{ ...required(manifest.surfaces[0]), purpose: "collection" as const }],
    };

    expect(() => defineApplicationManifest(collectionManifest)).not.toThrow();
    expect(() => assertCompatibleManifest(collectionManifest)).not.toThrow();
  });

  it("rejects third-party code at the trusted renderer boundary", () => {
    expect(() =>
      assertCompatibleManifest({
        ...manifest,
        package: { ...manifest.package, trust: "third_party" },
      }),
    ).toThrow("package declaration");
  });

  it("rejects remotes built for an incompatible design-system contract", () => {
    expect(() =>
      assertCompatibleManifest({
        ...manifest,
        compatibility: { ...manifest.compatibility, cadenceThemeContract: 2 },
      }),
    ).toThrow("compatibility declaration");
  });

  it("rejects duplicate surface identifiers", () => {
    expect(() =>
      assertCompatibleManifest({
        ...manifest,
        surfaces: [manifest.surfaces[0], manifest.surfaces[0]],
      }),
    ).toThrow("unique identifiers");
  });
});

describe("tagged host contexts", () => {
  const actor = { displayName: "Mara Vance", permissions: ["applications:view"] };

  it.each([
    [
      "organization",
      {
        scope: "organization",
        organizationId: "org-1",
        missionId: null,
        missionName: null,
        spacecraftId: null,
        spacecraftName: null,
        actor,
      },
    ],
    [
      "user/account",
      {
        scope: "user",
        organizationId: null,
        userId: "user-1",
        missionId: null,
        missionName: null,
        spacecraftId: null,
        spacecraftName: null,
        actor,
      },
    ],
    [
      "admin/global",
      {
        scope: "admin",
        organizationId: null,
        missionId: null,
        missionName: null,
        spacecraftId: null,
        spacecraftName: null,
        actor,
      },
    ],
  ])("accepts the %s context without a mission identity", (_label, context) => {
    expect(isHostContext(context)).toBe(true);
    expect(() => assertHostContext(context)).not.toThrow();
  });

  it("accepts mission context without inventing spacecraft identity", () => {
    const context = {
      scope: "mission",
      organizationId: "org-1",
      missionId: "mission-1",
      missionName: "Firebird",
      spacecraftId: null,
      spacecraftName: null,
      actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
    };

    expect(isHostContext(context)).toBe(true);
    expect(() => assertHostContext(context)).not.toThrow();
  });

  it("rejects a mission context that fabricates spacecraft values", () => {
    expect(() =>
      assertHostContext({
        scope: "mission",
        organizationId: "org-1",
        missionId: "mission-1",
        missionName: "Firebird",
        spacecraftId: "spacecraft-1",
        spacecraftName: "FB-1",
        actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
      }),
    ).toThrow("Host context is invalid");
  });

  it("requires complete spacecraft identity for spacecraft context", () => {
    expect(
      isHostContext({
        scope: "spacecraft",
        organizationId: "org-1",
        missionId: "mission-1",
        missionName: "Firebird",
        spacecraftId: null,
        spacecraftName: null,
        actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
      }),
    ).toBe(false);
  });

  it("rejects every wrong-scope resource identity", () => {
    expect(
      isHostContext({
        scope: "organization",
        organizationId: "org-1",
        missionId: "mission-1",
        missionName: "Firebird",
        spacecraftId: null,
        spacecraftName: null,
        actor,
      }),
    ).toBe(false);
    expect(
      isHostContext({
        scope: "user",
        organizationId: null,
        userId: "user-1",
        missionId: "mission-1",
        missionName: "Firebird",
        spacecraftId: null,
        spacecraftName: null,
        actor,
      }),
    ).toBe(false);
    expect(
      isHostContext({
        scope: "admin",
        organizationId: "org-1",
        missionId: null,
        missionName: null,
        spacecraftId: null,
        spacecraftName: null,
        actor,
      }),
    ).toBe(false);
  });
});

describe("host-approved frontend catalogs", () => {
  const catalog = {
    schema: FRONTEND_APPLICATION_CATALOG_SCHEMA,
    hostContract: APPLICATION_HOST_CONTRACT,
    generatedAt: "2026-08-22T20:00:00.000Z",
    session: {
      sessionId: "session-1",
      csrfToken: "csrf-1",
      bridgeBaseUrl: "/api/cadence/application-host/v1",
      context: {
        scope: "spacecraft",
        organizationId: "org-1",
        missionId: "mission-1",
        missionName: "Firebird",
        spacecraftId: "spacecraft-1",
        spacecraftName: "FB-1",
        actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
      },
    },
    applications: [
      {
        applicationKey: "telemetry_decom",
        applicationVersion: 1,
        displayName: "Telemetry Decom",
        description: "Decode selected packet inputs.",
        package: { packageId: "cadence.telemetry-applications", version: 1 },
        surface: manifest.surfaces[0],
        release: {
          federation: "module_federation",
          releaseId: "2026.08.22.2",
          remoteName: "telemetry_decom_current_2026_08_22_2",
          manifestUrl: "http://127.0.0.1:4174/releases/current/mf-manifest.json",
          exposedModule: "./Application",
        },
      },
    ],
  };

  it("accepts an exact first-party release selected by the host", () => {
    expect(() => assertFrontendApplicationCatalog(catalog)).not.toThrow();
  });

  it("rejects an insecure non-loopback remote origin", () => {
    expect(() =>
      assertFrontendApplicationCatalog({
        ...catalog,
        applications: [
          {
            ...catalog.applications[0],
            release: {
              ...catalog.applications[0]?.release,
              manifestUrl: "http://applications.example.com/mf-manifest.json",
            },
          },
        ],
      }),
    ).toThrow("invalid application");
  });

  it("rejects an unknown federation transport", () => {
    expect(() =>
      assertFrontendApplicationCatalog({
        ...catalog,
        applications: [
          {
            ...catalog.applications[0],
            release: {
              ...catalog.applications[0]?.release,
              federation: "script_tag",
            },
          },
        ],
      }),
    ).toThrow("invalid application");
  });

  it("rejects duplicate application identities", () => {
    expect(() =>
      assertFrontendApplicationCatalog({
        ...catalog,
        applications: [catalog.applications[0], catalog.applications[0]],
      }),
    ).toThrow("duplicate application key");
  });
});
