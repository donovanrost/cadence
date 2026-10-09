export const missionPath = "/missions/kestrel";
export const directoryPath = `${missionPath}/ops/dashboards`;
export const dashboardPath = (id: string) => `${directoryPath}/${id}`;

/** Stories render against a fixed clock so relative times are stable. */
export const NOW = Date.parse("2026-10-08T12:00:00Z");

export type StudyDashboard = {
  id: string;
  name: string;
  description: string | null;
  tags: string[];
  updatedAt: number;
  updatedBy: string;
  starred: boolean;
  lastViewedAt: number | null;
  archived: boolean;
  /** How this person last looked at it: what Resume reopens. */
  lastContext?: { range: string; scope: string; query: string };
};

export type Scenario = "established" | "first-run" | "viewer" | "large" | "archived";

const minutes = (n: number) => NOW - n * 60_000;
const hours = (n: number) => minutes(n * 60);
const days = (n: number) => hours(n * 24);

const established: StudyDashboard[] = [
  dashboard(
    "pass-overview",
    "Pass Overview",
    "Live state during a ground station contact",
    ["pass", "comms"],
    hours(2),
    "Dana Rost",
    {
      starred: true,
      viewed: minutes(20),
      context: {
        range: "Last 6 hours",
        scope: "KESTREL-02",
        query: "?from=now-6h&to=now&spacecraft=KESTREL-02",
      },
    },
  ),
  dashboard(
    "power-bus",
    "Power Bus",
    "Bus voltage, array current and load shedding",
    ["eps"],
    days(1),
    "Avery Kim",
    { starred: true, viewed: hours(3) },
  ),
  dashboard(
    "fdir-watchlist",
    "FDIR Watchlist",
    "Monitors closest to their fault thresholds",
    ["fdir", "alarms"],
    hours(6),
    "Sam Ortiz",
    { starred: true, viewed: days(1) },
  ),
  dashboard(
    "comms-health",
    "Comms Health",
    "Link margin, lock status and frame errors",
    ["comms", "rf"],
    days(2),
    "Avery Kim",
    { viewed: hours(5) },
  ),
  dashboard(
    "adcs-pointing",
    "ADCS Pointing",
    "Attitude error, mode and sensor agreement",
    ["adcs"],
    days(3),
    "Jordan Lee",
    { viewed: days(2) },
  ),
  dashboard(
    "thermal-margins",
    "Thermal Margins",
    "Component temperatures against operating limits",
    ["thermal"],
    days(4),
    "Sam Ortiz",
  ),
  dashboard(
    "payload-imaging",
    "Payload Imaging Queue",
    "Planned captures, storage and downlink backlog",
    ["payload", "planning"],
    days(5),
    "Riley Chen",
    { viewed: days(4) },
  ),
  dashboard(
    "battery-cycling",
    "Battery Cycling Trend",
    "Depth of discharge across eclipse seasons",
    ["eps", "trends"],
    days(9),
    "Avery Kim",
  ),
  dashboard(
    "downlink-budget",
    "Downlink Budget",
    null,
    ["comms", "planning"],
    days(12),
    "Riley Chen",
  ),
  dashboard(
    "reaction-wheels",
    "Reaction Wheel Speeds",
    "Speed, current and zero-crossing history",
    ["adcs", "trends"],
    days(16),
    "Jordan Lee",
  ),
  dashboard(
    "orbit-eclipse",
    "Orbit & Eclipse",
    "Ground track, beta angle and eclipse timing",
    ["flight-dynamics"],
    days(21),
    "Dana Rost",
  ),
  dashboard(
    "ground-network",
    "Ground Station Network",
    "Station availability and upcoming contacts",
    ["ground", "comms"],
    days(30),
    "Sam Ortiz",
  ),
  dashboard(
    "commissioning",
    "Commissioning Checklist",
    "Subsystem checkout during commissioning",
    ["commissioning"],
    days(120),
    "Dana Rost",
    { archived: true },
  ),
  dashboard(
    "leop-overview",
    "LEOP Overview",
    null,
    ["leop", "commissioning"],
    days(150),
    "Dana Rost",
    { archived: true },
  ),
];

const subsystems = ["eps", "comms", "adcs", "thermal", "payload", "fdir", "trends"];

function large(): StudyDashboard[] {
  return Array.from({ length: 120 }, (_, index) => {
    const craft = `KESTREL-0${(index % 6) + 1}`;
    const tag = subsystems.at(index % subsystems.length) ?? "eps";
    const base = established.at(index % 12) ?? established[0];
    if (!base) throw new Error("Study fixtures are empty");
    return {
      ...base,
      id: `${base.id}-${index}`,
      name: `${base.name} · ${craft}`,
      tags: [tag, craft.toLowerCase()],
      updatedAt: hours(index * 7 + 1),
      starred: index < 4,
      lastViewedAt: index < 6 ? hours(index + 1) : null,
      archived: false,
    };
  });
}

export function dashboardsFor(scenario: Scenario): StudyDashboard[] {
  if (scenario === "first-run") return [];
  if (scenario === "large") return large();
  return established.map((item) => ({ ...item, tags: [...item.tags] }));
}

export const teammateDashboard = (): StudyDashboard =>
  dashboard(
    "conjunction-watch",
    "Conjunction Watch",
    "Close approaches and screening results",
    ["flight-dynamics", "alarms"],
    NOW,
    "Avery Kim",
  );

function dashboard(
  id: string,
  name: string,
  description: string | null,
  tags: string[],
  updatedAt: number,
  updatedBy: string,
  extra: {
    starred?: boolean;
    viewed?: number;
    archived?: boolean;
    context?: StudyDashboard["lastContext"];
  } = {},
): StudyDashboard {
  return {
    id,
    name,
    description,
    tags,
    updatedAt,
    updatedBy,
    starred: extra.starred ?? false,
    lastViewedAt: extra.viewed ?? null,
    archived: extra.archived ?? false,
    ...(extra.context ? { lastContext: extra.context } : {}),
  };
}
