export interface TelemetryDecomManageProps {
  page: Record<string, unknown>;
  card: Record<string, unknown>;
  status: Record<string, unknown>;
  revision: Record<string, unknown> | null;
  no_revisions: Record<string, unknown> | null;
  packet_handoff: Record<string, unknown> | null;
  preview: Record<string, unknown> | null;
  preflight: Record<string, unknown>;
  pending_activation: Record<string, unknown> | null;
  lifecycle_actions: Record<string, unknown>;
}
