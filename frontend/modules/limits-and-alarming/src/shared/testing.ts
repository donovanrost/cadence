import type { Base, Page } from "./contracts";
import type { DefinitionsDocument } from "../features/definitions/contracts";
import type { PostureDocument } from "../features/posture/contracts";
export const emptyPage = <T>(): Page<T> => ({
  items: [],
  total_count: 0,
  page: 1,
  page_size: 25,
  previous_href: null,
  next_href: null,
});
export function baseFixture(surface: Base["surface"]): Base {
  const root = "/missions/mission-limits/applications/limits";
  return {
    contract_version: 1,
    surface,
    context: {
      organization_id: "org-limits",
      mission_id: "mission-limits",
      actor_id: "operator-limits",
      installation_id: "installation-limits",
    },
    mission_name: "Test mission",
    query: {
      page: 1,
      history_page: 1,
      activation_page: 1,
      points_page: 1,
      spacecraft_page: 1,
      q: "",
      points_q: "",
      spacecraft_q: "",
      spacecraft: "",
      definition: "",
      point: "",
      set: "",
      severity: "",
      version: null,
    },
    links: {
      self: root + "/" + surface,
      manage: root + "/manage",
      activity: root + "/activity",
      applications: "/missions/mission-limits/applications",
    },
  };
}
export function definitionsFixture(): DefinitionsDocument {
  const b = baseFixture("manage");
  return {
    ...b,
    surface: "manage",
    query: { ...b.query, point: "HK.voltage", set: "FLIGHT" },
    definitions: emptyPage(),
    points: emptyPage(),
    selection: null,
    editor: {
      point_id: "HK.voltage",
      limit_set_name: "FLIGHT",
      current: null,
      active: null,
      review: { definition_id: null, version: 0, activation_event_id: null },
    },
  };
}
export function postureFixture(): PostureDocument {
  return {
    ...baseFixture("activity"),
    surface: "activity",
    states: emptyPage(),
    spacecraft: emptyPage(),
    counts: { red: 0, yellow: 0, blue: 0, green: 0 },
    spacecraft_filter: "All spacecraft and mission states",
    selection: null,
  };
}
