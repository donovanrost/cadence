import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api";
import { activeBody, json, proposalBody, refused } from "./grant-fixtures.ts";
import GrantsPanel from "./GrantsPanel.vue";

/** ux U105 (#283): the Grants panel, Waiting for approval, Narrow… and Revoke…, end to end. */
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useSession: () => ({ user: { id: "u3" } }),
}));

type Call = Readonly<{ url: string; method: string; body: Record<string, unknown> | null }>;
const read = (grants: readonly unknown[]) =>
  json({
    data: {
      grants,
      service_identities: [{ id: "svc_1", name: "Nightly planner", state: "active" }],
      limits: {
        maximum_horizon_seconds: null,
        maximum_contacts: null,
        maximum_execution_concurrency: null,
      },
      policy_version: 3,
      permissions: ["grants.manage"],
      approval_setting: "independent",
    },
  });

/** Stubs fetch: GETs answer the read, each POST the next queued answer; calls are recorded. */
function stub(grants: readonly unknown[], posts: Response[] = []) {
  const calls: Call[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((url: string, init?: RequestInit) => {
      const method = init?.method ?? "GET";
      const raw = typeof init?.body === "string" ? init.body : null;
      const body: unknown = raw ? JSON.parse(raw) : null;
      calls.push({
        url,
        method,
        body:
          body !== null && typeof body === "object" && !Array.isArray(body) ? { ...body } : null,
      });
      return Promise.resolve(method === "GET" ? read(grants) : (posts.shift() ?? read(grants)));
    }),
  );
  return calls;
}
async function panel() {
  const w = mount(GrantsPanel, {
    props: { missionId: missionId("m-1") },
    attachTo: document.body,
  });
  await flushPromises();
  return w;
}
/** The open sheet (a <dialog> with open set). */
const openSheet = (w: Awaited<ReturnType<typeof panel>>) => {
  const d = w
    .findAll("dialog")
    .find((x) => x.element instanceof HTMLDialogElement && x.element.open);
  if (!d) throw new Error("no open sheet");
  return d;
};
const posts = (calls: readonly Call[]) => calls.filter((c) => c.method === "POST");
const button = (w: Awaited<ReturnType<typeof panel>>, text: string) =>
  w.findAll("button").find((b) => b.text().startsWith(text));

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

describe("Waiting for approval (U105)", () => {
  it("approves at the hash read with an operation id; a retry of the same request reuses it", async () => {
    const calls = stub(
      [proposalBody],
      [refused(409, "duplicate_operation"), json({ data: { grant: activeBody, replayed: true } })],
    );
    const w = await panel();
    expect(w.text()).toContain("Waiting for approval");
    await button(w, "Approve grant for Nightly planner")?.trigger("click");
    await flushPromises();
    expect(w.get('[role="alert"]').text()).toContain("Not approved: Cadence matched this");
    await button(w, "Approve grant for Nightly planner")?.trigger("click");
    await flushPromises();
    const [first, second] = posts(calls);
    expect(first?.url).toContain("/contact-planning/grants/g2/approve");
    expect(first?.body).toMatchObject({ sha256: "abc" });
    expect(typeof first?.body?.["operation_id"]).toBe("string");
    expect(second?.body?.["operation_id"]).toBe(first?.body?.["operation_id"]);
    // A replay is shown as this one's result.
    expect(w.get('p[role="status"]').text()).toBe(
      "Approved. Nightly planner can act under it until 12-19 06:40Z.",
    );
  });

  it("A6: Approve off with the server's reason, muted under it; Reject stays", async () => {
    stub([{ ...proposalBody, viewer_can_decide: false, cannot_decide_because: "proposer" }]);
    const w = await panel();
    const approve = button(w, "Approve grant for Nightly planner");
    expect(approve?.attributes("aria-disabled") ?? approve?.attributes("disabled")).toBeDefined();
    expect(w.get("[data-grant-blocked]").text()).toBe(
      "You proposed this grant, so another org admin approves it.",
    );
    expect(button(w, "Reject…")?.attributes("disabled")).toBeUndefined();
  });

  it("a separation refusal keeps Approve off with the up-front line", async () => {
    stub(
      [proposalBody],
      [refused(403, "automation_grant_self_approval_forbidden", { because: "proposed" })],
    );
    const w = await panel();
    await button(w, "Approve grant for Nightly planner")?.trigger("click");
    await flushPromises();
    expect(w.get("[data-grant-blocked]").text()).toBe(
      "You proposed this grant, so another org admin approves it.",
    );
  });

  it("rejects with a reason and an operation id; the 422 field message shows under the field", async () => {
    const calls = stub(
      [proposalBody],
      [
        refused(422, "invalid_params", { reason: "Say why." }),
        json({ data: { grant: { ...proposalBody, state: "rejected" }, replayed: false } }),
      ],
    );
    const w = await panel();
    await button(w, "Reject…")?.trigger("click");
    await flushPromises();
    await openSheet(w).get("textarea").setValue("Too wide");
    const reject = w.findAll("button").filter((b) => b.text() === "Reject");
    await reject[reject.length - 1]?.trigger("click");
    await flushPromises();
    const sent = posts(calls)[0];
    expect(sent?.url).toContain("/grants/g2/reject");
    expect(sent?.body).toMatchObject({ reason: "Too wide" });
    expect(typeof sent?.body?.["operation_id"]).toBe("string");
    expect(document.body.textContent).toContain("Say why.");
  });
});

