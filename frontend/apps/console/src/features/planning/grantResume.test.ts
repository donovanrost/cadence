import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api";
import { activeBody, json, refused } from "./grant-fixtures.ts";
import GrantsPanel from "./GrantsPanel.vue";

/** ux U105 "Suspended" (#499): the suspended row and Resume…, end to end. */
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useSession: () => ({ user: { id: "u3" } }),
}));

const suspendedBody = {
  ...activeBody,
  id: "g5",
  state: "suspended",
  suspension: {
    at: "2026-11-19T22:40:00Z",
    by: { kind: "user", id: "u1", name: "Mira K." },
    settings_revision: 4,
    level: "mission",
  },
  viewer_can_narrow: false,
  viewer_can_decide: true,
  cannot_decide_because: null,
};

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
type Panel = Awaited<ReturnType<typeof panel>>;
const openSheet = (w: Panel) => {
  const d = w
    .findAll("dialog")
    .find((x) => x.element instanceof HTMLDialogElement && x.element.open);
  if (!d) throw new Error("no open sheet");
  return d;
};
const menuItems = async (w: Panel) => {
  await w.get('button[aria-haspopup="menu"]').trigger("click");
  return w.findAll('[role="menuitem"]');
};
async function openResume(w: Panel) {
  const resume = (await menuItems(w)).find((i) => i.text() === "Resume…");
  await resume?.trigger("click");
  await flushPromises();
  return openSheet(w);
}
const resumeButton = (w: Panel) =>
  openSheet(w)
    .findAll("button")
    .find((b) => b.text().startsWith("Resume"));
const posts = (calls: readonly Call[]) => calls.filter((c) => c.method === "POST");

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

describe("a suspended grant (U105, #499)", () => {
  it("shows SUSPENDED and who suspended it; the menu offers Resume… and Revoke…, not Narrow", async () => {
    stub([suspendedBody]);
    const w = await panel();
    expect(w.text()).toContain("SUSPENDED");
    expect(w.text()).toContain(
      "Suspended when Mira K. changed the mission's approval setting to Needs a second person's approval at 11-19 22:40Z. A second org admin resumes it.",
    );
    expect((await menuItems(w)).map((i) => i.text())).toEqual(["Resume…", "Revoke…"]);
  });

  it("resumes at the hash read with an operation id; a retry reuses it; a replay is the result", async () => {
    const calls = stub(
      [suspendedBody],
      [refused(409, "duplicate_operation"), json({ data: { grant: activeBody, replayed: true } })],
    );
    const w = await panel();
    const sheet = await openResume(w);
    expect(sheet.text()).toContain(
      "It takes effect again at once. Nightly planner can act under it until 12-19 06:40Z.",
    );
    await resumeButton(w)?.trigger("click");
    await flushPromises();
    expect(openSheet(w).get('[role="alert"]').text()).toContain(
      "Not resumed: Cadence matched this",
    );
    await resumeButton(w)?.trigger("click");
    await flushPromises();
    const [first, second] = posts(calls);
    expect(first?.url).toContain("/contact-planning/grants/g5/resume");
    expect(first?.body).toMatchObject({ sha256: "abc" });
    expect(typeof first?.body?.["operation_id"]).toBe("string");
    expect(second?.body?.["operation_id"]).toBe(first?.body?.["operation_id"]);
    expect(w.get('p[role="status"]').text()).toBe(
      "Resumed. Nightly planner can act under it until 12-19 06:40Z.",
    );
  });

  it("claims a resume only on a confirmed state", async () => {
    stub([suspendedBody], [json({ data: { grant: suspendedBody, replayed: false } })]);
    const w = await panel();
    await openResume(w);
    await resumeButton(w)?.trigger("click");
    await flushPromises();
    expect(w.get('p[role="status"]').text()).toBe(
      "Cadence didn't confirm that it resumed. Reload to see it.",
    );
  });

  it("disables Resume… up front with the server's reason; Revoke stays", async () => {
    stub([{ ...suspendedBody, viewer_can_decide: false, cannot_decide_because: "approved" }]);
    const w = await panel();
    const items = await menuItems(w);
    const resume = items.find((i) => i.text().startsWith("Resume…"));
    expect(resume?.attributes("aria-disabled")).toBe("true");
    expect(w.text()).toContain("You approved this grant, so another org admin resumes it.");
    expect(items.some((i) => i.text() === "Revoke…")).toBe(true);
  });

  it("keeps Resume off after a separation refusal, with its line", async () => {
    stub(
      [suspendedBody],
      [
        refused(403, "automation_grant_self_approval_forbidden", {
          because: "approved",
          grantee: { id: "svc_1", name: "Nightly planner" },
        }),
      ],
    );
    const w = await panel();
    await openResume(w);
    await resumeButton(w)?.trigger("click");
    await flushPromises();
    expect(openSheet(w).get('[role="alert"]').text()).toContain(
      "Not resumed: you approved this grant, so another org admin resumes it. Nothing changed.",
    );
    expect(resumeButton(w)?.attributes("aria-disabled")).toBe("true");
    // ca-engineer on #565: closing and reopening the sheet keeps it off for the grant as read.
    await openSheet(w)
      .findAll("button")
      .find((b) => b.text() === "Cancel")
      ?.trigger("click");
    await flushPromises();
    await openResume(w);
    expect(resumeButton(w)?.attributes("aria-disabled")).toBe("true");
  });

  it("Revoke's line on a suspended grant says it won't act again (ca-ux on #565)", async () => {
    stub([suspendedBody]);
    const w = await panel();
    await (await menuItems(w)).find((i) => i.text() === "Revoke…")?.trigger("click");
    await flushPromises();
    expect(openSheet(w).text()).toContain("Nightly planner won't act under this grant again.");
    expect(openSheet(w).text()).not.toContain("Plans it already submitted");
  });

  it("an unknown up-front reason keeps its code in the row's Technical details", async () => {
    stub([{ ...suspendedBody, viewer_can_decide: false, cannot_decide_because: "something_new" }]);
    const w = await panel();
    expect(w.text()).toContain("Technical details");
    expect(w.text()).toContain("something_new");
  });
});
