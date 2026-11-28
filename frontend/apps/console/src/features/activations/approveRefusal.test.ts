import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader, type ApiError } from "@/api/index.ts";
import ActivationDecide from "./ActivationDecide.vue";
import type { ActivationDetail } from "./api.ts";
import { approveRefusal } from "./approveRefusal.ts";

const conflict = (code: string, details?: unknown): ApiError => ({
  kind: "conflict",
  code,
  message: "x",
  details,
});
const said = (code: string, details?: unknown) => approveRefusal(conflict(code, details));
const END = " Your approval wasn't recorded.";

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

/** ux U95: Approve refused by domain's preflight; nothing recorded. */
describe("approve refusals (U95)", () => {
  it("words each preflight code, ending that nothing was recorded", () => {
    expect(said("approved_activation_content_mismatch")?.text).toBe(
      `Not approved: what this request would apply changed after it was requested, so it isn't what you reviewed. The requester sends it again.${END}`,
    );
    expect(said("mission_model_revision_not_in_catalog")?.text).toBe(
      `Not approved: the catalog doesn't list the revision this request uses, so it can't apply. The requester sends a request for a revision the catalog lists.${END}`,
    );
    expect(said("activation_policy_changed")?.text).toContain(
      "the mission's approval setting changed",
    );
    expect(said("change_set_activation_stale")?.text).toContain(
      "what's running on this mission changed",
    );
    expect(said("mission_model_activation_manifest_required")?.text).toContain(
      "if it keeps happening, tell the team that runs Cadence.",
    );
    expect(said("mission_model_comparison_report_required")?.link?.label).toBe("Open the catalog");
    expect(said("mission_model_runtime_plans_not_ready")?.final).toBe(false);
  });

  it("names catalog revs: one with Open rev N, several up to 3, none by number", () => {
    const one = said("mission_model_revision_not_approved", {
      catalog_revisions: [{ id: "cr-4", number: 4, mission_model_revision_id: "mm-4" }],
    });
    expect(one?.text).toContain(
      "catalog rev 4 isn't approved yet, so this can't apply. An org admin approves it",
    );
    expect(one?.link).toEqual({
      label: "Open rev 4",
      to: { name: "setup.catalog.model", params: { revisionId: "mm-4" } },
    });
    const many = said("mission_model_revision_not_approved", {
      catalog_revisions: [4, 5, 6, 7, 8].map((n) => ({
        id: `cr-${n}`,
        number: n,
        mission_model_revision_id: `mm-${n}`,
      })),
    });
    expect(many?.text).toContain("catalog revs 4, 5, 6 and 2 more aren't approved yet");
    expect(many?.text).toContain("approves them");
    expect(many?.link?.label).toBe("Open the catalog");
    const none = said("mission_model_revision_not_approved", {
      catalog_revisions: [{ id: null, number: null, mission_model_revision_id: "mm-9" }],
    });
    expect(none?.text).toContain("a catalog revision it uses isn't approved yet");
  });

  it("comparison failed: the rev and Open the report; without a number, the revision it uses", () => {
    const c = said("mission_model_comparison_failed", {
      catalog_revision: { id: "cr-4", number: 4 },
      comparison_report_id: "rep-1",
      mission_model_revision_id: "mm-4",
    });
    expect(c?.text).toBe(
      `Not approved: catalog rev 4's comparison didn't pass, so this can't apply.${END}`,
    );
    expect(c?.link?.label).toBe("Open the report");
    const n = said("mission_model_comparison_failed", {
      catalog_revision: null,
      comparison_report_id: "rep-1",
    });
    expect(n?.text).toContain("the comparison for the catalog revision it uses didn't pass");
    expect(n?.link?.label).toBe("Open the catalog");
  });

  it("review stale names the craft: one, several, or a spacecraft", () => {
    const sc = (...names: string[]) => ({
      spacecraft: names.map((name, i) => ({ id: `sc-${i}`, name })),
    });
    expect(said("spacecraft_configuration_review_stale", sc("EARENDIL-004"))?.text).toContain(
      "Not approved: EARENDIL-004's configuration changed after this was requested",
    );
    expect(
      said("spacecraft_configuration_review_stale", sc("EARENDIL-004", "EARENDIL-005"))?.text,
    ).toContain("the configuration of EARENDIL-004 and EARENDIL-005 changed");
    expect(said("spacecraft_configuration_review_stale")?.text).toContain(
      "a spacecraft's configuration changed",
    );
  });

  it("an unworded code: the generic line, its code for Technical details; older refusals aren't U95's", () => {
    const g = said("invalid_spacecraft_model_bindings");
    expect(g?.text).toBe(`Not approved: this request can't apply as it stands.${END}`);
    expect(g?.code).toBe("invalid_spacecraft_model_bindings");
    expect(said("not_pending")).toBeNull();
    expect(
      approveRefusal({ kind: "forbidden", code: "self_approval_forbidden", message: "x" }),
    ).toBeNull();
  });
});

