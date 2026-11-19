import { nextTick } from "vue";
import { stationId as stationIdReader } from "@/api/index.ts";
import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { PlanDetail } from "./api.ts";
import SubmitSheet from "./SubmitSheet.vue";
import { station } from "./fixtures.ts";

const gap = (id: string) => ({
  requirement_id: id,
  requirement_version: 1,
  spacecraft_id: `sc-${id}`,
  why: ["minimum_duration_not_met"],
});
const plan: PlanDetail = {
  id: "plan_1",
  version: 41,
  state: "draft",
  window: { from: null, to: null },
  author: null,
  counts: { passes: 12, minutes: 96, conflicts: 0, unsatisfied: 2 },
  ready_to_approve: false,
  updated_at: "2026-11-09T10:00:00Z",
  created_at: null,
  passes: [],
  demand: { rule_met: 1, rule_total: 3, spacecraft: [], rules: [] },
  unmet: [gap("r1"), gap("r2")],
  conflicts: [],
  at_risk: [],
  unconfirmed: null,
  chain: null,
  execution: null,
  provider_freeze: null,
  approval: null,
  submission: null,
  previous_round: null,
  chain_head: null,
  superseded: null,
  repair_of: null,
  superseded_by: null,
  latest_version: undefined,
  repair: undefined,
};

