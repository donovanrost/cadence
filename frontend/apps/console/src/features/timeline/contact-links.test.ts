import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { effectScope, ref } from "vue";
import { missionId } from "@/api/index.ts";
import { forgetContactLinks, UNRESOLVED_TTL_MS, useContactLinks } from "./useContactLinks.ts";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
  forgetContactLinks();
});

/** A booked pass row as GET /passes/:id returns it (the row keeps its own reservation id). */
const passRow = {
  id: "res-1",
  kind: "contact",
  booked: true,
  state: "completed",
  pass_phase: null,
  delivery_state: null,
  spacecraft_id: null,
  spacecraft: null,
  station: { ref: "FBK", id: null, code: "FBK", name: "Fairbanks" },
  antenna: null,
  starts_at: "2026-11-14T02:59:40Z",
  ends_at: "2026-11-14T03:08:52Z",
  uplink_capable: null,
  source: { provider: "p", provider_name: "Simulator", synthetic: true },
  max_elevation_deg: null,
  elevation_source: null,
  predicted_pass_id: null,
  plan: null,
};

/** GET /passes/:id answers the row for `known` ids and 404 pass_not_found for the rest. */
function server(known: readonly string[]) {
  const asked: string[] = [];
  vi.stubGlobal("fetch", (input: string) => {
    const id = decodeURIComponent(input.split("/passes/")[1] ?? "");
    asked.push(id);
    return Promise.resolve(
      known.includes(id)
        ? new Response(JSON.stringify({ data: passRow }))
        : new Response(
            JSON.stringify({ error: { code: "pass_not_found", message: "Not found." } }),
            { status: 404 },
          ),
    );
  });
  return asked;
}

describe("Timeline contact links (U78, lead's ruling)", () => {
  const mount = (ids: readonly string[]) => {
    const scope = effectScope();
    const links = scope.run(() => useContactLinks(ref(missionId("m-1")), ref(ids)));
    if (!links) throw new Error("no scope");
    return { links, stop: () => scope.stop() };
  };

  it("links only the ids GET /passes/:id resolves", async () => {
    server(["sc-1"]);
    const d = mount(["sc-1", "rc-1"]);
    expect(d.links.resolved.value.size).toBe(0);
    await d.links.probe();
    expect([...d.links.resolved.value]).toEqual(["sc-1"]);
    d.stop();
  });

  it("asks once per id across opened events; a miss is asked again only after its TTL", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const asked = server(["sc-1"]);
    const first = mount(["sc-1", "rc-1"]);
    await first.links.probe();
    await first.links.probe();
    // Another event naming the same contact: answered from the cache, no request.
    const second = mount(["sc-1", "rc-1"]);
    await second.links.probe();
    expect(asked).toEqual(["sc-1", "rc-1"]);
    expect([...second.links.resolved.value]).toEqual(["sc-1"]);
    vi.setSystemTime(Date.now() + UNRESOLVED_TTL_MS + 1);
    await second.links.probe();
    expect(asked).toEqual(["sc-1", "rc-1", "rc-1"]);
    first.stop();
    second.stop();
  });
});
