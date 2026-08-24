import type { StatusSymbolRole } from "@cadence/ui";

export type MonitoringSubjectKind =
  | "spacecraft"
  | "ground-station"
  | "telemetry-stream"
  | "command-path";

export interface MonitoringEvidence {
  label: string;
  value: string;
}

export interface MonitoringItem {
  evidence: readonly MonitoringEvidence[];
  id: string;
  identifier: string;
  observedAt: string;
  observedLabel: string;
  status: StatusSymbolRole;
  statusLabel: string;
  subject: string;
  subjectKind: MonitoringSubjectKind;
  summary: string;
}

export type MonitoringScenarioId =
  | "nominal-live"
  | "planned-standby"
  | "telemetry-caution"
  | "link-serious"
  | "command-critical"
  | "coverage-unknown";

export interface MonitoringScenario {
  asOf: string;
  asOfLabel: string;
  id: MonitoringScenarioId;
  items: readonly MonitoringItem[];
  label: string;
  note: string;
  scope: string;
  timeBasis: string;
}

const commonItems = {
  spacecraft: {
    id: "lunar-relay-02",
    identifier: "LR-02",
    subject: "Lunar relay",
    subjectKind: "spacecraft",
  },
  groundStation: {
    id: "goldstone-dss-24",
    identifier: "DSS-24",
    subject: "Goldstone",
    subjectKind: "ground-station",
  },
  telemetry: {
    id: "telemetry-vc-01",
    identifier: "TM VC-01",
    subject: "Telemetry stream",
    subjectKind: "telemetry-stream",
  },
  command: {
    id: "command-path-alpha",
    identifier: "CMD ALPHA",
    subject: "Command path",
    subjectKind: "command-path",
  },
} as const;

const observed = {
  at: "2026-08-23T14:23:02Z",
  label: "14:23:02",
} as const;

const nominalItems: readonly MonitoringItem[] = [
  {
    ...commonItems.spacecraft,
    status: "normal",
    statusLabel: "Normal",
    summary: "Flight state assessed from current navigation and bus telemetry.",
    observedAt: observed.at,
    observedLabel: observed.label,
    evidence: [
      { label: "Assessment", value: "Complete" },
      { label: "Navigation age", value: "1.2 s" },
      { label: "Bus limits", value: "0 violated" },
    ],
  },
  {
    ...commonItems.groundStation,
    status: "normal",
    statusLabel: "Normal",
    summary: "Carrier lock and antenna tracking are within the active pass plan.",
    observedAt: observed.at,
    observedLabel: observed.label,
    evidence: [
      { label: "Carrier lock", value: "Acquired" },
      { label: "Tracking error", value: "0.018°" },
      { label: "Schedule", value: "P042 active" },
    ],
  },
  {
    ...commonItems.telemetry,
    status: "normal",
    statusLabel: "Normal",
    summary: "Frames are current, ordered, and passing the configured quality checks.",
    observedAt: observed.at,
    observedLabel: observed.label,
    evidence: [
      { label: "Frame age", value: "0.8 s" },
      { label: "Frame lock", value: "True" },
      { label: "Quality", value: "Good" },
    ],
  },
  {
    ...commonItems.command,
    status: "standby",
    statusLabel: "Standby",
    summary: "The uplink path is available; no command transmission is active.",
    observedAt: observed.at,
    observedLabel: observed.label,
    evidence: [
      { label: "Path check", value: "Passed" },
      { label: "Transmitter", value: "Ready" },
      { label: "Active radiation", value: "None" },
    ],
  },
];

export const monitoringScenarioIds: readonly MonitoringScenarioId[] = [
  "nominal-live",
  "planned-standby",
  "telemetry-caution",
  "link-serious",
  "command-critical",
  "coverage-unknown",
];

