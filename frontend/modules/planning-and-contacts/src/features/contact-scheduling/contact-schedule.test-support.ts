import { required } from "../../../../../test-support/required";
import { mutableFixture, type MutableFixture } from "../../../../../test-support/mutable-fixture";
import type {
  ContactSchedule,
  ScheduleSearch,
  ScheduleSearchResult,
  ScheduleReceipt,
} from "./OpsContactSchedule.contracts";
export const scheduleFixture = (): MutableFixture<ContactSchedule> => ({
  permissions: { operate: true, cancel: true },
  contract_version: 1,
  context: { organization_id: "org-one", mission_id: "mission-one" },
  query: {
    spacecraft_id: "craft-one",
    spacecraft_q: "",
    spacecraft_page: 1,
    routes_page: 1,
    findings_page: 1,
    scheduled_page: 1,
    realized_page: 1,
    reservations_page: 1,
  },
  initial_window: { starts_at: "2099-09-09T12:00:00Z", ends_at: "2099-09-09T13:00:00Z" },
  spacecraft: { page: 1, more: false, entries: [{ id: "craft-one", name: "Test craft" }] },
  selected_spacecraft: { id: "craft-one", name: "Test craft" },
  routes: {
    page: 1,
    more: false,
    entries: [
      {
        key: "route-one",
        spacecraft_id: "craft-one",
        provider: "Ground Network",
        transport: "Primary downlink",
        service: "Telemetry",
        delivery: "Cadence ingress",
        delivery_summary: "Streaming to Cadence",
        evidence: {
          provider_id: "provider-one",
          provider_version: 2,
          transport_id: "transport-one",
          transport_version: 3,
          provider_profile_id: "profile-one",
          provider_profile_version: 1,
          routing_rule_id: "rule-one",
          path_template_id: "path-one",
          path_template_version: 2,
          source_endpoint_id: "source-one",
          provider_spacecraft_ref: "SC-1",
          service_profile_ref: { id: "service-one", version: 3 },
          delivery_profile_ref: { id: "delivery-one", version: 7 },
        },
      },
    ],
  },
  findings: { page: 1, more: false, entries: [] },
  scheduled: {
    page: 1,
    more: false,
    entries: [
      {
        id: "scheduled-one",
        lifecycle_state: "scheduled",
        starts_at: "2099-09-09T12:05:00Z",
        ends_at: "2099-09-09T12:15:00Z",
        revision: 1,
        realized_id: null,
      },
    ],
  },
  realized: {
    page: 1,
    more: false,
    entries: [
      {
        id: "realized-one",
        lifecycle_state: "completed",
        realized_at: "2026-09-09T12:00:00Z",
        clock_mode: "replay",
        scheduled_id: null,
      },
    ],
  },
  reservations: {
    page: 1,
    more: false,
    entries: [
      {
        id: "reservation-one",
        lifecycle_state: "confirmed",
        provider_revision: 4,
        provider_contact_ref: "provider-contact-one",
        provider_id: "provider-one",
        provider_version: 2,
        transport_id: "transport-one",
        transport_version: 3,
        service_profile: { id: "service-one", version: 3 },
        delivery_profile: { id: "delivery-one", version: 7 },
        starts_at: "2099-09-09T12:05:00Z",
        ends_at: "2099-09-09T12:15:00Z",
        scheduled_id: "scheduled-one",
        last_reconciled_at: "2026-09-09T12:00:00Z",
      },
    ],
  },
});
export function searchFixture(
  model: ContactSchedule = scheduleFixture(),
  search?: ScheduleSearch,
): MutableFixture<ScheduleSearchResult> {
  return mutableFixture<ScheduleSearchResult>({
    contract_version: 1,
    context: model.context,
    truncated: false,
    route: required(model.routes.entries[0]),
    search: search ?? {
      spacecraft_id: required(model.selected_spacecraft).id,
      route_key: required(model.routes.entries[0]).key,
      ...model.initial_window,
    },
    opportunities: [
      {
        id: "opportunity-one",
        starts_at: model.initial_window.starts_at,
        ends_at: model.initial_window.ends_at,
        expires_at: model.initial_window.starts_at,
        availability: "available",
        synthetic: true,
        station: "Station one",
        antenna: "Antenna one",
        cost: 25,
        token: "opaque-token-one",
      },
    ],
  });
}
export const completion = (result: unknown) => ({
  receiptId: "receipt-one",
  completedAt: "2026-09-09T12:00:00Z",
  result,
});
export const receiptFixture = (
  lifecycleState: ScheduleReceipt["lifecycleState"] = "confirmed",
): ScheduleReceipt => ({
  providerReservationId: "reservation-one",
  providerRevision: 5,
  lifecycleState,
  scheduledContactId: "scheduled-one",
});
