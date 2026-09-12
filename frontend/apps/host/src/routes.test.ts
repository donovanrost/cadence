import { expect, test } from "vite-plus/test";
import routes from "./routes.json";
import { catalogPages } from "./catalog/pages";
import { missionPages } from "./mission-and-spacecraft/pages";
import { spacecraftPages } from "./mission-and-spacecraft/spacecraft-pages";
import { spacecraftModulePages } from "./mission-and-spacecraft/features/module-pages/contributions";
import { missionModulePages } from "./mission-and-spacecraft/features/module-pages/mission-contributions";
import { opsPages } from "./ops-workspace/features/module-pages/contributions";
import { organizationModulePages } from "./administration/features/module-pages/contributions";
import { resolveHostComponent } from "./shell/registry";
test("requirement review captures exact version, run and page queries", () => {
  const route = routes.find(
    (r) => r.path === "/missions/:mission_id/ops/requirements/:contact_requirement_id",
  )!;
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "planning.requirement-review",
    resourceParam: "contact_requirement_id",
    scope: "mission",
  });
  expect(route.queryKeys).toEqual([
    "contact_requirement_id",
    "version",
    "planning_run_id",
    "versions_page",
    "runs_page",
    "searches_page",
    "opportunities_page",
  ]);
});
test("plan review retains the exact version and independently paged evidence", () => {
  const route = routes.find((r) => r.path === "/missions/:mission_id/ops/plans/:contact_plan_id")!;
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
test("requirements retain bounded page and lifecycle query parameters", () => {
  const route = routes.find((r) => r.path === "/missions/:mission_id/ops/requirements")!;
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "planning.requirement-directory",
    scope: "mission",
  });
  expect(route.queryKeys).toEqual(["page", "state"]);
});
test("commands are a compiled read-only mission contribution with explicit navigation", () => {
  const route = routes.find((r) => r.path === "/missions/:mission_id/ops/commands")!;
  expect(route).toMatchObject({ kind: "ops_module", contribution: "commanding.monitor" });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
  expect(route.resourceParam).toBeUndefined();
  expect(route.queryKeys).toEqual(["status", "target", "query", "focus_command_id", "page"]);
  expect(opsPages["commanding.monitor"].navigation).toBe(true);
  expect(opsPages["commanding.monitor"].actions).toBeUndefined();
});
test("Explore is a compiled mission query page with navigation but no action authority", () => {
  const route = routes.find((r) => r.path === "/missions/:mission_id/ops/explore")!;
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
  expect(opsPages["dashboards.exploration"].navigation).toBe(true);
  expect(opsPages["dashboards.exploration"].actions).toBeUndefined();
});
test("diagnostics is a compiled mission resource contribution with an explicit inspect action", () => {
  const route = routes.find(
    (r) => r.path === "/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics",
  )!;
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "dashboards.execution-diagnostics",
    resourceParam: "dashboard_id",
  });
  expect(route).not.toHaveProperty("application");
  expect(opsPages["dashboards.execution-diagnostics"].actions).toEqual(["inspect"]);
  expect(route.queryKeys).toEqual([
    "collection",
    "row",
    "filter",
    "time_mode",
    "time_axis",
    "from",
    "to",
    "realm",
    "selection_view",
    "limit_mode",
  ]);
});
test("shared viewers are compiled, read-only and derive identities only from their paths", () => {
  for (const [segment, key, contribution] of [
    ["dashboard-shares", "share_id", "dashboards.share"],
    ["dashboard-snapshots", "snapshot_id", "dashboards.snapshot"],
  ]) {
    const route = routes.find(
      (r) => r.path === "/missions/:mission_id/ops/" + segment + "/:" + key,
    );
    expect(route).toMatchObject({
      kind: "ops_module",
      contribution,
      resourceParam: key,
      queryKeys: [],
    });
    expect(route).not.toHaveProperty("application");
    expect(route).not.toHaveProperty("surface");
    expect(opsPages[contribution].actions).toEqual([]);
  }
});

