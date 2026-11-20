import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId, type ApiError } from "@/api/index.ts";
import { modelRevisionReader, type ModelRevision } from "./api.ts";
import { rolloutGate } from "./rollout-gate.ts";
import WithdrawControl from "./WithdrawControl.vue";
import { withdrawFailure } from "./withdraw-words.ts";
import { approvalTag, decidedLine, decisionFailure } from "./words.ts";

/** E2 (#546; U109 in #615): withdrawing a catalog revision's approval, readers first. */
type Withdraw = typeof import("./api.ts").withdrawRevision;
const call = vi.hoisted(() => ({ fn: vi.fn<Withdraw>() }));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  withdrawRevision: (...args: Parameters<Withdraw>) => call.fn(...args),
}));
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useSession: () => ({ user: { id: "u-me" } }),
}));
afterEach(() => call.fn.mockReset());

const at = "2026-11-20T09:12:00Z";
const read = (o: Record<string, unknown> = {}): ModelRevision => {
  const r = decode(modelRevisionReader, {
    id: "mm-4",
    status: "approved",
    imported_at: null,
    imported_by: null,
    catalog_revision: { id: "cr-4", number: 4, label: null, database_id: "db" },
    decision: {
      kind: "approved",
      by: { kind: "user", id: "u-ana", name: "Ana R." },
      at,
      report_id: null,
      reason: null,
    },
    viewer_can_decide: false,
    viewer_is_importer: false,
    cannot_decide_because: null,
    plans_ready: true,
    comparison: null,
    ...o,
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};
const conflict = (code: string, details: unknown = null): ApiError => ({
  kind: "conflict",
  code,
  message: "x",
  details,
});

describe("reading a withdrawn revision", () => {
  it("reads the status, a nameless decision, and the WITHDRAWN tag", () => {
    const r = read({
      status: "withdrawn",
      decision: {
        kind: "withdrawn",
        by: null,
        at,
        reason: "Wrong FSW",
        report_id: null,
        retroactive: false,
      },
    });
    expect(decidedLine(r)).toMatch(/^Withdrawn at .+: “Wrong FSW”\.$/);
    expect(approvalTag(r.status)).toEqual({ label: "WITHDRAWN", state: "off" });
    expect(rolloutGate(r)).toEqual({
      kind: "line",
      line: "Catalog rev 4's approval was withdrawn, so spacecraft can't move to it.",
    });
  });

  it("says why Approve was refused on a withdrawn revision (backstop)", () => {
    expect(
      decisionFailure(conflict("mission_model_revision_not_approvable", { status: "withdrawn" }), 4)
        .text,
    ).toBe(
      "Not approved: catalog rev 4's approval was withdrawn, and it can't be approved again for now. Your approval wasn't recorded.",
    );
  });
});

describe("the withdraw refusals", () => {
  const not = (details: unknown) =>
    withdrawFailure(
      conflict("mission_model_revision_not_withdrawable", details),
      "catalog rev 4",
      "u-me",
    );
  it("words each status, with who and when when known", () => {
    expect(not({ status: "candidate", decided_by: null, decided_at: null }).text).toBe(
      "Not withdrawn: catalog rev 4 isn't approved, so there's nothing to withdraw. Nothing changed.",
    );
    expect(
      not({ status: "rejected", decided_by: { id: "u-ana", name: "Ana R." }, decided_at: at }).text,
    ).toMatch(
      /^Catalog rev 4 was rejected by Ana R\. at .+, so there's nothing to withdraw\. Nothing changed\.$/,
    );
    expect(
      not({ status: "withdrawn", decided_by: { id: "u-me", name: "Mira K." }, decided_at: at })
        .text,
    ).toMatch(/^You already withdrew its approval at .+\. Reload to see it\.$/);
    expect(not({ status: "withdrawn", decided_by: null, decided_at: null }).text).toBe(
      "Not withdrawn: its approval was already withdrawn, so nothing changed. Reload to see it.",
    );
    expect(not({ status: "retired", decided_by: null, decided_at: null }).text).toBe(
      "Not withdrawn: catalog rev 4 is retired, so its approval can't be withdrawn. Nothing changed.",
    );
    expect(not({ status: "quarantined" })).toEqual({
      text: "Not withdrawn: catalog rev 4 can't be withdrawn as it stands, so nothing changed. Reload to see it.",
      code: "quarantined",
    });
  });

  it("puts a reason refusal on the field, and words 403s", () => {
    expect(
      withdrawFailure(
        {
          kind: "invalid",
          code: "mission_model_decision_reason_required",
          message: "x",
          details: null,
        },
        "catalog rev 4",
        null,
      ),
    ).toEqual({ text: null, field: "Say why." });
    expect(
      withdrawFailure({ kind: "forbidden", code: "forbidden", message: "x" }, "catalog rev 4", null)
        .text,
    ).toBe("Not withdrawn: only an org admin can withdraw an approval. Nothing changed.");
  });
});

describe("Withdraw approval…", () => {
  const key = { missionId: missionId("m1"), revisionId: "mm-4" };
  const mountIt = (r: ModelRevision) =>
    mount(WithdrawControl, { props: { revision: r, modelKey: key }, attachTo: document.body });

  it("shows only to someone who can withdraw an approved revision", () => {
    expect(mountIt(read()).find("button").exists()).toBe(false);
    const w = mountIt(read({ viewer_can_withdraw: true }));
    expect(w.get("button").attributes("aria-label")).toBe("Withdraw approval of catalog rev 4");
    w.unmount();
  });

  it("withdraws with a reason, says so once, and replays a retry with the same id", async () => {
    call.fn
      .mockResolvedValueOnce({ ok: false, error: { kind: "unavailable", status: 0, message: "x" } })
      .mockResolvedValueOnce({ ok: true, value: read({ status: "withdrawn" }) });
    const w = mountIt(read({ viewer_can_withdraw: true }));
    await w.get("button").trigger("click");
    await w.get("textarea").setValue("Wrong FSW build");
    // The sheet's commit, not the opener (whose text is "Withdraw approval…").
    const commit = () =>
      w
        .findAll("button")
        .filter((b) => b.text().startsWith("Withdraw approval") && !b.text().includes("…"))
        .at(-1);
    await commit()?.trigger("click");
    await flushPromises();
    await commit()?.trigger("click");
    await flushPromises();
    const ids = call.fn.mock.calls.map((c) => c[2]);
    expect(call.fn.mock.calls[0]?.[1]).toBe("Wrong FSW build");
    expect(ids[0]).toBe(ids[1]);
    expect(w.text()).toContain(
      "Approval withdrawn. Spacecraft on catalog rev 4 can't take a new configuration that uses it.",
    );
    expect(w.emitted("changed")).toHaveLength(1);
    w.unmount();
  });
});
