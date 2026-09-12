import type {
  OpsPageContext,
  OpsPageReadPort,
  OpsPageReadRequest,
} from "@cadence/plugin-sdk/ops-pages";
const record = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === "object" && !Array.isArray(value);

/** The host admits the envelope only. Each feature interprets its own data. */
export function createOpsReadPort(
  id: string,
  token: unknown,
  context: OpsPageContext,
  active: () => boolean,
  query?: (request: OpsPageReadRequest) => Promise<unknown>,
): OpsPageReadPort | undefined {
  if (
    !query ||
    typeof token !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(token)
  )
    return;
  const captured = { ...context };
  return {
    async read() {
      if (!active()) throw Error("Inactive Ops page read.");
      const result = await query({ id, token });
      if (!active()) throw Error("Inactive Ops page response.");
      if (
        !record(result) ||
        result.id !== id ||
        result.slot !== "ops.page" ||
        result.version !== 1 ||
        result.status !== "ready" ||
        result.token !== token ||
        !record(result.context) ||
        result.context.organizationId !== captured.organizationId ||
        result.context.missionId !== captured.missionId ||
        result.context.resourceId !== captured.resourceId
      )
        throw Error("Unavailable Ops page read.");
      return result.data;
    },
  };
}
