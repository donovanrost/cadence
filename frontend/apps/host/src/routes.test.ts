import { hostRoute } from "./shell/host-navigation";
import { required } from "../../../test-support/required";
import { expect, test } from "vite-plus/test";
import routes from "./routes.json";
import { catalogPages } from "./catalog/pages";
import { spacecraftPages } from "./mission-and-spacecraft/spacecraft-pages";
import { loadedOpsPages as opsPages } from "./module-pages.test-support";
test("plan review retains the exact version and independently paged evidence", () => {
  const route = required(
    routes.find((r) => r.path === "/missions/:mission_id/ops/plans/:contact_plan_id"),
  );
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "planning.plan-review",
    resourceParam: "contact_plan_id",
    scope: "mission",
  });
  expect(route.queryKeys).toEqual([
    "contact_plan_id",
    "version",
    "versions_page",
    "approvals_page",
    "opportunities_page",
    "execution_page",
    "requirements_page",
    "issues_page",
  ]);
});
test("commands are a compiled read-only mission contribution with explicit navigation", () => {
  const route = required(routes.find((r) => r.path === "/missions/:mission_id/ops/commands"));
  expect(route).toMatchObject({ kind: "ops_module", contribution: "commanding.monitor" });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
  expect(route.resourceParam).toBeUndefined();
  expect(route.queryKeys).toEqual(["status", "target", "query", "focus_command_id", "page"]);
  expect(required(opsPages["commanding.monitor"]).navigation).toBe(true);
  expect(required(opsPages["commanding.monitor"]).actions).toBeUndefined();
});
test("Explore is a compiled mission query page with navigation but no action authority", () => {
  const route = required(routes.find((r) => r.path === "/missions/:mission_id/ops/explore"));
  expect(route).toMatchObject({ kind: "ops_module", contribution: "dashboards.exploration" });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
  expect(route.resourceParam).toBeUndefined();
  expect(route.queryKeys).toEqual([
    "point_id",
    "spacecraft_id",
    "scope_kind",
    "scope_id",
    "time_mode",
    "time_axis",
    "from",
    "to",
    "replay_run_id",
    "order",
    "limit",
    "selection_view",
    "validity_state",
    "realm",
    "logical_source",
    "data_source_id",
    "source_binding_id",
    "source_dashboard_id",
    "sample_id",
    "selected_time",
    "question",
    "limit_mode",
    "data_view",
  ]);
  expect(route.queryAliases).toEqual({});
  expect(required(opsPages["dashboards.exploration"]).navigation).toBe(true);
  expect(required(opsPages["dashboards.exploration"]).actions).toBeUndefined();
});
test("each core host route resolves to its registered owner", () => {
  expect(new Set(routes.map((route) => route.path)).size).toBe(routes.length);
  for (const route of routes) {
    if (route.kind === "ops_module") {
      expect(opsPages[required(route.contribution)], route.path).toBeDefined();
      expect(route.scope).toBe("mission");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "activation_approvals") {
      expect(route.path).toBe("/missions/:mission_id/ops/activations");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "spacecraft") {
      expect(spacecraftPages[required(route.spacecraftPage)], route.path).toBeDefined();
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "catalog") {
      expect(catalogPages[required(route.catalogPage)], route.path).toBeDefined();
      expect(route.scope).toBe("mission");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "ops_workspace") {
      if (route.workspacePage === "landing") {
        expect(route.path).toBe("/missions/:mission_id/ops");
        expect(route.scope).toBe("mission");
        expect(route).not.toHaveProperty("application");
        expect(route).not.toHaveProperty("surface");
        expect(route.queryKeys).toEqual([]);
        continue;
      }
      expect(route.path).toBe("/missions/:mission_id/ops/timeline");
      expect(route.workspacePage).toBe("timeline");
      expect(route.scope).toBe("mission");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      expect(route.queryKeys).toEqual([
        "category",
        "kind",
        "severity",
        "spacecraft_id",
        "from",
        "to",
        "event_id",
        "source_dashboard_id",
        "before_at",
        "before_id",
      ]);
      continue;
    }
    if (route.kind === "application_surface") {
      // Served by the Phoenix application host; catalogued only for typed headers.
      expect(hostRoute(new URL(route.path, "https://cadence.test"))).toBeUndefined();
      expect(["mission", "spacecraft"]).toContain(route.scope);
      continue;
    }
    throw new Error(`Unregistered core route kind: ${route.kind} (${route.path})`);
  }
});

test("reservation review forwards selected evidence and independent history cursors", () => {
  const route = required(
    routes.find((route) => route.contribution === "planning.reservation-review"),
  );
  expect(route.path).toBe("/missions/:mission_id/ops/contacts/:provider_reservation_id");
  expect(route.queryKeys).toEqual([
    "provider_reservation_id",
    "change_id",
    "before_revision",
    "before_audit",
  ]);
});

test("contact record routing forwards the reviewed revision and each evidence page", () => {
  const route = required(routes.find((route) => route.contribution === "planning.contact-record"));
  expect(route.path).toBe("/missions/:mission_id/ops/contacts/records/:contact_id");
  expect(route.queryKeys).toEqual([
    "contact_id",
    "revision",
    "before_revision",
    "scheduled_paths_page",
    "realized_paths_page",
    "sources_page",
    "intents_page",
  ]);
});

test("contact scheduling captures spacecraft selection and independent ledger pages", () => {
  const route = required(routes.find((r) => r.contribution === "planning.contact-schedule"));
  expect(route.scope).toBe("mission");
  expect(route.path).toBe("/missions/:mission_id/ops/contacts");
  expect(route.queryKeys).toEqual([
    "spacecraft_id",
    "spacecraft_q",
    "spacecraft_page",
    "routes_page",
    "findings_page",
    "scheduled_page",
    "realized_page",
    "reservations_page",
    "operations_page",
  ]);
});
