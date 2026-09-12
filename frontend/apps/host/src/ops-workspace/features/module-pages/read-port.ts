import type {
  OpsPageContext,
  OpsPageReadPort,
  OpsPageReadRequest,
} from "@cadence/plugin-sdk/ops-pages";
import { readPageEnvelope, validPageToken } from "../../../shell/module-pages/page-admission";

/** The host admits the envelope only. Each feature interprets its own data. */
export function createOpsReadPort(
  id: string,
  token: unknown,
  context: OpsPageContext,
  active: () => boolean,
  query?: (request: OpsPageReadRequest) => Promise<unknown>,
): OpsPageReadPort | undefined {
  if (!query || !validPageToken(token)) return;
  const captured = { ...context };
  return {
    async read() {
      if (!active()) throw Error("Inactive Ops page read.");
      const result = await query({ id, token });
      if (!active()) throw Error("Inactive Ops page response.");
      try {
        const envelope = readPageEnvelope(result, { id, slot: "ops.page", version: 1 }, captured, [
          "organizationId",
          "missionId",
        ]);
        if (envelope.token !== token) throw Error("Changed page token");
        return envelope.data;
      } catch {
        throw Error("Unavailable Ops page read.");
      }
    },
  };
}
