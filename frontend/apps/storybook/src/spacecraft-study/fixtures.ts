export type SpacecraftId = "KESTREL-01" | "KESTREL-02" | "KESTREL-03";
export type RevisionId = "3.3" | "3.4";
export type Section = "overview" | "catalog" | "communications" | "changes" | "ops";
export type Inspector = "catalog" | "telemetry" | "commanding" | "route";
export type Scenario = "established" | "new" | "upgrade" | "review" | "missing-input";

export type Configuration = Readonly<{
  catalog: RevisionId | null;
  telemetryEnabled: boolean;
  telemetryInput: "obc-vc0" | null;
  commandingEnabled: boolean;
  downlink: "TM" | "AOS" | null;
  uplink: "TC" | null;
  route: "s-band" | null;
}>;

export type Revision = Readonly<{
  id: RevisionId;
  software: string;
  date: string;
  packets: number;
  parameters: number;
  commands: number;
  additions: readonly string[];
}>;

export const revisions: Readonly<Record<RevisionId, Revision>> = {
  "3.4": {
    id: "3.4",
    software: "Flight software 3.4.x",
    date: "12 Sep 2026",
    packets: 26,
    parameters: 248,
    commands: 19,
    additions: ["CAPTURE_IMAGE command", "2 payload status packets", "12 image health parameters"],
  },
  "3.3": {
    id: "3.3",
    software: "Flight software 3.3.x",
    date: "28 Aug 2026",
    packets: 24,
    parameters: 236,
    commands: 18,
    additions: ["Baseline bus commands", "ADCS and power telemetry", "OBC housekeeping packets"],
  },
};

export const fleet: readonly Readonly<{
  id: SpacecraftId;
  scid: string;
  role: string;
  hardware: string;
}>[] = [
  { id: "KESTREL-01", scid: "101", role: "Pathfinder", hardware: "6U · Block A" },
  { id: "KESTREL-02", scid: "102", role: "Imaging demonstrator", hardware: "6U · Block A" },
  { id: "KESTREL-03", scid: "103", role: "Commissioning", hardware: "6U · Block B" },
];

export const sections: readonly Readonly<{
  id: Exclude<Section, "ops">;
  label: string;
  icon: string;
}>[] = [
  { id: "overview", label: "Overview", icon: "hero-squares-2x2" },
  { id: "catalog", label: "Catalog & applications", icon: "hero-square-3-stack-3d" },
  { id: "communications", label: "Communications", icon: "hero-signal" },
  { id: "changes", label: "Changes", icon: "hero-arrows-right-left" },
];

export const emptyConfiguration: Configuration = {
  catalog: null,
  telemetryEnabled: false,
  telemetryInput: null,
  commandingEnabled: false,
  downlink: null,
  uplink: null,
  route: null,
};

export function configured(catalog: RevisionId): Configuration {
  return {
    catalog,
    telemetryEnabled: true,
    telemetryInput: "obc-vc0",
    commandingEnabled: true,
    downlink: "TM",
    uplink: "TC",
    route: "s-band",
  };
}

export type ConfigurationChange = Readonly<{ label: string; before: string; after: string }>;

export function revisionLabel(revision: RevisionId | null): string {
  return revision ? `Kestrel FSW · r${revision}` : "Not bound";
}

export function configurationChanges(
  active: Configuration | null,
  draft: Configuration,
): readonly ConfigurationChange[] {
  const before = active ?? emptyConfiguration;
  const fields: readonly Readonly<{
    key: keyof Configuration;
    label: string;
    value: (configuration: Configuration) => string;
  }>[] = [
    { key: "catalog", label: "OBC catalog", value: (config) => revisionLabel(config.catalog) },
    {
      key: "telemetryEnabled",
      label: "Telemetry Decom",
      value: (config) => (config.telemetryEnabled ? "Enabled" : "Not enabled"),
    },
    {
      key: "telemetryInput",
      label: "Telemetry input",
      value: (config) => (config.telemetryInput ? "OBC downlink · VC 0" : "Not connected"),
    },
    {
      key: "commandingEnabled",
      label: "Commanding",
      value: (config) => (config.commandingEnabled ? "Enabled" : "Not enabled"),
    },
    {
      key: "downlink",
      label: "Downlink framing",
      value: (config) => config.downlink ?? "Not configured",
    },
    {
      key: "uplink",
      label: "Uplink framing",
      value: (config) => config.uplink ?? "Not configured",
    },
    {
      key: "route",
      label: "Delivery path",
      value: (config) => (config.route ? "S-band · primary" : "Not connected"),
    },
  ];
  return fields
    .filter((field) => before[field.key] !== draft[field.key])
    .map((field) => ({
      label: field.label,
      before: field.value(before),
      after: field.value(draft),
    }));
}

export type SetupIssue = Readonly<{
  id: string;
  label: string;
  action: string;
  section: Section;
  inspector: Inspector | null;
}>;

export function setupIssues(config: Configuration): readonly SetupIssue[] {
  const issues: SetupIssue[] = [];
  if (!config.catalog)
    issues.push({
      id: "catalog",
      label: "Bind a catalog to the onboard computer",
      action: "Choose catalog",
      section: "catalog",
      inspector: "catalog",
    });
  if (!config.telemetryEnabled && !config.commandingEnabled)
    issues.push({
      id: "applications",
      label: "Enable an application to use these definitions",
      action: "Set up applications",
      section: "catalog",
      inspector: null,
    });
  if (config.telemetryEnabled && !config.telemetryInput)
    issues.push({
      id: "input",
      label: "Telemetry Decom needs a packet input",
      action: "Connect input",
      section: "catalog",
      inspector: "telemetry",
    });
  if ((config.telemetryEnabled && !config.downlink) || (config.commandingEnabled && !config.uplink))
    issues.push({
      id: "protocol",
      label: "Configure the framing used by enabled applications",
      action: "Configure framing",
      section: "communications",
      inspector: null,
    });
  if ((config.telemetryEnabled || config.commandingEnabled) && !config.route)
    issues.push({
      id: "route",
      label: "Connect a delivery path",
      action: "Connect path",
      section: "communications",
      inspector: null,
    });
  return issues;
}