describe("rows, Narrow… and Revoke… (U105)", () => {
  it("a grant made before #283 says so, and Narrow is off with its reason; Revoke stays", async () => {
    stub([{ ...activeBody, viewer_can_narrow: false, issued_before_two_person_approval: true }]);
    const w = await panel();
    expect(w.text()).toContain(
      "Made before Cadence checked grants against the mission's approval setting, so it can only be revoked. To change it, propose a new grant.",
    );
    await w.get('button[aria-haspopup="menu"]').trigger("click");
    const items = w.findAll('[role="menuitem"]');
    expect(items.map((i) => i.text().slice(0, 7))).toEqual(["Narrow…", "Revoke…"]);
    expect(w.text()).toContain(
      "This grant can only be revoked. To change it, propose a new grant.",
    );
  });

  it("Narrow follows viewer_can_narrow only: false without a reason hides it", async () => {
    stub([{ ...activeBody, viewer_can_narrow: false }]);
    const w = await panel();
    await w.get('button[aria-haspopup="menu"]').trigger("click");
    expect(w.findAll('[role="menuitem"]').map((i) => i.text())).toEqual(["Revoke…"]);
  });

  it("narrows with only what shrinks and an operation id", async () => {
    const calls = stub(
      [activeBody],
      [json({ data: { grant: { ...activeBody, maximum_contacts: 20 }, replayed: false } })],
    );
    const w = await panel();
    await w.get('button[aria-haspopup="menu"]').trigger("click");
    await w.findAll('[role="menuitem"]')[0]?.trigger("click");
    await flushPromises();
    const contacts = w
      .findAll("input")
      .find(
        (i) =>
          i.attributes("inputmode") === "numeric" &&
          i.element instanceof HTMLInputElement &&
          i.element.value === "40",
      );
    // ca-engineer on #514: the horizon hint reads as a duration, never a raw division.
    expect(w.text()).toContain("Now 48h 00m. Choose the same or less.");
    expect(w.text()).toContain("Now 30 days, from approval. Choose the same or less.");
    await contacts?.setValue("20");
    const narrow = w.findAll("button").filter((b) => b.text() === "Narrow");
    await narrow[narrow.length - 1]?.trigger("click");
    await flushPromises();
    const sent = posts(calls)[0];
    expect(sent?.url).toContain("/grants/g1/narrow");
    expect(sent?.body).toMatchObject({ changes: { maximum_contacts: 20 } });
    expect(typeof sent?.body?.["operation_id"]).toBe("string");
    expect(w.get('p[role="status"]').text()).toContain("Narrowed. Nightly planner can now");
  });

  it("revokes without a hash; a nameless service reads U105's form in the sentence", async () => {
    const nameless = { ...activeBody, service_identity: { id: "svc_9", name: null } };
    const calls = stub([nameless], [json({ data: { grant: { ...nameless, state: "revoked" } } })]);
    const w = await panel();
    expect(w.text()).toContain("Unknown service identity");
    expect(w.text()).not.toContain("svc_9");
    expect(w.get('button[aria-haspopup="menu"]').attributes("aria-label")).toBe(
      "Actions for Unknown service identity's grant",
    );
    await w.get('button[aria-haspopup="menu"]').trigger("click");
    const items = w.findAll('[role="menuitem"]');
    await items[items.length - 1]?.trigger("click");
    await flushPromises();
    expect(document.body.textContent).toContain(
      "The service identity this grant is for stops acting on its own now.",
    );
    await openSheet(w).get("textarea").setValue("Done with it");
    const revoke = w.findAll("button").filter((b) => b.text() === "Revoke");
    await revoke[revoke.length - 1]?.trigger("click");
    await flushPromises();
    const sent = posts(calls)[0];
    expect(sent?.url).toContain("/grants/g1/revoke");
    expect(sent?.body).toEqual({ reason: "Done with it" });
    expect(w.text()).toContain(
      "Revoked. The service identity this grant is for can't act under this grant any more.",
    );
  });

  it("Revoke waits for a reason up front, and claims a revoke only on a confirmed state", async () => {
    stub([activeBody], [json({ data: { grant: { ...activeBody, state: "active" } } })]);
    const w = await panel();
    await w.get('button[aria-haspopup="menu"]').trigger("click");
    const items = w.findAll('[role="menuitem"]');
    await items[items.length - 1]?.trigger("click");
    await flushPromises();
    const revoke = () =>
      openSheet(w)
        .findAll("button")
        .find((b) => b.text().startsWith("Revoke"));
    // ca-ux and ux on #514: the console's check is the whole rule (the server has no 422).
    expect(revoke()?.attributes("aria-disabled")).toBe("true");
    expect(document.body.textContent).toContain("Give a reason first.");
    await openSheet(w).get("textarea").setValue("Done with it");
    await revoke()?.trigger("click");
    await flushPromises();
    expect(w.text()).toContain("Cadence didn't confirm the revoke. Reload to see it.");
    expect(w.text()).not.toContain("Revoked.");
  });
});
