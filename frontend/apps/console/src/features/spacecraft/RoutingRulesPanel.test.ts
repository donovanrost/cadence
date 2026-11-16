import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { decode, missionId } from "@/api/index.ts";
import RoutingRulesPanel from "./RoutingRulesPanel.vue";
import { detailReader } from "./detail.ts";

const inu = { id: "gs-1", code: "INU", name: "Inuvik" };
const rule = (r: Record<string, unknown>) => ({
  name: "INU · EARENDIL-389",
  purpose: null,
  direction: "inbound",
  role: "primary",
  enabled: true,
  active: true,
  transport: { id: "t-1", name: "INU S-band", version: 1 },
  ...r,
});
function rules() {
  const result = decode(detailReader, {
    spacecraft: {
      id: "sc-1",
      name: "EARENDIL-389",
      scid: 389,
      norad_id: null,
      plane: null,
      slot: null,
      last_received_at: null,
    },
    profile: null,
    configuration: null,
    telemetry: { status: "never", last_received_at: null },
    routing_rules: [
      rule({ id: "p-1", name: "SVB primary", origin: "profile", route_id: null, station: null }),
      rule({ id: "leg-1", origin: "spacecraft", route_id: "route-1", station: inu }),
      rule({
        id: "leg-2",
        origin: "spacecraft",
        route_id: "route-1",
        station: inu,
        direction: "outbound",
      }),
      rule({ id: "old-1", name: "Old AWA", origin: "legacy", route_id: null, station: null }),
    ],
    readiness: { ready: true, checks: [] },
  });
  if (!result.ok) throw new Error(result.error.message);
  return result.value.routing_rules;
}

afterEach(() => vi.unstubAllGlobals());
async function render(canStage = true) {
  const staged: unknown[] = [];
  vi.stubGlobal("fetch", (url: string, init?: RequestInit) => {
    if (typeof init?.body === "string") staged.push(JSON.parse(init.body));
    const data = url.endsWith("/stage")
      ? {
          change_set_id: "cs-1",
          change_id: "c-1",
          version: 1,
          staged_count: 1,
          base_revision: 3,
          entity_ids: ["route-1"],
        }
      : {};
    return Promise.resolve(new Response(JSON.stringify({ data })));
  });
  const stub = { render: () => null };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/sc", name: "setup.spacecraft.one", component: stub },
      { path: "/changes", name: "setup.changes", component: stub },
      { path: "/comms", name: "setup.comms", component: stub },
    ],
  });
  await router.push("/sc");
  const w = mount(RoutingRulesPanel, {
    props: {
      missionId: missionId("m-1"),
      spacecraftName: "EARENDIL-389",
      rules: rules(),
      canStage,
    },
    global: { plugins: [router] },
    attachTo: document.body,
  });
  await flushPromises();
  return { w, router, staged };
}
const row = (w: Awaited<ReturnType<typeof render>>["w"], text: string) =>
  w.findAll("tr").find((tr) => tr.text().includes(text));

describe("Setup › Spacecraft › Routing (U79)", () => {
  it("tags every route by where it comes from", async () => {
    const { w } = await render();
    expect(row(w, "SVB primary")?.text()).toContain("From profile");
    expect(row(w, "INU · EARENDIL-389")?.text()).toContain("This spacecraft only");
    expect(row(w, "Old AWA")?.text()).toContain("This spacecraft only");
    w.unmount();
  });

  it("gives a legacy route its quiet line and a reachable reason instead of actions", async () => {
    const { w } = await render();
    const old = row(w, "Old AWA");
    expect(old?.text()).toContain("Set up on the old routing page.");
    const reason = old
      ?.findAll("span")
      .find((s) => s.text() === "Older routes can't be changed here yet.");
    expect(reason?.attributes("tabindex")).toBe("0");
    expect(old?.text()).not.toContain("Edit");
    w.unmount();
  });

  it("offers Add extra route above the list, and Edit once per extra route", async () => {
    const { w } = await render();
    const add = w.findAll("a").find((a) => a.text() === "Add extra route");
    expect(add?.attributes("href")).toContain("route=new");
    const edits = w.findAll("a").filter((a) => a.text() === "Edit");
    expect(edits.map((a) => a.attributes("href"))).toEqual([
      expect.stringContaining("route=route-1"),
    ]);
    expect(row(w, "SVB primary")?.text()).not.toContain("Remove…");
    w.unmount();
  });

  it("stages Remove… as the kind's delete with the named summary", async () => {
    const { w, router, staged } = await render();
    const remove = w.findAll("button").find((b) => b.text() === "Remove…");
    await remove?.trigger("click");
    await flushPromises();
    const stage = [...document.querySelectorAll("button")].find(
      (b) => b.textContent?.trim() === "Stage removal",
    );
    stage?.click();
    await flushPromises();
    expect(staged).toEqual([
      {
        summary: "Remove extra route INU · EARENDIL-389",
        source: { surface: "spacecraft" },
        ops: [{ kind: "spacecraft_route", action: "delete", entity_id: "route-1" }],
      },
    ]);
    expect(router.currentRoute.value.name).toBe("setup.changes");
    w.unmount();
  });

  it("shows tags but no Add, Edit, Remove… or reason to someone who can't stage", async () => {
    const { w } = await render(false);
    expect(w.text()).toContain("This spacecraft only");
    expect(w.text()).not.toContain("Add extra route");
    expect(w.text()).not.toContain("Remove…");
    expect(w.text()).not.toContain("Older routes can't be changed here yet.");
    w.unmount();
  });
});