export const monitoringScenarios: Readonly<Record<MonitoringScenarioId, MonitoringScenario>> = {
  "nominal-live": {
    id: "nominal-live",
    label: "Nominal live pass",
    note: "All active assessments are current. Command remains available but inactive.",
    scope: "Artemis relay · Pass 042",
    timeBasis: "UTC · Live",
    asOf: observed.at,
    asOfLabel: observed.label,
    items: nominalItems,
  },
  "planned-standby": {
    id: "planned-standby",
    label: "Planned standby",
    note: "Pass resources are ready. Data flow and command radiation are intentionally off.",
    scope: "Artemis relay · Pass 042",
    timeBasis: "UTC · Live",
    asOf: observed.at,
    asOfLabel: observed.label,
    items: [
      {
        ...nominalItems[0],
        status: "standby",
        statusLabel: "Standby",
        summary: "The spacecraft is available for the pass; active tracking has not begun.",
        evidence: [
          { label: "Pass phase", value: "Pre-acquisition" },
          { label: "Configured", value: "Yes" },
          { label: "Active tracking", value: "No" },
        ],
      },
      {
        ...nominalItems[1],
        status: "standby",
        statusLabel: "Standby",
        summary: "The antenna is configured and waiting for acquisition of signal.",
        evidence: [
          { label: "Antenna", value: "On point" },
          { label: "Receiver", value: "Ready" },
          { label: "Carrier lock", value: "Not expected" },
        ],
      },
      {
        ...nominalItems[2],
        status: "off",
        statusLabel: "Off",
        summary: "No telemetry is expected before acquisition of signal.",
        evidence: [
          { label: "Expected flow", value: "No" },
          { label: "Last frame", value: "Previous pass" },
          { label: "Configuration", value: "Intentional" },
        ],
      },
      {
        ...nominalItems[3],
        status: "off",
        statusLabel: "Off",
        summary: "Command radiation is inhibited by the pre-pass configuration.",
        evidence: [
          { label: "Transmitter", value: "Off" },
          { label: "Inhibit", value: "Applied" },
          { label: "Authority", value: "Not requested" },
        ],
      },
    ],
  },
  "telemetry-caution": {
    id: "telemetry-caution",
    label: "Telemetry freshness caution",
    note: "The stream remains usable, but its freshness threshold requires operator awareness.",
    scope: "Artemis relay · Pass 042",
    timeBasis: "UTC · Live",
    asOf: observed.at,
    asOfLabel: observed.label,
    items: nominalItems.map((item) =>
      item.id === commonItems.telemetry.id
        ? {
            ...item,
            status: "caution",
            statusLabel: "Caution",
            summary: "Frames are arriving beyond the 15-second freshness threshold.",
            evidence: [
              { label: "Frame age", value: "18.4 s" },
              { label: "Caution limit", value: "15.0 s" },
              { label: "Frame lock", value: "True" },
            ],
          }
        : item,
    ),
  },
  "link-serious": {
    id: "link-serious",
    label: "Degraded ground link",
    note: "Ground-link performance requires prompt intervention; telemetry is also delayed.",
    scope: "Artemis relay · Pass 042",
    timeBasis: "UTC · Live",
    asOf: observed.at,
    asOfLabel: observed.label,
    items: nominalItems.map((item) => {
      if (item.id === commonItems.groundStation.id) {
        return {
          ...item,
          status: "serious",
          statusLabel: "Serious",
          summary: "Carrier margin is below the intervention threshold and continues to fall.",
          evidence: [
            { label: "Link margin", value: "1.8 dB" },
            { label: "Serious limit", value: "2.0 dB" },
            { label: "Trend", value: "−0.6 dB/min" },
          ],
        };
      }

      if (item.id === commonItems.telemetry.id) {
        return {
          ...item,
          status: "caution",
          statusLabel: "Caution",
          summary: "Frame gaps correlate with the degraded ground link.",
          evidence: [
            { label: "Frame age", value: "11.7 s" },
            { label: "Missing frames", value: "28" },
            { label: "Quality", value: "Suspect" },
          ],
        };
      }

      if (item.id === commonItems.command.id) {
        return {
          ...item,
          status: "off",
          statusLabel: "Off",
          summary: "The uplink path is intentionally inhibited while link margin is degraded.",
          evidence: [
            { label: "Transmitter", value: "Off" },
            { label: "Inhibit", value: "Link policy" },
            { label: "Pending commands", value: "1" },
          ],
        };
      }

      return item;
    }),
  },
  "command-critical": {
    id: "command-critical",
    label: "Command-path response",
    note: "The command path has lost its required inhibit and requires immediate response.",
    scope: "Artemis relay · Pass 042",
    timeBasis: "UTC · Live",
    asOf: observed.at,
    asOfLabel: observed.label,
    items: nominalItems.map((item) =>
      item.id === commonItems.command.id
        ? {
            ...item,
            status: "critical",
            statusLabel: "Critical",
            summary: "The transmitter reports enabled while the safety inhibit is not confirmed.",
            evidence: [
              { label: "Transmitter", value: "Enabled" },
              { label: "Safety inhibit", value: "Not confirmed" },
              { label: "Response", value: "Disable path" },
            ],
          }
        : item,
    ),
  },
  "coverage-unknown": {
    id: "coverage-unknown",
    label: "Assessment coverage unknown",
    note: "Current evidence is incomplete. The affected subjects must not imply normal or off.",
    scope: "Artemis relay · Pass 042",
    timeBasis: "UTC · Live",
    asOf: observed.at,
    asOfLabel: observed.label,
    items: nominalItems.map((item) =>
      item.id === commonItems.spacecraft.id || item.id === commonItems.telemetry.id
        ? {
            ...item,
            status: "unknown",
            statusLabel: "Unknown",
            summary: "No current evidence is available for this assessment axis.",
            evidence: [
              { label: "Assessment", value: "Incomplete" },
              { label: "Last evidence", value: "13:58:44 UTC" },
              { label: "Cause", value: "Source unavailable" },
            ],
          }
        : item,
    ),
  },
};

export function getMonitoringScenario(id: MonitoringScenarioId): MonitoringScenario {
  return monitoringScenarios[id];
}
