import { flushPromises } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { effectScope, ref } from "vue";
import { missionId } from "@/api/index.ts";
import { useContactLinks } from "./useContactLinks.ts";

afterEach(() => vi.unstubAllGlobals());

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
  it("links only the ids GET /passes/:id resolves, probing each once", async () => {
    const asked = server(["sc-1"]);
    const ids = ref<readonly string[]>(["sc-1", "rc-1"]);
    const scope = effectScope();
    const links = scope.run(() => useContactLinks(ref(missionId("m-1")), ids));
    if (!links) throw new Error("no scope");
    expect(links.resolved.value.size).toBe(0);
    await links.probe();
    await links.probe();
    expect(asked).toEqual(["sc-1", "rc-1"]);
    expect([...links.resolved.value]).toEqual(["sc-1"]);
    ids.value = ["rc-2"];
    await flushPromises();
    expect(links.resolved.value.size).toBe(0);
    scope.stop();
  });
});
