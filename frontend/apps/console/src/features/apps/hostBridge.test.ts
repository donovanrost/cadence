import { describe, expect, it } from "vite-plus/test";
import type { HostSessionDescriptor } from "@cadence/plugin-sdk";
import { HostBridgeError, type HttpHostBridge } from "@cadence/plugin-sdk/host";
import { LOST_TEXT, repinningBridge } from "./hostBridge.ts";

const session = (id: string): HostSessionDescriptor => ({
  sessionId: id,
  csrfToken: "csrf",
  bridgeBaseUrl: "/api/cadence/application-host/v1/missions/m",
  context: {
    scope: "mission",
    organizationId: "o",
    missionId: "m",
    missionName: "Earendil",
    spacecraftId: null,
    spacecraftName: null,
    actor: { displayName: "Mira K.", permissions: ["applications:view"] },
  },
});
const mismatch = () =>
  new HostBridgeError(409, "host_session_mismatch", "Another scope holds the session.");

/** A fake HTTP bridge per session: `fails` sessions answer host_session_mismatch; calls record who answered. */
function fakes(fails: ReadonlySet<string>) {
  const made: string[] = [];
  const answered: string[] = [];
  const create = (s: HostSessionDescriptor): HttpHostBridge => {
    made.push(s.sessionId);
    const answer = async <T>(): Promise<T> => {
      if (fails.has(s.sessionId)) throw mismatch();
      answered.push(s.sessionId);
      // The fake has nothing to return; tests read `answered`.
      return undefined as never;
    };
    return {
      query: answer,
      execute: answer,
      subscribe: () => () => undefined,
      invalidate: () => undefined,
    };
  };
  return { made, answered, create };
}

const query = { queryId: "q", version: 1, context: session("s0").context };
const action = {
  applicationKey: "limits",
  applicationVersion: 1,
  actionId: "save_limit_definition",
  input: {},
  context: session("s0").context,
};

describe("L9 re-pinning bridge (api: one scope per session)", () => {
  it("re-pins and retries once on host_session_mismatch", async () => {
    const f = fakes(new Set(["s1"]));
    let lost = false;
    const b = repinningBridge({
      session: session("s1"),
      create: f.create,
      repin: async () => session("s2"),
      navigate: () => undefined,
      onReceipt: () => undefined,
      onLost: () => (lost = true),
    });
    await b.bridge.query(query);
    expect(f.made).toEqual(["s1", "s2"]);
    expect(f.answered).toEqual(["s2"]);
    expect(lost).toBe(false);
  });

  it("says it lost the connection when the retry fails too", async () => {
    const f = fakes(new Set(["s1", "s2"]));
    let lost = false;
    const b = repinningBridge({
      session: session("s1"),
      create: f.create,
      repin: async () => session("s2"),
      navigate: () => undefined,
      onReceipt: () => undefined,
      onLost: () => (lost = true),
    });
    await expect(b.bridge.query(query)).rejects.toThrow(LOST_TEXT);
    expect(lost).toBe(true);
  });

  it("hands every receipt to the save seam", async () => {
    const seen: string[] = [];
    const b = repinningBridge({
      session: session("s1"),
      create: fakes(new Set()).create,
      repin: async () => null,
      navigate: () => undefined,
      onReceipt: (actionId) => seen.push(actionId),
      onLost: () => undefined,
    });
    await b.bridge.execute(action);
    expect(seen).toEqual(["save_limit_definition"]);
  });
});
