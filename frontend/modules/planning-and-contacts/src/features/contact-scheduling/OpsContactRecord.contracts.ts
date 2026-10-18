import type { Snapshot } from "@cadence/plugin-sdk/admission";
import type { WorkflowProtocol } from "../../shared/workflow-protocol";
import type { InjectionKey } from "vue";
export const recordPageKeys = [
  "scheduled_paths_page",
  "realized_paths_page",
  "sources_page",
  "intents_page",
] as const;
export type RecordPageKey = (typeof recordPageKeys)[number];
export type RecordPage<T> = Snapshot<{ page: number; more: boolean; entries: T[] }>;
export type ContactRevision = Snapshot<{
  id: string;
  revision: number;
  created_at: string;
  created_by: string;
  provider_change_id: string | null;
}>;
export type ContactPath = Snapshot<{
  id: string;
  direction: "uplink" | "downlink";
  selection: "selected" | "candidate" | "contributing";
  source_endpoint_ref: string | null;
  provider_binding_count: number;
  transport_binding_count: number;
}>;
export type ContactRecord = Snapshot<{
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  subject: { id: string; kind: "scheduled" | "realized" };
  query: Record<RecordPageKey, number> & {
    contact_id: string;
    revision: number | null;
    before_revision: number | null;
  };
  scheduled: {
    id: string;
    current_revision: number;
    lifecycle_state: "scheduled" | "realized" | "completed" | "expired" | "canceled";
    starts_at: string;
    ends_at: string | null;
    realized_id: string | null;
    provider_contact_ref: string | null;
  } | null;
  realized: {
    id: string;
    scheduled_id: string | null;
    lifecycle_state: "defined" | "active" | "stopped" | "completed";
    clock_mode: "live" | "replay";
    realized_at: string | null;
    initial_time: string | null;
  } | null;
  review:
    | (ContactRevision & {
        starts_at: string;
        ends_at: string | null;
        lifecycle_state: "scheduled" | "realized" | "completed" | "expired" | "canceled";
        provider_contact_ref: string | null;
      })
    | null;
  origin: {
    change_id: string;
    reservation_id: string;
    provider_revision: number;
    proposal_hash: string;
  } | null;
  revisions: { entries: ContactRevision[]; next: number | null };
  scheduled_paths: RecordPage<ContactPath>;
  realized_paths: RecordPage<ContactPath>;
  sources: RecordPage<{ id: string; kind: "reviewed_schedule" | "realized" }>;
  intents: RecordPage<{ id: string; kind: "current_schedule" | "realized" }>;
}>;
export type ContactRecordPort = WorkflowProtocol & {
  context: { organization_id: string; mission_id: string; contact_id?: string };
  refresh: () => Promise<unknown>;
};
export const CONTACT_RECORD_PORT: InjectionKey<ContactRecordPort> = Symbol(
  "cadence.contact-record-port",
);
export type OpsContactRecordProps = { record: unknown; port?: ContactRecordPort };
