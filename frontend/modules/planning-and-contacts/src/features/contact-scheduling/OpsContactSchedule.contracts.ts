import type { CapturedContact } from "./contact-workflow";
import type { InjectionKey } from "vue";
export const schedulePageKeys = [
  "spacecraft_page",
  "routes_page",
  "findings_page",
  "scheduled_page",
  "realized_page",
  "reservations_page",
] as const;
export type SchedulePageKey = (typeof schedulePageKeys)[number];
export type SchedulePage<T> = { page: number; more: boolean; entries: T[] };
export type ScheduleContext = { organization_id: string; mission_id: string };
export type ProfileRef = { id: string; version: number };
export type RouteEvidence = {
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
};
export type ScheduleRoute = {
  key: string;
  spacecraft_id: string;
  provider: string;
  transport: string;
  service: string;
  delivery: string;
  delivery_summary: string;
  evidence: RouteEvidence;
};
export type ScheduleReservation = {
  id: string;
  lifecycle_state: string;
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
};
export type ContactSchedule = {
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
    lifecycle_state: string;
    starts_at: string | null;
    ends_at: string | null;
    revision: number;
    realized_id: string | null;
  }>;
  realized: SchedulePage<{
    id: string;
    lifecycle_state: string;
    realized_at: string | null;
    clock_mode: "live" | "replay";
    scheduled_id: string | null;
  }>;
  reservations: SchedulePage<ScheduleReservation>;
};
export type ScheduleSearch = {
  spacecraft_id: string;
  route_key: string;
  starts_at: string;
  ends_at: string;
};
export type ScheduleOpportunity = {
  id: string;
  starts_at: string;
  ends_at: string;
  expires_at: string;
  availability: string;
  synthetic: boolean;
  station: string;
  antenna: string | null;
  cost: number | null;
  token: string;
};
export type ScheduleSearchResult = {
  truncated: boolean;
  contract_version: 1;
  context: ScheduleContext;
  search: ScheduleSearch;
  route: ScheduleRoute;
  opportunities: ScheduleOpportunity[];
};
export type ScheduleReceipt = {
  providerReservationId: string;
  providerRevision: number;
  lifecycleState: string;
  scheduledContactId: string | null;
};
export type ScheduleAction = "search" | "reserve" | "cancel";
export interface ContactSchedulePort {
  captured?: CapturedContact;
  context: ScheduleContext;
  execute(action: ScheduleAction, input: Record<string, unknown>): Promise<unknown>;
  refresh(): Promise<unknown>;
}
export const CONTACT_SCHEDULE_PORT: InjectionKey<ContactSchedulePort> = Symbol(
  "cadence.contact-schedule-port",
);
export type OpsContactScheduleProps = { schedule: unknown; port?: ContactSchedulePort };
