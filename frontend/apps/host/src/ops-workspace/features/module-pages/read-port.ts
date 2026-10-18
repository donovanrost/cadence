import type {
  OpsPageContext,
  OpsPageReadPort,
  OpsPageReadRequest,
  OpsPageUpdateSubscription,
  LiveOpsPageReadPort,
} from "@cadence/plugin-sdk/ops-pages";
import { readPageEnvelope, validPageToken } from "../../../shell/module-pages/page-admission";

/** The host admits the envelope only. Each feature interprets its own data. */
export function createOpsReadPort(
  id: string,
  token: unknown,
  context: OpsPageContext,
  active: () => boolean,
  query?: (request: OpsPageReadRequest) => Promise<unknown>,
  subscribe?: OpsPageUpdateSubscription,
): OpsPageReadPort | LiveOpsPageReadPort | undefined {
  if (!query || !validPageToken(token)) return;
  const captured = { ...context };
  return {
    ...(subscribe
      ? {
          subscribe(listener: () => void) {
            if (!active()) throw Error("Inactive Ops page subscription.");
            let listening = true;
            const stop = subscribe({ id, token }, () => {
              if (listening && active()) listener();
            });
            return () => {
              if (!listening) return;
              listening = false;
              stop();
            };
          },
        }
      : {}),
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
