import { record } from "@cadence/plugin-sdk/admission";

export type PageContext = {
  organizationId: string;
  missionId?: string;
  spacecraftId?: string;
  resourceId?: string;
};
type ContextKey = keyof PageContext;
type PageRegistration = { id: string; slot: string; version: number };
type PageInput = {
  contributionId: string;
  snapshot: unknown;
  context: PageContext;
  refreshing?: boolean;
};
const contextKeys = ["organizationId", "missionId", "spacecraftId", "resourceId"] as const;
export const validPageToken = (token: unknown): token is string =>
  typeof token === "string" &&
  token.length === 36 &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(token);

function sameContext(value: unknown, expected: PageContext, required: readonly ContextKey[]) {
  return (
    record(value) &&
    required.every((key) => typeof expected[key] === "string" && expected[key] !== "") &&
    contextKeys.every((key) => value[key] === expected[key])
  );
}
export function readPageEnvelope(
  value: unknown,
  registration: PageRegistration,
  context: PageContext,
  required: readonly ContextKey[],
) {
  if (
    !record(value) ||
    value.id !== registration.id ||
    value.slot !== registration.slot ||
    value.version !== registration.version ||
    value.status !== "ready" ||
    !sameContext(value.context, context, required)
  )
    throw Error("Unavailable or mismatched page envelope.");
  return { data: value.data, token: value.token };
}

/** Captured capabilities survive data refreshes but never a changed token, page or scope. */
export function capturePage(
  input: PageInput,
  registration: PageRegistration,
  required: readonly ContextKey[],
  alive: () => boolean,
) {
  const context = { ...input.context };
  const envelope = readPageEnvelope(input.snapshot, registration, context, required);
  const active = () => {
    if (
      !alive() ||
      input.contributionId !== registration.id ||
      !sameContext(input.context, context, required)
    )
      return false;
    try {
      return (
        readPageEnvelope(input.snapshot, registration, context, required).token === envelope.token
      );
    } catch {
      return false;
    }
  };
  return { ...envelope, active, current: () => active() && !input.refreshing };
}

type PageAction = { id: string; token: string; event: string; input: Record<string, unknown> };
export function createPageActionPort(
  registration: PageRegistration & { actions: readonly string[] },
  token: unknown,
  current: () => boolean,
  transport: {
    execute: ((request: PageAction) => Promise<unknown>) | undefined;
    navigate: ((href: string) => void) | undefined;
  },
  label: string,
) {
  if (!validPageToken(token) || !transport.execute || !transport.navigate)
    throw Error(`Unavailable ${label} action capability.`);
  return {
    async execute(event: string, input: Record<string, unknown>) {
      if (!current() || !transport.execute || !registration.actions.includes(event))
        throw Error(`Inactive ${label} action.`);
      const result = await transport.execute({ id: registration.id, token, event, input });
      if (!current()) throw Error(`Inactive ${label} response.`);
      return result;
    },
    navigate(href: string) {
      if (current()) transport.navigate?.(href);
    },
  };
}
