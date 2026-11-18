import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import KindEditor from "./KindEditor.vue";

const role = (value: string, label: string) => ({ value, label });
const roles = [
  role("none", "Not used"),
  role("primary", "Primary"),
  role("candidate", "Candidate"),
  role("contributing", "Contributing"),
];
const field = (path: string, label: string, extra: Record<string, unknown> = {}) => ({
  path,
  label,
  type: "enum",
  unit: null,
  enum: roles,
  range: null,
  default: null,
  required: true,
  help: null,
  visible_when: null,
  ...extra,
});
const schema = {
  kind: "spacecraft_route",
  fields: [
    field("downlink", "Downlink", { default: "primary" }),
    field("uplink", "Uplink", { default: "none" }),
  ],
};

type Call = { url: string; body: unknown };
function stub(stageReply: { status: number; body: unknown }) {
  const calls: Call[] = [];
  vi.stubGlobal("fetch", (url: string, init?: RequestInit) => {
    const body: unknown = typeof init?.body === "string" ? JSON.parse(init.body) : null;
    calls.push({ url, body });
    const reply = url.endsWith("/schema") ? { status: 200, body: { data: schema } } : stageReply;
    return Promise.resolve(new Response(JSON.stringify(reply.body), { status: reply.status }));
  });
  return calls;
}
afterEach(() => vi.unstubAllGlobals());

async function render(props: Record<string, unknown> = {}) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/", component: { render: () => null } },
      { path: "/done", name: "home", component: { render: () => null } },
    ],
  });
  const w = mount(KindEditor, {
    props: {
      missionId: missionId("m-1"),
      kind: "spacecraft_route",
      entityId: null,
      document: {},
      name: "extra route",
      index: "R1",
      surface: "spacecraft",
      done: { name: "home" as const },
      ...props,
    },
    global: { plugins: [router] },
    attachTo: document.body,
  });
  await flushPromises();
  return w;
}

describe("KindEditor: U79 errors on their fields, and the kind's own summary", () => {
  it("shows a rejected field's message on that field, with 'Nothing was staged.' in the callout", async () => {
    stub({
      status: 422,
      body: {
        error: {
          code: "invalid_op",
          message: "A staged change is invalid.",
          details: {
            index: 0,
            errors: [{ path: "downlink", message: "Choose a role for downlink, uplink or both" }],
          },
        },
      },
    });
    const w = await render();
    await w.get("form").trigger("submit");
    await flushPromises();
    expect(w.text()).toContain("Choose a role for downlink, uplink or both");
    expect(w.get('[role="status"]').text()).toBe("Nothing was staged.");
    w.unmount();
  });

  it("keeps the whole-outcome sentence when no error names a field", async () => {
    stub({
      status: 422,
      body: {
        error: {
          code: "invalid_op",
          message: "A staged change is invalid.",
          details: { index: 0, errors: [{ path: "", message: "Each direction once" }] },
        },
      },
    });
    const w = await render();
    await w.get("form").trigger("submit");
    await flushPromises();
    expect(w.text()).toContain("Nothing was staged. Each direction once");
    w.unmount();
  });

  it("stages with the kind's summary when it gives one, and today's otherwise", async () => {
    const reply = {
      status: 200,
      body: {
        data: {
          change_set_id: "cs-1",
          change_id: "c-1",
          version: 1,
          staged_count: 1,
          base_revision: 3,
          entity_ids: ["e-1"],
        },
      },
    };
    let calls = stub(reply);
    let w = await render({
      summarize: (action: string) =>
        `${action === "create" ? "Add" : "Edit"} extra route INU · EARENDIL-389`,
    });
    await w.get("form").trigger("submit");
    await flushPromises();
    const staged = (c: Call[]) =>
      c.find((x) => x.url.endsWith("/stage"))?.body as { summary: string } | undefined;
    expect(staged(calls)?.summary).toBe("Add extra route INU · EARENDIL-389");
    w.unmount();

    calls = stub(reply);
    w = await render();
    await w.get("form").trigger("submit");
    await flushPromises();
    expect(staged(calls)?.summary).toBe("Add extra route");
    w.unmount();
  });
});
