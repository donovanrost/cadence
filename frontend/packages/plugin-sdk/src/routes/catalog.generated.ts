// Generated from apps/host/src/routes.json by tools/generate-route-types.mjs. Do not edit.
// Run `corepack pnpm routes:generate` after changing the route catalog.
export const routeCatalog = {
  "/missions/:mission_id/ops/commands/requests/:command_request_id/history": {
    kind: "ops_module",
    layer: "ops",
    scope: "mission",
    title: "Command history",
    queryKeys: ["release", "release_after", "verifier_after", "verifier"],
    header: {
      kind: "resource",
      breadcrumbs: true,
      eyebrow: false,
      description: null,
    },
  },
  "/missions/:mission_id/ops/commands": {
    kind: "ops_module",
    layer: "ops",
    scope: "mission",
    title: "Commands",
    queryKeys: ["status", "target", "query", "focus_command_id", "page"],
    header: {
      kind: "collection",
      breadcrumbs: true,
      eyebrow: false,
      description: null,
    },
  },
  "/missions/:mission_id/applications/:application_key/:surface_id": {
    kind: "application_surface",
    layer: "management",
    scope: "mission",
    title: null,
    queryKeys: [],
    header: {
      kind: "resource",
      breadcrumbs: true,
      eyebrow: false,
      description: null,
    },
  },
  "/missions/:mission_id/settings": {
    kind: "settings",
    layer: "management",
    scope: "mission",
    title: "Mission settings",
    queryKeys: [],
    header: {
      kind: "collection",
      breadcrumbs: true,
      eyebrow: false,
      description: null,
    },
  },
  "/missions/:mission_id/settings/:section_id": {
    kind: "settings",
    layer: "management",
    scope: "mission",
    title: "Mission settings",
    queryKeys: [],
    header: {
      kind: "collection",
      breadcrumbs: true,
      eyebrow: false,
      description: null,
    },
  },
} as const;
