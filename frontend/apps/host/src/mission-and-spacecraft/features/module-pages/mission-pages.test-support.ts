import { overviewResponse } from "../../../../../../modules/communications/src/features/overview/fixtures.test-support";
import * as transports from "../../../../../../modules/communications/src/features/transports/read-fixtures.test-support";
import * as routing from "../../../../../../modules/communications/src/features/routing/read-fixtures.test-support";
import * as stations from "../../../../../../modules/communications/src/features/ground-stations/read-fixtures.test-support";
export const missionContext = { organizationId: "org-1", missionId: "mission-1" };
export function missionSnapshots() {
  return [
    {
      id: "comms.overview",
      data: {
        navigation: { fallback_href: "/missions/mission-1/comms", breadcrumbs: [] },
        data: overviewResponse().presentation,
      },
    },
    {
      id: "comms.validation",
      data: {
        navigation: { fallback_href: "/missions/mission-1/comms/validation", breadcrumbs: [] },
        data: {
          title: "Validation",
          finding_count: 0,
          total_count: 0,
          page: 1,
          page_size: 20,
          page_count: 1,
          empty: true,
          status: "ready",
          findings: [],
          finding_groups: [],
        },
      },
    },
    { id: "comms.transports", data: transports.directoryPayload() },
    { id: "comms.transport", resourceId: "transports-1", data: transports.detailPayload() },
    { id: "comms.routing", data: routing.directoryPayload() },
    { id: "comms.routing-detail", resourceId: "routing-1", data: routing.detailPayload() },
    { id: "comms.ground-stations", data: stations.directoryPayload() },
    { id: "comms.ground-station", resourceId: "ground-stations-1", data: stations.detailPayload() },
  ].map(({ resourceId, ...item }) => ({
    ...item,
    slot: "mission.page",
    version: 1,
    status: "ready",
    context: { ...missionContext, ...(resourceId ? { resourceId } : {}) },
  }));
}
