import type { DiagnosticsSnapshot } from "@cadence/plugin-sdk";
import {
  array,
  count,
  invalid,
  nullable,
  object,
  optional,
  record,
  string,
} from "./snapshot-readers";
const maybe = <T>(read: (value: unknown) => T) => optional(nullable(read));
const contextFields = object({
  user: nullable(object({ user_id: string, email: string, display_name: nullable(string) })),
  organization: nullable(object({ organization_id: string, display_name: string })),
  mission: nullable(object({ mission_id: string, display_name: string, slug: string })),
  spacecraft: maybe(object({ spacecraft_id: string, display_name: string })),
  csrf_token: string,
});
function hostContext(value: unknown) {
  if (!record(value) || value.version !== 1) return invalid();
  // Account, navigation, and Ops readers own their additional payloads.
  return { ...value, ...contextFields(value) };
}
function envelope<T>(read: (value: unknown) => T) {
  return (value: unknown) => {
    if (!record(value)) return invalid();
    return { ...value, ...read(value) };
  };
}
const contributedPage = envelope(object({ id: optional(string), token: maybe(string) }));
const actionPage = envelope(object({ action_token: maybe(string) }));
const missionPage = envelope(object({ creation_token: maybe(string) }));
const spacecraftPage = envelope(object({ form_token: maybe(string), page: optional(string) }));
const activationPage = envelope(object({ token: maybe(string) }));
const featurePayload = (value: unknown) => value;
const diagnostics = (value: unknown): DiagnosticsSnapshot => {
  if (!record(value) || (value.status !== "ready" && value.status !== "unavailable"))
    return invalid();
  return {
    id: string(value.id),
    version: count(value.version),
    status: value.status,
    data: value.data,
  };
};
const snapshotFields = object({
  path: string,
  context: hostContext,
  error: maybe(string),
  diagnostics: optional(array(diagnostics)),
  application_management: featurePayload,
  activation_approvals: maybe(activationPage),
  organization_module_page: maybe(contributedPage),
  ops_page: maybe(contributedPage),
  mission_module_page: maybe(contributedPage),
  spacecraft_module_page: featurePayload,
  spacecraft_page: maybe(spacecraftPage),
  mission_page: maybe(missionPage),
  notifications_page: maybe(actionPage),
  platform_administration_page: maybe(actionPage),
  administration_page: featurePayload,
  catalog: featurePayload,
  ops_landing_page: featurePayload,
  timeline_page: featurePayload,
});
export type HostSnapshot = ReturnType<typeof snapshotFields>;
export function readHostSnapshot(value: unknown): HostSnapshot {
  return snapshotFields(value);
}
export function requireRecord(value: unknown): Record<string, unknown> {
  if (!record(value)) return invalid();
  return value;
}
export const errorMessage = (error: unknown): string =>
  error instanceof Error ? error.message : "This page is unavailable.";
