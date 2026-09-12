import type { ReadinessContribution } from "@cadence/plugin-sdk/readiness";
import type { ReadinessData } from "./contracts";

export function contributionFixture(): ReadinessContribution {
  return {
    id: "comms.routing",
    slot: "spacecraft.readiness",
    version: 1,
    title: "Routing",
    context: { organizationId: "org-a", missionId: "mission-a", spacecraftId: "craft-a" },
    availability: "available",
    status: { tone: "info", label: "Review routing" },
    details: [{ label: "Enabled routing rules", value: "2" }],
    action: { label: "Review Routing", href: "/missions/mission-a/spacecraft/craft-a/routing" },
  };
}

export function readinessFixture(): ReadinessData {
  return {
    context: contributionFixture().context,
    page: {
      id: "spacecraft-readiness-page",
      title: "Readiness",
      title_suffix: "· Nova",
      subtitle: "Review spacecraft setup.",
      breadcrumbs: [{ label: "Spacecraft", href: "/missions/mission-a/spacecraft" }],
      status: { tone: "info", label: "Review setup" },
    },
    panels: [
      {
        id: "spacecraft-readiness-identity",
        title: "Identity",
        status: { tone: "ready", label: "Ready" },
        description: "Durable spacecraft identity.",
        details: [{ label: "SCID", value: "0" }],
        action: { label: "Edit Identity", href: "/missions/mission-a/spacecraft/craft-a/identity" },
        application_list: null,
      },
    ],
    applications: [],
    contributions: [contributionFixture()],
  };
}