describe("SubmitSheet", () => {
  it("needs a valid reason for every gap; 'same for all' fills the rest; emits acknowledgements", async () => {
    const wrapper = mount(SubmitSheet, {
      props: {
        plan,
        nameOf: () => null,
        commitLabel: "Accept 2 gaps and submit",
        title: "Approve and book the plan",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    expect(wrapper.text()).toContain("2 gaps still need a reason");
    expect(wrapper.text()).toContain("Accept 2 gaps ·"); // gaps title the sheet, not the act
    expect(wrapper.text()).not.toContain("Approve and book the plan");
    const [first] = wrapper.findAll("textarea");
    await first?.setValue("Station maintenance accepted by ops.");
    expect(wrapper.text()).toContain("1 gap still needs a reason");
    await wrapper.get("input[type=checkbox]").setValue(true);
    expect(wrapper.text()).not.toContain("still need");
    await wrapper.findAll("footer button").at(-1)?.trigger("click");
    expect(wrapper.emitted("submit")).toEqual([
      [
        [
          { requirement_id: "r1", reason: "Station maintenance accepted by ops." },
          { requirement_id: "r2", reason: "Station maintenance accepted by ops." },
        ],
      ],
    ]);
    wrapper.unmount();
  });

  it("ticked first, one shared box covers every gap (qa #27); causes print once (qa #26)", async () => {
    const twice = { ...gap("r2"), why: ["provider_unavailable", "provider_unavailable"] };
    const wrapper = mount(SubmitSheet, {
      props: {
        plan: { ...plan, unmet: [gap("r1"), twice] },
        nameOf: () => null,
        commitLabel: "Accept 2 gaps and submit",
        title: "Approve and book the plan",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    await wrapper.get("input[type=checkbox]").setValue(true);
    // One shared reason box, plus U76's note for the record (always last).
    expect(wrapper.findAll("textarea")).toHaveLength(2);
    await wrapper.get("textarea").setValue("Past windows on today's draft.");
    expect(wrapper.text()).not.toContain("still need");
    expect(wrapper.findAll("li").at(-1)?.text()).toBe("r2 · Provider reports no availability");
    await wrapper.findAll("footer button").at(-1)?.trigger("click");
    expect(wrapper.emitted("submit")?.[0]?.[0]).toEqual([
      { requirement_id: "r1", reason: "Past windows on today's draft." },
      { requirement_id: "r2", reason: "Past windows on today's draft." },
    ]);
    wrapper.unmount();
  });

  it("refuses reasons shorter than 10 characters", async () => {
    const wrapper = mount(SubmitSheet, {
      props: {
        plan: { ...plan, unmet: [gap("r1")] },
        nameOf: () => null,
        commitLabel: "Accept 1 gap and submit",
        title: "Approve and book the plan",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    await wrapper.get("textarea").setValue("too short");
    await wrapper.findAll("footer button").at(-1)?.trigger("click");
    expect(wrapper.emitted("submit")).toBeUndefined();
    wrapper.unmount();
  });
});

describe("SubmitSheet per-spacecraft gaps (U23 amended)", () => {
  it("asks one reason per spacecraft and acknowledges each of its requirements", async () => {
    const two = {
      ...plan,
      unmet: [
        { ...gap("r1"), spacecraft_id: "sc-a" },
        { ...gap("r2"), spacecraft_id: "sc-a" },
      ],
    };
    const wrapper = mount(SubmitSheet, {
      props: {
        plan: two,
        nameOf: () => null,
        commitLabel: "Accept 1 gap and submit",
        title: "Approve and book the plan",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    expect(wrapper.get("h2").text()).toContain("Accept 1 gap");
    await wrapper.findAll("textarea")[0]?.setValue("Both windows are under the minimum.");
    await wrapper.findAll("footer button").at(-1)?.trigger("click");
    expect(wrapper.emitted("submit")).toEqual([
      [
        [
          { requirement_id: "r1", reason: "Both windows are under the minimum." },
          { requirement_id: "r2", reason: "Both windows are under the minimum." },
        ],
      ],
    ]);
    wrapper.unmount();
  });
});

describe("SubmitSheet dialog (ux K1 #8)", () => {
  it("is a labelled modal and focuses the first reason on open", async () => {
    const wrapper = mount(SubmitSheet, {
      props: {
        plan,
        nameOf: () => null,
        commitLabel: "Accept 2 gaps and submit",
        title: "Approve and book the plan",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    const dialog = wrapper.get("dialog");
    expect(dialog.attributes("aria-modal")).toBe("true");
    expect(wrapper.get(`#${dialog.attributes("aria-labelledby") ?? "missing"}`).text()).toContain(
      "Accept 2 gaps",
    );
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open(); the lint type service can't resolve SFC instances.
    wrapper.vm.open();
    await new Promise((r) => setTimeout(r, 0));
    expect(document.activeElement?.tagName).toBe("TEXTAREA");
    wrapper.unmount();
  });
});

describe("SubmitSheet at-risk passes (ux #13)", () => {
  it("lists passes on a degraded station before booking", () => {
    const risky = {
      ...plan,
      unmet: [],
      passes: [
        {
          snapshot_id: "p1",
          spacecraft_id: "sc-a",
          station: station({ ref: "kir", id: "gs-kir", code: "KIR", name: "Kiruna" }),
          starts_at: "2026-11-11T00:12:00Z",
          ends_at: "2026-11-11T00:20:00Z",
          synthetic: true,
          locked: false,
          expires_at: null,
          booking: null,
        },
      ],
      at_risk: [
        {
          code: "station_degraded" as const,
          snapshot_ids: ["p1"],
          spacecraft_id: undefined,
          ground_station_id: stationIdReader("gs-kir"),
          window_id: "w",
          kind: "degraded" as const,
        },
      ],
    };
    const wrapper = mount(SubmitSheet, {
      props: {
        plan: risky,
        nameOf: () => ({ name: "EARENDIL-003", scid: 3 }),
        commitLabel: "Submit and book 1 pass",
        title: "Approve and book the plan",
        confirm: "c",
        busy: false,
      },
      attachTo: document.body,
    });
    expect(wrapper.text()).toContain("Approve and book the plan"); // the act, not 'Submit the plan' (U36)
    expect(wrapper.text()).toContain("1 pass on a degraded station may lose data");
    expect(wrapper.text()).toContain("EARENDIL-003 · KIR · 00:12–00:20Z");
    wrapper.unmount();
  });
});

describe("SubmitSheet note for the record (U76)", () => {
  it("offers the note on every submit, with U76's label, hint and a counter from 1,800", async () => {
    const wrapper = mount(SubmitSheet, {
      props: {
        plan,
        nameOf: () => null,
        commitLabel: "Submit",
        title: "Submit",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open(); the lint type service can't resolve SFC instances.
    wrapper.vm.open();
    await nextTick();
    expect(wrapper.text()).toContain("Note for the record (optional)");
    expect(wrapper.text()).toContain("Saved with your name in the plan's history.");
    const note = wrapper.findAll("textarea").at(-1);
    expect(note?.attributes("maxlength")).toBe("2000");
    await note?.setValue("x".repeat(1850));
    expect(wrapper.text()).toContain("1,850 / 2,000");
    wrapper.unmount();
  });
});

describe("SubmitSheet resubmission (U36)", () => {
  it("prefills last round's reasons and sends the optional note", async () => {
    const sentBack = {
      ...plan,
      approval: {
        decision: "rejected" as const,
        actor: { kind: "user" as const, id: "u", name: "Mira K." },
        at: "2026-11-09T10:52:00Z",
        reason: "Move 004 off HBK",
        exceptions: [],
      },
      previous_round: {
        round: 1,
        version: 41,
        approval: null,
        acknowledgements: [
          { requirement_id: "r1", reason: "Outage at HBK, accepted by ops." },
          { requirement_id: "r2", reason: "Outage at HBK, accepted by ops." },
        ],
      },
    };
    const wrapper = mount(SubmitSheet, {
      props: {
        plan: sentBack,
        nameOf: () => null,
        commitLabel: "Accept 2 gaps and submit again",
        title: "Approve and book the plan",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open(); the lint type service can't resolve SFC instances.
    wrapper.vm.open();
    await nextTick();
    expect(wrapper.text()).not.toContain("still need");
    // U76: the note for the record is the sheet's last field.
    await wrapper.findAll("textarea").at(-1)?.setValue("Moved 004 to KIR.");
    await wrapper.findAll("footer button").at(-1)?.trigger("click");
    const [acks, note] = wrapper.emitted("submit")?.[0] ?? [];
    expect(note).toBe("Moved 004 to KIR.");
    expect(acks).toHaveLength(2);
    wrapper.unmount();
  });
});
