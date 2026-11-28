import { describe, expect, it } from "vite-plus/test";
import {
  assertReleaseMatchesModule,
  type CatalogApplication,
  type FederatedApplicationModule,
  type FederatedSurfaceDefinition,
} from "@cadence/plugin-sdk";
import { manifest as opsConsole } from "../../ops-console/src/federated-application";

type SurfaceRow = readonly [
  surfaceId: string,
  purpose: FederatedSurfaceDefinition["purpose"],
  scope: FederatedSurfaceDefinition["scope"],
  placement: FederatedSurfaceDefinition["placement"],
  label: string,
  order: number,
  dataContractId: string,
  actions: readonly string[],
];

const surface = ([
  surfaceId,
  purpose,
  scope,
  placement,
  label,
  order,
  dataContractId,
  actions,
]: SurfaceRow): FederatedSurfaceDefinition => ({
  surfaceId,
  version: 1,
  purpose,
  scope,
  placement,
  navigation: { label, order },
  dataContract: { id: dataContractId, version: 1 },
  actions,
  renderer: { kind: "federated-vue", exposedModule: "./Application" },
});

const expected = [
  {
    name: "ops_console",
    manifest: opsConsole,
    package: { packageId: "cadence.ops_console", version: 1 },
    displayName: "Ops Console",
    description: "Mission operations, dashboard runtime, evidence, and control surfaces.",
    installableScopes: ["mission"] as const,
    releaseId: () => "ops-console-v1",
    surfaces: [
      [
        "workspace",
        "overview",
        "mission",
        "application_workspace",
        "Ops Console",
        10,
        "cadence.ops.workspace",
        [],
      ],
      [
        "data_sources",
        "configuration",
        "mission",
        "ops_workspace",
        "Data Sources",
        10,
        "cadence.ops.data_sources",
        [
          "register-source",
          "change-binding",
          "disable-source",
          "enable-source",
          "reconcile-tsdb-backend",
          "deprovision-tsdb-backend",
          "provision-tsdb-backend",
          "probe-source",
          "rotate-source-credential",
          "retry-deployment-run",
          "requeue-deployment-run",
        ],
      ],
      [
        "data_source_registration",
        "configuration",
        "mission",
        "ops_workspace",
        "Register Data Source",
        10,
        "cadence.ops.data_source_registration",
        ["register-source"],
      ],
      [
        "data_source_settings",
        "configuration",
        "mission",
        "ops_workspace",
        "Data Source Settings",
        10,
        "cadence.ops.data_source_settings",
        [
          "change-binding",
          "disable-source",
          "enable-source",
          "reconcile-tsdb-backend",
          "deprovision-tsdb-backend",
          "provision-tsdb-backend",
          "probe-source",
          "rotate-source-credential",
          "retry-deployment-run",
          "requeue-deployment-run",
        ],
      ],
    ] as SurfaceRow[],
  },
] as const;

function expectedSurfaces(rows: readonly SurfaceRow[]) {
  return rows.map(surface);
}

function dtoFor(
  application: (typeof expected)[number],
  surfaceDefinition: FederatedSurfaceDefinition,
): CatalogApplication {
  return {
    applicationKey: application.name,
    applicationVersion: 1,
    displayName: application.displayName,
    description: application.description,
    package: application.package,
    surface: surfaceDefinition,
    release: {
      federation: "module_federation",
      releaseId: application.releaseId(),
      remoteName: `cadence_${application.name}`,
      manifestUrl: `/assets/application-host/${application.name.replaceAll("_", "-")}/mf-manifest.json`,
      exposedModule: "./Application",
    },
  };
}

describe("first-party federated manifest parity", () => {
  it("matches the exact host DTO contract for every in-scope published surface", () => {
    let surfaceCount = 0;

    for (const application of expected) {
      const manifestSurfaces = expectedSurfaces(application.surfaces);

      expect({
        applicationKey: application.manifest.application.applicationKey,
        applicationVersion: application.manifest.application.version,
        displayName: application.manifest.application.displayName,
        description: application.manifest.application.description,
        installableScopes: application.manifest.application.installableScopes,
        package: application.manifest.package,
      }).toEqual({
        applicationKey: application.name,
        applicationVersion: 1,
        displayName: application.displayName,
        description: application.description,
        installableScopes: application.installableScopes,
        package: { ...application.package, trust: "first_party" },
      });
      expect(application.manifest.surfaces).toEqual(manifestSurfaces);

      for (const surfaceDefinition of manifestSurfaces) {
        surfaceCount += 1;
        expect(() =>
          assertReleaseMatchesModule(dtoFor(application, surfaceDefinition), {
            manifest: application.manifest,
            default: {},
          } satisfies FederatedApplicationModule),
        ).not.toThrow();
      }
    }

    // Sweep row 2: spacecraft's new / profile_new / edit forms left (40 → 37); the
    // organization-admin notifications page left (37 → 36); the ops-console
    // activation_requests surface left (36 → 35). #671: the Mission Catalog (8) and Spacecraft (9)
    // remotes left (35 → 18). #702: the ops-console data_operations and data_operations_manage
    // surfaces left (18 → 16). #672: the Organization Admin remote's notifications bell left
    // (16 → 15). #666/#142/#143: the ops-console timeline, telemetry_explore and alarms surfaces
    // left (15 → 12). #665: the ops-console planning and contacts surfaces left (12 → 5). #708:
    // the ops-console commands surface left (5 → 4).
    expect(surfaceCount).toBe(4);
  });
});
