import { computed, ref } from "vue";
import { fleet, type SpacecraftId } from "./fixtures";

export const missionPath = "/missions/kestrel";
export const spacecraftPath = (id: SpacecraftId) => `${missionPath}/spacecraft/${id}`;
export const catalogPath = `${missionPath}/catalog`;

type Destination = Readonly<{
  kind: "spacecraft" | "catalog" | "outside";
  navItem: string;
  title: string;
  path: string;
}>;
const destinations: readonly Destination[] = [
  { kind: "outside", navItem: "mission_overview", title: "Mission overview", path: missionPath },
  {
    kind: "outside",
    navItem: "mission_applications",
    title: "Mission applications",
    path: `${missionPath}/applications`,
  },
  { kind: "catalog", navItem: "catalog", title: "Catalog", path: catalogPath },
  {
    kind: "outside",
    navItem: "ops_dashboards",
    title: "Ops dashboards",
    path: `${missionPath}/ops/dashboards`,
  },
  {
    kind: "outside",
    navItem: "comms_overview",
    title: "Communications overview",
    path: `${missionPath}/comms`,
  },
  {
    kind: "outside",
    navItem: "comms_transports",
    title: "Transports",
    path: `${missionPath}/comms/transports`,
  },
  {
    kind: "outside",
    navItem: "comms_ground_stations",
    title: "Ground stations",
    path: `${missionPath}/comms/ground-stations`,
  },
  {
    kind: "outside",
    navItem: "comms_routing",
    title: "Routing",
    path: `${missionPath}/comms/routing`,
  },
  {
    kind: "outside",
    navItem: "comms_validation",
    title: "Communications validation",
    path: `${missionPath}/comms/validation`,
  },
];

// In-memory navigation for the design study. Browser history, authorization and
// actual resource routes remain the production host's responsibility.
export function useStudyNavigation(selectSpacecraft: (id: SpacecraftId) => void) {
  const destination = ref<Destination>({
    kind: "spacecraft",
    navItem: "spacecraft",
    title: "Spacecraft",
    path: `${missionPath}/spacecraft`,
  });
  const context = computed(() => ({
    version: 1,
    user: { user_id: "engineer", display_name: "Mission engineer", email: "engineer@example.test" },
    organization: { organization_id: "flight", display_name: "Flight Operations" },
    organizations: [],
    capabilities: ["organization_admin"],
    platform_admin: false,
    admin_mode: false,
    csrf_token: "storybook-csrf",
    notifications: [],
    unread_count: 0,
    nav_context: "mission",
    nav_item: destination.value.navItem,
    mission: { mission_id: "kestrel", display_name: "Kestrel", slug: "kestrel" },
  }));
  function navigate(path: string) {
    const craft = fleet.find((item) => spacecraftPath(item.id) === path);
    if (craft || path === `${missionPath}/spacecraft`) {
      if (craft) selectSpacecraft(craft.id);
      destination.value = { kind: "spacecraft", navItem: "spacecraft", title: "Spacecraft", path };
      return;
    }
    destination.value = destinations.find((item) => item.path === path) ?? {
      kind: "outside",
      navItem: "",
      title: path === "/" ? "Flight Operations" : "Cadence destination",
      path,
    };
  }
  return { destination, context, navigate };
}
