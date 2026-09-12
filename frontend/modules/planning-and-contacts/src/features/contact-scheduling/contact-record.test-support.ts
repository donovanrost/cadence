import type { MutableFixture } from "../../../../../test-support/mutable-fixture";
import type { ContactRecord } from "./OpsContactRecord.contracts";
export function contactRecordFixture(): MutableFixture<ContactRecord> {
  const review: NonNullable<MutableFixture<ContactRecord>["review"]> = {
    id: "revision-one",
    revision: 1,
    created_at: "2026-09-08T12:00:00Z",
    created_by: "operator-one",
    provider_change_id: null,
    starts_at: "2027-01-01T12:00:00Z",
    ends_at: "2027-01-01T12:10:00Z",
    lifecycle_state: "scheduled",
    provider_contact_ref: "provider-contact-one",
  };
  return {
    contract_version: 1,
    context: { organization_id: "org-one", mission_id: "mission-one" },
    subject: { id: "scheduled-one", kind: "scheduled" },
    query: {
      contact_id: "scheduled-one",
      revision: 1,
      before_revision: null,
      scheduled_paths_page: 1,
      realized_paths_page: 1,
      sources_page: 1,
      intents_page: 1,
    },
    scheduled: {
      id: "scheduled-one",
      current_revision: 2,
      lifecycle_state: "realized",
      starts_at: "2027-01-01T12:01:00Z",
      ends_at: "2027-01-01T12:11:00Z",
      realized_id: "realized-one",
      provider_contact_ref: "provider-contact-one",
    },
    realized: {
      id: "realized-one",
      scheduled_id: "scheduled-one",
      lifecycle_state: "completed",
      clock_mode: "live",
      realized_at: "2027-01-01T12:01:00Z",
      initial_time: "2027-01-01T12:01:00Z",
    },
    review,
    origin: null,
    revisions: { entries: [review], next: null },
    scheduled_paths: {
      page: 1,
      more: false,
      entries: [
        {
          id: "scheduled-path",
          direction: "downlink",
          selection: "selected",
          source_endpoint_ref: "source-planned",
          provider_binding_count: 1,
          transport_binding_count: 1,
        },
      ],
    },
    realized_paths: {
      page: 1,
      more: false,
      entries: [
        {
          id: "actual-path",
          direction: "downlink",
          selection: "contributing",
          source_endpoint_ref: "source-actual",
          provider_binding_count: 1,
          transport_binding_count: 2,
        },
      ],
    },
    sources: {
      page: 1,
      more: false,
      entries: [
        { id: "source-planned", kind: "reviewed_schedule" },
        { id: "source-actual", kind: "realized" },
      ],
    },
    intents: {
      page: 1,
      more: false,
      entries: [
        { id: "payload_downlink", kind: "current_schedule" },
        { id: "payload_downlink", kind: "realized" },
      ],
    },
  };
}