test("settings is a resource-bound compiled contribution with finite actions and cursors", () => {
  const route = routes.find(
    (r) => r.path === "/missions/:mission_id/ops/dashboards/:dashboard_id/settings",
  )!;
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "dashboards.settings",
    resourceParam: "dashboard_id",
    queryKeys: ["after_share", "after_snapshot", "after_deployment"],
  });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
  expect(opsPages["dashboards.settings"].actions).toEqual([
    "save_settings",
    "create_share",
    "revoke_share",
    "create_snapshot",
    "archive_dashboard",
    "reload_settings",
    "page_settings",
  ]);
});
test("playlist composition binds its subject and bounded playback URL state", () => {
  const directory = routes.find(
    (r) => r.path === "/missions/:mission_id/ops/dashboards/playlists",
  )!;
  const present = routes.find(
    (r) => r.path === "/missions/:mission_id/ops/dashboards/playlists/:playlist_id/present",
  )!;
  expect(directory).toMatchObject({
    kind: "ops_module",
    contribution: "dashboards.playlists",
    queryKeys: ["q", "after"],
  });
  expect(present).toMatchObject({
    kind: "ops_module",
    contribution: "dashboards.playlist-present",
    resourceParam: "playlist_id",
    queryKeys: ["index", "playing"],
  });
  expect(directory).not.toHaveProperty("application");
  expect(present).not.toHaveProperty("application");
  expect(opsPages["dashboards.playlist-present"].actions).toEqual([]);
  expect(opsPages["dashboards.playlists"].actions).toEqual([
    "create_playlist",
    "reload_playlists",
    "search_dashboards",
  ]);
});
test("dashboard library is a compiled mission feature with bounded independent query state", () => {
  const route = routes.find(
    (route) => route.path === "/missions/:mission_id/ops/dashboards/library",
  )!;
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "dashboards.library",
    queryKeys: [
      "q",
      "after",
      "item_id",
      "version",
      "before_version",
      "consumer_after",
      "dashboard_query",
      "dashboard_after",
      "target_id",
    ],
  });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
  expect(opsPages["dashboards.library"].actions).toEqual([
    "create_item",
    "add_version",
    "add_to_draft",
    "reload_library",
  ]);
});
test("dashboard history is a resource-bound compiled feature with independent bounded cursors", () => {
  const route = routes.find(
    (route) => route.path === "/missions/:mission_id/ops/dashboards/:dashboard_id/activity",
  )!;
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "dashboards.activity",
    resourceParam: "dashboard_id",
    queryKeys: ["version", "before_version", "before_event", "selected_publish_issue"],
  });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
  expect(opsPages["dashboards.activity"].actions).toEqual([
    "publish_version",
    "restore_version",
    "reload_activity",
  ]);
});
test("dashboard authoring is a resource-bound compiled feature without an installation lookup", () => {
  const route = routes.find(
    (route) => route.path === "/missions/:mission_id/ops/dashboards/:dashboard_id/edit",
  )!;
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "dashboards.editor",
    resourceParam: "dashboard_id",
  });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
});
test("the dashboard viewer is a resource-bound compiled Ops contribution, not an installed application", () => {
  const route = routes.find(
    (route) => route.path === "/missions/:mission_id/ops/dashboards/:dashboard_id",
  )!;
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "dashboards.workspace",
    resourceParam: "dashboard_id",
  });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
});
test("Communications collections forward the bounded producer query keys", () => {
  const collections = routes.filter(
    (route) =>
      route.kind === "mission_module" &&
      ["comms.transports", "comms.routing", "comms.ground-stations"].includes(route.contribution!),
  );
  expect(collections).toHaveLength(3);
  for (const route of collections)
    expect(route.queryKeys).toEqual(["q", "page", "pageSize", "sort", "dir"]);
});
test("each core host route resolves to its registered owner", () => {
  expect(new Set(routes.map((route) => route.path)).size).toBe(routes.length);
  for (const route of routes) {
    if (route.kind === "ops_module") {
      expect(opsPages[route.contribution!], route.path).toBeDefined();
      expect(route.scope).toBe("mission");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "mission_module") {
      expect(missionModulePages[route.contribution!], route.path).toBeDefined();
      expect(route.scope).toBe("mission");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "organization_module") {
      expect(organizationModulePages[route.contribution!], route.path).toBeDefined();
      expect(route.scope).toBe("organization");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "spacecraft_module") {
      expect(spacecraftModulePages[route.contribution!], route.path).toBeDefined();
      expect(route.scope).toBe("spacecraft");
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
      expect(spacecraftPages[route.spacecraftPage!], route.path).toBeDefined();
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "mission") {
      expect(missionPages[route.missionPage!], route.path).toBeDefined();
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "catalog") {
      expect(catalogPages[route.catalogPage!], route.path).toBeDefined();
      expect(route.scope).toBe("mission");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "platform_administration") {
      expect([
        "/admin",
        "/admin/organizations",
        "/admin/organizations/new",
        "/admin/organizations/:org_id",
        "/admin/organizations/:org_id/invite",
      ]).toContain(route.path);
      expect([
        "platform_overview",
        "organization_directory",
        "organization_create",
        "organization_detail",
        "organization_invite",
      ]).toContain(route.administrationPage);
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      expect(route.scope).toBe("admin");
      continue;
    }
    if (route.kind === "notifications") {
      expect(route.path).toBe("/notifications");
      expect(route.scope).toBe("user");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      expect(route.queryKeys).toEqual(["unread", "before_at", "before_id"]);
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
    if (route.kind === "administration") {
      expect(route.path).toBe("/");
      expect(route.administrationPage).toBe("organization_home");
      expect(route.scope).toBe("organization");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "administration_diagnostics") {
      expect(route.path).toBe("/admin/runtime");
      expect(route.scope).toBe("admin");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "application_management") {
      expect(resolveHostComponent(route.component!)).toBeDefined();
      expect(route.queryKeys).toEqual([]);
      expect(["mission", "spacecraft"]).toContain(route.scope);
      continue;
    }
    throw new Error(`Unregistered core route kind: ${route.kind} (${route.path})`);
  }
});

test("reservation review forwards selected evidence and independent history cursors", () => {
  const route = routes.find((route) => route.contribution === "planning.reservation-review")!;
  expect(route.path).toBe("/missions/:mission_id/ops/contacts/:provider_reservation_id");
  expect(route.queryKeys).toEqual([
    "provider_reservation_id",
    "change_id",
    "before_revision",
    "before_audit",
  ]);
});

test("contact record routing forwards the reviewed revision and each evidence page", () => {
  const route = routes.find((route) => route.contribution === "planning.contact-record")!;
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
  const route = routes.find((r) => r.contribution === "planning.contact-schedule")!;
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
  ]);
});

test("declaration uses a compiled feature contribution at its existing URL", () => {
  const route = routes.find((r) => r.path === "/missions/:mission_id/ops/requirements/new");
  expect(route).toMatchObject({
    kind: "ops_module",
    contribution: "planning.requirement-declaration",
    queryKeys: [],
  });
});

test("recurring requirement templates use the compiled Planning contribution", () => {
  expect(
    routes.find((r) => r.path === "/missions/:mission_id/ops/requirement-templates"),
  ).toMatchObject({
    kind: "ops_module",
    contribution: "planning.requirement-templates",
    queryKeys: [],
  });
});
