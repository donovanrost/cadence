import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api";
import StagedArchive from "./StagedArchive.vue";

/** ux U82: Archive… stages the kind's delete; an in-use refusal goes to the page, others stay in place. */
const api = vi.hoisted(() => ({
  result: { ok: true, value: null } as unknown,
  sent: [] as unknown[],
  push: vi.fn(() => Promise.resolve()),
}));
vi.mock("./actions.ts", async (original) => ({
  ...(await original<typeof import("./actions.ts")>()),
  stageChange: (_m: unknown, body: unknown) => {
    api.sent.push(body);
    return Promise.resolve(api.result);
  },
}));
vi.mock("./useConfigState.ts", async (original) => ({
  ...(await original<typeof import("./useConfigState.ts")>()),
  refreshConfigState: () => undefined,
}));
vi.mock("vue-router", async (original) => ({
  ...(await original<typeof import("vue-router")>()),
  useRouter: () => ({ push: api.push }),
}));

let wrapper: ReturnType<typeof mount> | null = null;
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  api.sent = [];
  api.push.mockClear();
});
function render(variant: "menu" | "button") {
  wrapper = mount(StagedArchive, {
    props: {
      missionId: missionId("m-1"),
      kind: "transport",
      entityId: "t-1",
      name: "INU S-band",
      surface: "transports",
      variant,
    },
    attachTo: document.body,
  });
  return wrapper;
}
const click = async (label: string) => {
  [...document.querySelectorAll<HTMLElement>("button, [role=menuitem]")]
    .find((b) => b.textContent?.trim() === label)
    ?.click();
  await flushPromises();
};
const inUse = {
  ok: false,
  error: {
    kind: "conflict",
    code: "in_use",
    message: "in use",
    details: {
      entity: { kind: "transport", id: "t-1", name: "INU S-band" },
      uses: {
        routes: { count: 0, items: [] },
        profile_routes: { count: 0, items: [] },
        booked_passes: { count: 2, next_at: "2026-11-17T03:10:00Z" },
        listening_now: { count: 0, items: [] },
        transports: { count: 0, items: [] },
      },
    },
  },
};

describe("StagedArchive (ux U82)", () => {
  it("opens from the ⋯ menu, confirms in place and stages the delete with ux's summary", async () => {
    api.result = { ok: true, value: {} };
    render("menu");
    await click("⋯");
    await click("Archive…");
    expect(document.body.textContent).toContain(
      "Stage archiving INU S-band? Once the change set is applied, it can't be chosen for new routes or passes. Its history stays.",
    );
    await click("Stage archive");
    expect(api.sent).toEqual([
      {
        summary: "Archive transport INU S-band",
        source: { surface: "transports" },
        ops: [{ kind: "transport", action: "delete", entity_id: "t-1" }],
      },
    ]);
    expect(api.push).toHaveBeenCalledWith({ name: "setup.changes" });
  });

  it("hands an in-use refusal to the page, in place of the confirm", async () => {
    api.result = inUse;
    const w = render("button");
    await click("Archive…");
    await click("Stage archive");
    const refused = w.emitted("refused")?.[0]?.[0];
    expect(refused).toMatchObject({
      sentence: "INU S-band is still in use, so it can't be archived:",
      closing: "Move or remove these first.",
    });
    expect(document.body.textContent).not.toContain("Stage archiving INU S-band?");
    expect(api.push).not.toHaveBeenCalled();
  });

  it("reads any other refusal inside the confirm, which stays open", async () => {
    api.result = {
      ok: false,
      error: { kind: "conflict", code: "frozen_in_review", message: "", details: null },
    };
    const w = render("button");
    await click("Archive…");
    await click("Stage archive");
    expect(w.emitted("refused")).toBeUndefined();
    expect(document.body.textContent).toContain(
      "The change set is in review, so staging is paused.",
    );
    expect(document.body.textContent).toContain("Stage archiving INU S-band?");
  });
});
