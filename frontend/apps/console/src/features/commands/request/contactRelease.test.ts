import { flushPromises, mount } from "@vue/test-utils";
import { computed, defineComponent, h } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import { groupOf } from "../groups/fixtures.ts";
import AbortPanel from "./AbortPanel.vue";
import ContactRelease from "./ContactRelease.vue";

vi.mock("@/shell/index.ts", async (original) => ({
  ...(await original<typeof import("@/shell/index.ts")>()),
  useMissionScope: () => computed(() => ({ mission: { id: missionId("m-1"), name: "EARENDIL" } })),
}));

/** a11y B6/A5 (#243, ca-ux, ux B4): a release's result outlives the callout that a clean one empties. */
const contact = (armed: string[]) => ({
  realized_contact_id: "rc-9",
  booked: false,
  station: { ref: "sva", id: null, code: "SVA", name: "Svalbard A" },
  starts_at: "2026-11-14T00:12:00Z",
  ends_at: null,
  started_by: { kind: "user", id: "user-7", name: "Mira K." },
  started_at: "2026-11-14T00:12:00Z",
  armed_group_ids: armed,
});
const groupWith = (armed: string[]) =>
  groupOf({
    uplink: {
      spacecraft: { id: "sc-1", name: "EARENDIL-001" },
      pass: null,
      next_pass: null,
      readiness: null,
      contact: contact(armed),
    },
  });
const released = {
  realized_contact_id: "rc-9",
  booked: false,
  results: [
    {
      command_group_id: "grp-0",
      outcome: "released",
      released_entry_ids: ["e-1"],
      not_attempted_entry_ids: [],
      stopped: null,
      refused: null,
    },
  ],
};
const reply = (body: unknown) =>
  new Response(JSON.stringify({ data: body }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
// The danger sheet: answered yes at once.
const ConfirmDialog = defineComponent({
  setup(_props, { expose }) {
    expose({ ask: () => Promise.resolve(true) });
    return () => h("div");
  },
});

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

async function release(focusElsewhere = false) {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(reply(released)));
  const w = mount(ContactRelease, {
    props: { group: groupWith(["grp-0"]), missionId: missionId("m-1"), canRelease: true },
    global: { stubs: { ConfirmDialog } },
    attachTo: document.body,
  });
  const button = w.findAll("button").find((b) => b.text() === "Release commands…");
  if (!button) throw new Error("no Release");
  if (button.element instanceof HTMLElement) button.element.focus();
  await button.trigger("click");
  await flushPromises();
  const elsewhere = document.createElement("button");
  document.body.appendChild(elsewhere);
  if (focusElsewhere) elsewhere.focus();
  return { w, elsewhere };
}

describe("ContactRelease after a release", () => {
  it("a clean release: the result stays, and focus on Release follows it", async () => {
    const { w } = await release();
    await w.setProps({ group: groupWith([]) });
    await flushPromises();
    const status = w.get('[role="status"]');
    expect(status.text()).toBe("Released 1 request.");
    expect(document.activeElement).toBe(status.element);
    w.unmount();
  });

  it("leaves focus alone when the person moved on before the callout went", async () => {
    const { w, elsewhere } = await release(true);
    await w.setProps({ group: groupWith([]) });
    await flushPromises();
    expect(w.get('[role="status"]').text()).toBe("Released 1 request.");
    expect(document.activeElement).toBe(elsewhere);
    w.unmount();
  });

  it("a partial release keeps the callout, so focus doesn't move", async () => {
    const { w } = await release();
    const before = document.activeElement;
    await w.setProps({ group: groupWith(["grp-1"]) });
    await flushPromises();
    expect(document.activeElement).toBe(before);
    w.unmount();
  });
});

describe("AbortPanel's result goes up", () => {
  it("emits the aborted line for the view to say (the panel goes once it can't abort)", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(reply(groupOf())));
    const w = mount(AbortPanel, { props: { group: groupOf() }, attachTo: document.body });
    await w.get("button[aria-controls]").trigger("click");
    await flushPromises();
    await w.get("textarea").setValue("wrong target");
    await w
      .findAll("button")
      .find((b) => b.text() === "Abort remaining uplinks")
      ?.trigger("click");
    await flushPromises();
    const done = w.emitted("done");
    expect(done?.[0]?.[0]).toMatch(/^Aborted: \d+ canceled/);
    w.unmount();
  });
});
