export interface AdminOrganization {
  id: string;
  name: string;
  reference: string;
  members: number;
  missions: number;
  updatedAt: string;
}

export const organizations: readonly AdminOrganization[] = [
  {
    id: "org-orbital-research",
    name: "Orbital Research",
    reference: "ORBITAL-RESEARCH",
    members: 14,
    missions: 3,
    updatedAt: "2026-08-22T18:42:00.000Z",
  },
  {
    id: "org-flight-systems",
    name: "Flight Systems Lab",
    reference: "FLIGHT-SYSTEMS",
    members: 8,
    missions: 1,
    updatedAt: "2026-08-20T16:10:00.000Z",
  },
  {
    id: "org-integration-range",
    name: "Integration Range",
    reference: "INTEGRATION-RANGE",
    members: 5,
    missions: 2,
    updatedAt: "2026-08-18T21:05:00.000Z",
  },
];

export function dateLabel(value: string): string {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "2-digit",
    year: "numeric",
  })
    .format(new Date(value))
    .toUpperCase();
}
