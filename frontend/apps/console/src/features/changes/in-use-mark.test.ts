import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId, type ApiError } from "@/api";
import ChangeList from "./ChangeList.vue";
import { inUseMark, refusalOutcome } from "./refusals.ts";
import { configStateReader } from "./shapes.ts";

/** ux U82: after an apply-time in-use refusal, the archive's row in the set carries a crit mark. */
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useSession: () => ({ user: { id: "u1" } }),
}));

const actor = { kind: "user", id: "u1", name: "Mira K." };
const change = (id: string, entity: string, summary: string) => ({
  id,
  summary,
  author: actor,
  staged_at: "2026-11-16T21:00:00Z",
  source: { surface: "transports" },
  state: "staged",
  ops: [
    {
      id: `o-${id}`,
      kind: "transport",
      entity_id: entity,
      action: "delete",
      paths: [],
      payload: null,
    },
  ],
});
function config() {
  const r = decode(configStateReader, {
    head: {
      revision: 5,
      kind: "change_set",
      live: true,
      applied_at: "2026-11-16T02:29:00Z",
      applied_by: actor,
      reason: "r5",
      summary: null,
      entry_count: 1,
      change_set_id: null,
      rolls_back_to: null,
      approvals: [],
    },
    change_set: {
      id: "cs-1",
      version: 1,
      state: "open",
      base_revision: 5,
      opened_at: "2026-11-16T21:00:00Z",
      opened_by: actor,
      staged_count: 2,
      changes: [
        change("c-1", "t-1", "Archive transport INU S-band"),
        change("c-2", "t-2", "Archive transport SVB X-band"),
      ],
      withdrawn: [],
      authors: [actor],
      submitted_by: null,
      submitted_at: null,
      reason: null,
      approval_required: null,
      reviews: [],
      failure: null,
      applied_revision: null,
    },
    permissions: ["config.stage"],
  });
  if (!r.ok || !r.value.change_set) throw new Error("fixture");
  return { state: r.value, set: r.value.change_set };
}
const none = { count: 0, items: [] };
const refused: ApiError = {
  kind: "conflict",
  code: "in_use",
  message: "in use",
  details: {
    entity: { kind: "transport", id: "t-1", name: "INU S-band" },
    uses: {
      routes: none,
      profile_routes: none,
      booked_passes: { count: 1, next_at: "2026-11-17T03:10:00Z" },
      listening_now: none,
      transports: none,
    },
  },
};

describe("the in-use row mark (ux U82)", () => {
  it("names the refused entity, as a sentence for the row", () => {
    expect(inUseMark(refusalOutcome(refused, "applied"))).toEqual({
      entityId: "t-1",
      sentence: "INU S-band is in use now, so this change set can't be applied.",
    });
    expect(
      inUseMark(refusalOutcome({ kind: "unavailable", status: 0, message: "" }, "applied")),
    ).toBeNull();
  });

  it("marks only the row whose op is that entity", () => {
    const { state, set } = config();
    const w = mount(ChangeList, {
      props: {
        missionId: missionId("m-1"),
        config: state,
        changeSet: set,
        conflicts: new Map(),
        inUse: inUseMark(refusalOutcome(refused, "applied")),
      },
    });
    const rows = w.findAll("li");
    expect(rows[0]?.text()).toContain(
      "INU S-band is in use now, so this change set can't be applied.",
    );
    expect(rows[0]?.find(".ap-mark--crit").exists()).toBe(true);
    expect(rows[1]?.text()).not.toContain("in use now");
    w.unmount();
  });
});
