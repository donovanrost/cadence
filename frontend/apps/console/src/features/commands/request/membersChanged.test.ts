import { flushPromises, mount } from "@vue/test-utils";
import { computed } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId } from "@/api/index.ts";
import { preflightReader } from "../groups/api.ts";
import { groupOf } from "../groups/fixtures.ts";
import DecisionPanel from "./DecisionPanel.vue";
import { membersChangedLine } from "./decision.ts";

vi.mock("@/live/index.ts", async (original) => ({
  ...(await original<typeof import("@/live/index.ts")>()),
  useMissionInvalidation: () => undefined,
}));
vi.mock("@/shell/index.ts", async (original) => ({
  ...(await original<typeof import("@/shell/index.ts")>()),
  useMissionScope: () => computed(() => ({ mission: { id: missionId("m-1"), name: "EARENDIL" } })),
}));
afterEach(() => {
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

const clean = decode(preflightReader, {
  valid: true,
  digest: "d",
  members: 2,
  second_go_required: true,
  targets: [],
  checks: [],
});
if (!clean.ok) throw clean.error;
const LINE =
  "Not released: this group's commands changed after it was submitted, so it isn't what was reviewed. Give it NO-GO and submit the commands again. Tell the team that runs Cadence for you: a group shouldn't change after it's submitted.";
const refusal = (details: unknown = null) =>
  new Response(
    JSON.stringify({ error: { code: "command_group_members_changed", message: "x", details } }),
    { status: 409, headers: { "content-type": "application/json" } },
  );

/** ux U92: a GO refused because the group's commands changed after it was submitted. */
describe("command_group_members_changed (U92)", () => {
  it("words the refusal, with both counts when the 409 carries them", () => {
    expect(membersChangedLine(null)).toBe(LINE);
    expect(membersChangedLine({ submitted_member_count: 12, current_member_count: 13 })).toBe(
      LINE.replace("submitted, so", "submitted (12 then, 13 now), so"),
    );
    expect(membersChangedLine({ submitted_member_count: 12 })).toBe(LINE);
  });

  it("after the refusal GO stays off with the line as its reason; NO-GO stays the way out", async () => {
    // #795: the panel also reads the log and the HOLD acks (empty here); the decision is refused.
    const empty = (key: string) =>
      new Response(JSON.stringify({ data: { [key]: [] }, meta: { next_cursor: null, total: 0 } }), {
        status: 200,
      });
    const fetch = vi.fn((url: string, init?: RequestInit) =>
      Promise.resolve(
        init?.method === "POST"
          ? refusal()
          : url.includes("/events")
            ? empty("events")
            : empty("names"),
      ),
    );
    vi.stubGlobal("fetch", fetch);
    const decisions = () => fetch.mock.calls.filter(([, init]) => init?.method === "POST");
    const w = mount(DecisionPanel, {
      props: {
        group: groupOf(),
        review: clean.value,
        viewerId: "user-2",
        canApprove: true,
        nameOf: (id: string | null) => id ?? "someone",
        targetName: (id: string) => id,
      },
      attachTo: document.body,
    });
    await flushPromises();
    await w.get('input[value="go"]').setValue(true);
    const commit = () => w.findAll("button").find((b) => b.text().startsWith("Sign GO"));
    await commit()?.trigger("click");
    await flushPromises();
    expect(w.emitted("decided")).toBeUndefined();
    expect(decisions()).toHaveLength(1);
    expect(w.find('[role="alert"]').text()).toBe(LINE);
    expect(w.text()).not.toContain("Not recorded");
    expect(commit()?.attributes("aria-disabled")).toBe("true");
    expect(commit()?.attributes("title")).toBe(LINE);
    await w.get('input[value="no_go"]').setValue(true);
    // NO-GO only waits for its note; the changed group doesn't block it.
    const noGo = w.findAll("button").find((b) => b.text().startsWith("Sign NO-GO"));
    expect(noGo?.attributes("title")).toBe("Add a note to no-go.");
    w.unmount();
  });
});
