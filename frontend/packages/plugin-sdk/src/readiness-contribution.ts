/** Data-only contributions. Rendering and authorization remain host-owned. */
export const SPACECRAFT_READINESS_SLOT = "spacecraft.readiness" as const;
export type ReadinessContext = { organizationId: string; missionId: string; spacecraftId: string };
export type ReadinessContribution = {
  id: string;
  slot: typeof SPACECRAFT_READINESS_SLOT;
  version: 1;
  title: string;
  context: ReadinessContext;
  availability: "available" | "unavailable";
  status: { tone: "ready" | "attention" | "blocked" | "info"; label: string };
  details: { label: string; value: string }[];
  action: { label: string; href: string } | null;
};
