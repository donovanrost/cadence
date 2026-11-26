import { mount } from "@vue/test-utils";
import { computed } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId } from "@/api/index.ts";
import { preflightReader } from "../groups/api.ts";
import { groupOf } from "../groups/fixtures.ts";
import DecisionPanel from "./DecisionPanel.vue";
import { decisionOptions, membersChangedUpFront } from "./decision.ts";

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

/** ux U92 "Up front" (#120): U92's line less "Not released: ", since nothing was tried. */
const UP_FRONT =
  "This group's commands changed after it was submitted (12 then, 13 now), so it isn't what was reviewed. Give it NO-GO and submit the commands again. Tell the team that runs Cadence for you: a group shouldn't change after it's submitted.";
const changed = { members_changed: true, submitted_member_count: 12, current_member_count: 13 };

describe("members_changed up front (ux U92, #120)", () => {
  it("words the read's flag, with the bracket only when both counts are there", () => {
    expect(membersChangedUpFront(groupOf(changed))).toBe(UP_FRONT);
    const bare = UP_FRONT.replace(" (12 then, 13 now)", "");
    expect(membersChangedUpFront(groupOf({ ...changed, submitted_member_count: null }))).toBe(bare);
    expect(membersChangedUpFront(groupOf({ ...changed, current_member_count: null }))).toBe(bare);
  });

  it("blocks nothing when the flag is false or null (U20: never guessed)", () => {
    expect(
      membersChangedUpFront(
        groupOf({ members_changed: false, submitted_member_count: 2, current_member_count: 2 }),
      ),
    ).toBeNull();
    expect(
      membersChangedUpFront(
        groupOf({
          members_changed: null,
          submitted_member_count: null,
          current_member_count: null,
        }),
      ),
    ).toBeNull();
    expect(membersChangedUpFront(groupOf())).toBeNull();
  });

  it("the GO options carry the reason as their description; send back and NO-GO don't", () => {
    const flagged = [{ spacecraftId: "sc-1", name: "SC-1" }];
    const options = decisionOptions(groupOf({ ...changed, target_count: 2 }), flagged);
    const by = (v: string) => options.find((o) => o.value === v);
    expect(by("go")?.description).toBe(UP_FRONT);
    expect(by("go_excluding")?.description).toBe(UP_FRONT);
    expect(by("send_back")?.description).toBe("Returns it to the author with your note.");
    expect(by("no_go")?.description).toBe("Closes the request and logs why.");
    // Unchanged: the usual counts.
    const plain = decisionOptions(groupOf({ target_count: 2 }), flagged);
    expect(plain.find((o) => o.value === "go")?.description).not.toBe(UP_FRONT);
  });

  it("GO's commit is off before a click with the reason; NO-GO stays the way out", async () => {
    const fetch = vi.fn();
    vi.stubGlobal("fetch", fetch);
    const w = mount(DecisionPanel, {
      props: {
        group: groupOf(changed),
        review: clean.value,
        viewerId: "user-2",
        canApprove: true,
        nameOf: (id: string | null) => id ?? "someone",
        targetName: (id: string) => id,
      },
      attachTo: document.body,
    });
    await w.get('input[value="go"]').setValue(true);
    const commit = () => w.findAll("button").find((b) => b.text().startsWith("Sign GO"));
    expect(commit()?.attributes("aria-disabled")).toBe("true");
    expect(commit()?.attributes("title")).toBe(UP_FRONT);
    await commit()?.trigger("click");
    expect(fetch).not.toHaveBeenCalled();
    await w.get('input[value="no_go"]').setValue(true);
    const noGo = w.findAll("button").find((b) => b.text().startsWith("Sign NO-GO"));
    expect(noGo?.attributes("title")).toBe("Add a note to no-go.");
    w.unmount();
  });
});
