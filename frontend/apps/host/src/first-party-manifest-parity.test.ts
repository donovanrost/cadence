import { describe, expect, it } from "vite-plus/test";
import {
  assertReleaseMatchesModule,
  type CatalogApplication,
  type FederatedApplicationModule,
  type FederatedSurfaceDefinition,
} from "@cadence/plugin-sdk";
import { manifest as opsConsole } from "../../ops-console/src/federated-application";
import { manifest as organizationAdmin } from "../../organization-admin/src/federated-application";

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
        "contact_schedule",
        "operations",
        "mission",
        "ops_workspace",
        "Contact Schedule",
        10,
        "cadence.ops.contact_schedule",
        ["validate", "search", "reserve", "cancel"],
      ],
      [
        "contact_plan_show",
        "subject_detail",
        "mission",
        "ops_workspace",
        "Contact Plan",
        10,
        "cadence.ops.contact_plan_show",
        ["submit-plan", "approve-plan", "reject-plan", "execute-plan"],
      ],
      [
        "contact_detail",
        "subject_detail",
        "mission",
        "ops_workspace",
        "Contact Detail",
        10,
        "cadence.ops.contact_detail",
        ["approve-provider-change", "reject-provider-change", "acknowledge-provider-change"],
      ],
      [
        "contact_record",
        "subject_detail",
        "mission",
        "ops_workspace",
        "Contact Record",
        10,
        "cadence.ops.contact_record",
        [],
      ],
      [
        "fleet_planning",
        "operations",
        "mission",
        "ops_workspace",
        "Fleet Planning",
        10,
        "cadence.ops.fleet_planning",
        ["refresh-planning"],
      ],
      [
        "fleet_planning_new",
        "configuration",
        "mission",
        "ops_workspace",
        "New Fleet Run",
        10,
        "cadence.ops.fleet_planning_new",
        ["validate-fleet-run", "create-fleet-run"],
      ],
      [
        "fleet_planning_run",
        "subject_detail",
        "mission",
        "ops_workspace",
        "Fleet Planning Run",
        10,
        "cadence.ops.fleet_planning_run",
        ["refresh-fleet-run", "repair-fleet-run"],
      ],
      [
        "commands",
        "operations",
        "mission",
        "ops_workspace",
        "Commands",
        10,
        "cadence.ops.commands",
        [],
      ],
      [
        "telemetry_explore",
        "operations",
        "mission",
        "ops_workspace",
        "Telemetry Explore",
        10,
        "cadence.ops.telemetry_explore",
        ["apply_filters", "apply_question"],
      ],
      [
        "data_operations",
        "operations",
        "mission",
        "ops_workspace",
        "Data Operations",
        10,
        "cadence.ops.data_operations",
        [],
      ],
      [
        "data_operations_manage",
        "operations",
        "mission",
        "ops_workspace",
        "Manage Data Operations",
        10,
        "cadence.ops.data_operations_manage",
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
      [
        "alarms",
        "operations",
        "mission",
        "ops_workspace",
        "Alarms",
        10,
        "cadence.ops.alarms",
        ["filter", "reset_filters"],
      ],
      [
        "timeline",
        "activity",
        "mission",
        "ops_workspace",
        "Timeline",
        10,
        "cadence.ops.timeline",
        ["apply_timeline_filters", "clear_timeline_selection"],
      ],
    ] as SurfaceRow[],
  },
  {
    name: "organization_admin",
    manifest: organizationAdmin,
    package: { packageId: "cadence.organization-admin", version: 1 },
    displayName: "Organization Administration",
    description: "Show your notifications and mark them read.",
    installableScopes: ["user"] as const,
    releaseId: () => "organization-admin-v1",
    surfaces: [
      [
        "notifications_bell",
        "activity",
        "user",
        "application_workspace",
        "Notifications Bell",
        60,
        "cadence.organization.notifications_bell",
        ["mark_notification_read"],
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
    // remotes left (35 → 18).
    expect(surfaceCount).toBe(18);
  });
});
