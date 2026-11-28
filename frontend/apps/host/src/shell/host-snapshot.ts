import { invalid, nullable, object, optional, record, string } from "./snapshot-readers";
const maybe = <T>(read: (value: unknown) => T) => optional(nullable(read));
const contextFields = object({
  user: nullable(object({ user_id: string, email: string, display_name: nullable(string) })),
  organization: nullable(object({ organization_id: string, display_name: string })),
  mission: nullable(object({ mission_id: string, display_name: string, slug: string })),
  spacecraft: maybe(object({ spacecraft_id: string, display_name: string })),
  csrf_token: string,
});
export function readHostContext(value: unknown) {
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
const snapshotFields = object({
  path: string,
  context: readHostContext,
  ops_page: maybe(contributedPage),
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
