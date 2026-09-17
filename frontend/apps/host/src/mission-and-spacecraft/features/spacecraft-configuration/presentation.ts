import type { ConfigurationDocument, ConfigurationSnapshot, Inspector, Section } from "./contracts";
export const sections = [
  { id: "overview", label: "Overview", icon: "hero-squares-2x2" },
  { id: "catalog", label: "Catalog & applications", icon: "hero-square-3-stack-3d" },
  { id: "communications", label: "Communications", icon: "hero-signal" },
  { id: "changes", label: "Changes", icon: "hero-arrows-right-left" },
] as const;
export function revisionLabel(snapshot: ConfigurationSnapshot, id: string | null | undefined) {
  const revision = snapshot.catalogs.find((item) => item.id === id);
  return revision
    ? `${revision.name} · ${revision.label}`
    : id
      ? "Previously bound revision"
      : "No catalog bound";
}
export type SetupIssue = {
  id: string;
  label: string;
  detail: string;
  section: Section;
  inspector: Inspector | null;
};
export function setupIssues(document: ConfigurationDocument): readonly SetupIssue[] {
  const issues: SetupIssue[] = [];
  if (!document.catalog_revision_id)
    issues.push({
      id: "catalog",
      label: "Choose a flight software catalog",
      detail: "Bind an imported revision to this onboard computer.",
      section: "catalog",
      inspector: "catalog",
    });
  if (
    document.telemetry_enabled &&
    (!document.telemetry_source_endpoint_id || !document.handled_apids.length)
  )
    issues.push({
      id: "packets",
      label: "Connect telemetry inputs",
      detail: "Choose the packet source and APIDs Telemetry Decom will handle.",
      section: "catalog",
      inspector: "telemetry",
    });
  return issues;
}
export function configurationChanges(
  snapshot: ConfigurationSnapshot,
  draft: ConfigurationDocument,
) {
  const active = snapshot.active?.document;
  const beforeProtocol = active?.protocol;
  const protocol = draft.protocol;
  const rows = [
    {
      label: "Flight software catalog",
      ...identityLabels(
        revisionLabel(snapshot, active?.catalog_revision_id),
        revisionLabel(snapshot, draft.catalog_revision_id),
        active?.catalog_revision_id ?? null,
        draft.catalog_revision_id,
      ),
      impact: "Telemetry Decom and Commanding definitions",
    },
    {
      label: "Telemetry Decom",
      before: active?.telemetry_enabled ? "Enabled" : "Disabled",
      after: draft.telemetry_enabled ? "Enabled" : "Disabled",
      impact: "Incoming telemetry processing",
    },
    {
      label: "Packet input",
      ...identityLabels(
        sourceLabel(snapshot, active?.telemetry_source_endpoint_id),
        sourceLabel(snapshot, draft.telemetry_source_endpoint_id),
        active?.telemetry_source_endpoint_id ?? null,
        draft.telemetry_source_endpoint_id,
      ),
      impact: "Source of incoming packets",
    },
    {
      label: "Selected APIDs",
      before: active?.handled_apids.join(", ") || "None",
      after: draft.handled_apids.join(", ") || "None",
      impact: "Packets accepted by Telemetry Decom",
    },
    {
      label: "Commanding",
      before: active?.commanding_enabled ? "Enabled" : "Disabled",
      after: draft.commanding_enabled ? "Enabled" : "Disabled",
      impact: "Command discovery and preparation",
    },
    {
      label: "Framing",
      before: protocolLabel(beforeProtocol),
      after: protocolLabel(protocol),
      impact: "Spacecraft communications interpretation",
    },
  ];
  return rows.filter((row) => row.before !== row.after);
}
function identityLabels(
  before: string,
  after: string,
  beforeId: string | null,
  afterId: string | null,
) {
  return before === after && beforeId !== afterId
    ? { before: `${before} · ${beforeId}`, after: `${after} · ${afterId}` }
    : { before, after };
}
function protocolLabel(protocol: ConfigurationDocument["protocol"] | undefined) {
  return protocol
    ? `${protocol.downlink.toUpperCase()} ↓ / ${protocol.uplink.toUpperCase()} ↑ · ${protocol.frame_size} B · headers ${protocol.secondary_header_length}/${protocol.insert_zone_length}/${protocol.ocf_length} B${protocol.truncated_primary_header ? " · truncated" : ""}`
    : "Not configured";
}
export function sourceLabel(snapshot: ConfigurationSnapshot, id: string | null | undefined) {
  return (
    snapshot.sources.find((source) => source.id === id)?.name ??
    (id ? "Previously selected source" : "No source connected")
  );
}
