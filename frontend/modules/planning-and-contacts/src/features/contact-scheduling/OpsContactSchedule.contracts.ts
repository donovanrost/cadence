import type { Snapshot } from "@cadence/plugin-sdk/admission";
import type { ContactScheduleService } from "./schedule-service";
import type { InjectionKey } from "vue";
export const schedulePageKeys = [
  "spacecraft_page",
  "routes_page",
  "findings_page",
  "scheduled_page",
  "realized_page",
  "reservations_page",
  "operations_page",
] as const;
export type SchedulePageKey = (typeof schedulePageKeys)[number];
export type SchedulePage<T> = Snapshot<{ page: number; more: boolean; entries: T[] }>;
export type ScheduleContext = Snapshot<{ organization_id: string; mission_id: string }>;
export type ProfileRef = Snapshot<{ id: string; version: number }>;
export type RouteEvidence = Snapshot<{
  provider_id: string;
  provider_version: number;
  transport_id: string;
  transport_version: number;
  provider_profile_id: string;
  provider_profile_version: number;
  routing_rule_id: string;
  path_template_id: string;
  path_template_version: number;
  source_endpoint_id: string;
  provider_spacecraft_ref: string;
  service_profile_ref: ProfileRef;
  delivery_profile_ref: ProfileRef;
}>;
export type ScheduleRoute = Snapshot<{
  key: string;
  spacecraft_id: string;
  provider: string;
  transport: string;
  service: string;
  delivery: string;
  delivery_summary: string;
  evidence: RouteEvidence;
}>;
export type ReservationLifecycle =
  | "requesting"
  | "pending"
  | "confirmed"
  | "active"
  | "completed"
  | "rejected"
  | "canceled"
  | "canceling"
  | "failed"
  | "unknown";
export type ScheduleReservation = Snapshot<{
  id: string;
  lifecycle_state: ReservationLifecycle;
  provider_revision: number;
  provider_contact_ref: string | null;
  provider_id: string;
  provider_version: number;
  transport_id: string | null;
  transport_version: number | null;
  service_profile: ProfileRef | null;
  delivery_profile: ProfileRef | null;
  starts_at: string;
  ends_at: string;
  scheduled_id: string | null;
  last_reconciled_at: string | null;
}>;
export type ContactSchedule = Snapshot<{
  permissions: { operate: boolean; cancel: boolean };
  contract_version: 1;
  context: ScheduleContext;
  query: Record<SchedulePageKey, number> & { spacecraft_id: string | null; spacecraft_q: string };
  initial_window: { starts_at: string; ends_at: string };
  spacecraft: SchedulePage<{ id: string; name: string }>;
  selected_spacecraft: { id: string; name: string } | null;
  routes: SchedulePage<ScheduleRoute>;
  findings: SchedulePage<{ code: string; message: string; resource_id: string | null }>;
  scheduled: SchedulePage<{
    id: string;
    lifecycle_state: "scheduled" | "realized" | "completed" | "expired" | "canceled";
    starts_at: string | null;
    ends_at: string | null;
    revision: number;
    realized_id: string | null;
  }>;
  realized: SchedulePage<{
    id: string;
    lifecycle_state: "defined" | "active" | "stopped" | "completed";
    realized_at: string | null;
    clock_mode: "live" | "replay";
    scheduled_id: string | null;
  }>;
  reservations: SchedulePage<ScheduleReservation>;
}>;
export type ScheduleSearch = Snapshot<{
  spacecraft_id: string;
  route_key: string;
  starts_at: string;
  ends_at: string;
}>;
export type ScheduleOpportunity = Snapshot<{
  id: string;
  starts_at: string;
  ends_at: string;
  expires_at: string;
  availability: "available" | "limited" | "unavailable";
  synthetic: boolean;
  station: string;
  antenna: string | null;
  cost: number | null;
  token: string;
}>;
export type ScheduleSearchResult = Snapshot<{
  truncated: boolean;
  contract_version: 1;
  context: ScheduleContext;
  search: ScheduleSearch;
  route: ScheduleRoute;
  opportunities: ScheduleOpportunity[];
}>;
export type ScheduleReceipt = Snapshot<{
  providerReservationId: string;
  providerRevision: number;
  lifecycleState: ReservationLifecycle;
  scheduledContactId: string | null;
}>;
export type ScheduleAction = "search" | "reserve" | "cancel";
export type CancellableReservation = ScheduleReservation & {
  lifecycle_state: "pending" | "confirmed" | "active";
  provider_contact_ref: string;
};
export type CancelEvidence = Snapshot<{
  contract_version: 1;
  organization_id: string;
  mission_id: string;
  reservation_id: string;
  provider_revision: number;
  lifecycle_state: CancellableReservation["lifecycle_state"];
  provider_contact_ref: string;
}>;
export type ScheduleInputs = {
  search: Snapshot<{ contact_search: ScheduleSearch; route_evidence: RouteEvidence }>;
  reserve: Snapshot<{ token: string }>;
  cancel: Snapshot<{ reservation_evidence: CancelEvidence }>;
};
export type ScheduleRequest = {
  [A in ScheduleAction]: [action: A, input: ScheduleInputs[A]];
}[ScheduleAction];
export type SchedulePageRequest = {
  [A in ScheduleAction]: [action: A, input: { sequence: number; payload: ScheduleInputs[A] }];
}[ScheduleAction];
export type ContactSchedulePort = ContactScheduleService;
export const CONTACT_SCHEDULE_PORT: InjectionKey<ContactSchedulePort> = Symbol(
  "cadence.contact-schedule-port",
);
export type OpsContactScheduleProps = { schedule: unknown; port?: ContactSchedulePort };
