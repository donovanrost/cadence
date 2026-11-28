export const context = {
  version: 1,
  user: { user_id: "user-1", display_name: "Operator", email: "operator@example.test" },
  organization: { organization_id: "org-1", display_name: "Flight Operations" },
  organizations: [
    { organization_id: "org-1", display_name: "Flight Operations" },
    { organization_id: "org-2", display_name: "Engineering" },
  ],
  capabilities: [],
  platform_admin: false,
  admin_mode: false,
  csrf_token: "test-csrf",
  nav_context: "organization",
  nav_item: "missions",
  mission: { mission_id: "mission/1", display_name: "Lunar", slug: "lunar" },
  ops_nav_item: "commands",
  dashboard_navigation: { starred: [], recent: [] },
  dock_surfaces: [],
};
