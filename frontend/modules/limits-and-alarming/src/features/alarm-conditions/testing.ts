import { emptyPage } from "../../shared/testing";
import { alarmHref, type AlarmDocument } from "./contracts";
export function alarmFixture(total = 1, page = 1): AlarmDocument {
  const root = "/missions/mission-alarm";
  const query = {
    severity: "all",
    state: "all",
    spacecraft_id: "all",
    query: "",
    page,
    spacecraft_page: 1,
    spacecraft_query: "",
  } as const;
  const d: AlarmDocument = {
    version: 1,
    organization_id: "org-alarm",
    mission_id: "mission-alarm",
    mission_name: "Alarm mission",
    loaded_at: "2026-09-10T10:00:00Z",
    query: { ...query },
    links: {
      self: root + "/ops/alarms",
      definitions: root + "/applications/limits/manage",
      posture: root + "/applications/limits/activity",
    },
    counts: { critical: total, warning: 0, info: 0, nominal: 0 },
    states: emptyPage(),
    spacecraft: emptyPage(),
    spacecraft_filter: "All spacecraft and mission states",
  };
  const stamp = "2026-09-09T09:00:00Z";
  const items = Array.from(
    { length: Math.min(25, Math.max(0, total - (page - 1) * 25)) },
    (_, i) => {
      const n = (page - 1) * 25 + i;
      return {
        id: "limit-" + n,
        point_id: "HK.voltage",
        point_name: "Voltage",
        spacecraft_id: "craft-" + n,
        limit_set_name: "FLIGHT",
        definition_id: "definition",
        definition_version: 1,
        sample_id: "sample-" + n,
        source_sample_type: "telemetry_sample" as const,
        value: "42",
        state: "red_high",
        severity: "red" as const,
        violation: true,
        generation_time: null,
        receipt_time: stamp,
        definition_href: d.links.posture + "?definition=definition&version=1",
        evidence_href:
          root +
          "/ops/explore?" +
          new URLSearchParams({
            point_id: "HK.voltage",
            spacecraft_id: "craft-" + n,
            sample_id: "sample-" + n,
            selected_time: stamp,
          }),
      };
    },
  );
  d.states = {
    items,
    total_count: total,
    page,
    page_size: 25,
    previous_href: page > 1 ? alarmHref(d.links.self, { ...d.query, page: page - 1 }) : null,
    next_href: page * 25 < total ? alarmHref(d.links.self, { ...d.query, page: page + 1 }) : null,
  };
  return d;
}