describe("U95 additions", () => {
  it("configuration review required: reject it and send it from the spacecraft", () => {
    expect(said("spacecraft_configuration_review_required")?.text).toBe(
      `Not approved: on this mission, changes are activated from each spacecraft's configuration (Setup › Spacecraft), so this request can't apply. Reject it, and send the change from the spacecraft's configuration instead.${END}`,
    );
  });

  it("model not active names the craft, skips unknown names, else 'a spacecraft'", () => {
    const craft = (...names: (string | null)[]) => ({
      spacecraft_ids: names.map((_, i) => `sc-${i}`),
      spacecraft: names.map((name, i) => ({ id: `sc-${i}`, name })),
    });
    expect(said("spacecraft_model_not_active", craft("EARENDIL-004"))?.text).toBe(
      `Not approved: the catalog revision EARENDIL-004 was reviewed with isn't the active one any more, so this isn't what was reviewed. The requester sends it again.${END}`,
    );
    expect(said("spacecraft_model_not_active", craft("EARENDIL-004", null))?.text).toContain(
      "the catalog revision EARENDIL-004 was reviewed with",
    );
    expect(said("spacecraft_model_not_active", craft(null))?.text).toContain(
      "the catalog revision a spacecraft was reviewed with",
    );
    expect(
      said("spacecraft_configuration_review_stale", craft(null, "EARENDIL-005"))?.text,
    ).toContain("EARENDIL-005's configuration changed");
  });
});

describe("the decide panel after a refused Approve (U95)", () => {
  const detail: ActivationDetail = {
    id: "act_1",
    kind: "spacecraft_configuration",
    summary: "Spacecraft configuration for EARENDIL-004",
    binding_set: { id: "bs_1", version: 4 },
    requested_by: { kind: "user", id: "u1", name: "Mira K." },
    requested_at: "2026-11-13T02:10:00Z",
    state: "approval_pending",
    decision: null,
    execution: null,
    can_decide: true,
    superseded_by: undefined,
    superseded_at: undefined,
    details: [],
    comparison: null,
    permissions: undefined,
    configuration_changes: undefined,
  };

  it("shows the line, turns Approve off with it, and keeps Reject", async () => {
    const fetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>();
    fetch.mockResolvedValueOnce(
      new Response(
        JSON.stringify({ error: { code: "change_set_activation_stale", message: "x" } }),
        { status: 409, headers: { "content-type": "application/json" } },
      ),
    );
    vi.stubGlobal("fetch", fetch);
    const w = mount(ActivationDecide, {
      props: {
        requestKey: { missionId: missionIdReader("m-1"), requestId: "act_1" },
        request: detail,
        viewer: { userId: "u2", orgAdmin: true },
        index: "R2",
      },
      global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } },
      attachTo: document.body,
    });
    await w.find("textarea").setValue("Looks right.");
    const approve = () => w.findAll("button").find((b) => b.text().startsWith("Approve and apply"));
    await approve()?.trigger("click");
    await flushPromises();
    const text = `Not approved: what's running on this mission changed after this was requested, so it isn't what was reviewed. The requester sends it again.${END}`;
    expect(w.find('[role="alert"]').text()).toContain(text);
    expect(approve()?.attributes("aria-disabled")).toBe("true");
    expect(approve()?.attributes("title")).toBe(text);
    const reject = w.findAll("button").find((b) => b.text().startsWith("Reject"));
    expect(reject?.attributes("aria-disabled")).toBeUndefined();
    w.unmount();
  });
});
