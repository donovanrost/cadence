import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { decode, missionId } from "@/api/index.ts";
import { detailReader } from "./detail.ts";
import { configWith } from "./config.fixtures.ts";
import OperationPanel from "./OperationPanel.vue";

// useConfigState listens for config changes live.
vi.mock("@/live", async (original) => ({
  ...(await original<typeof import("@/live")>()),
  useMissionInvalidation: () => undefined,
}));

/** #309 (U40): the switches are changed on the Operation panel; turning one off says what it stops. */
afterEach(() => vi.unstubAllGlobals());

function detail() {
  const r = decode(detailReader, {
    spacecraft: {
      id: "sc-312",
      name: "EARENDIL-312",
      scid: 312,
      norad_id: null,
      plane: null,
      slot: null,
      last_received_at: null,
    },
    profile: null,
    configuration: null,
    telemetry: { status: "never", last_received_at: null },
    routing_rules: [],
    readiness: { ready: true, checks: [] },
    commanding_enabled: true,
    telemetry_enabled: true,
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}

/** The open set stages commanding off for EARENDIL-312; the head is r6, so it applies with r7. */
function configWithStagedOff() {
  const config = configWith([
    {
      kind: "spacecraft",
      entity_id: "sc-312",
      action: "update",
      paths: ["commanding_enabled"],
      payload: { changes: [{ path: "commanding_enabled", value: false }] },
    },
  ]);
  return { ...config, head: { ...config.head, revision: 6 } };
}

function render(canStage = true, mission = "m-ops") {
  const staged: unknown[] = [];
  vi.stubGlobal("fetch", (url: string, init?: RequestInit) => {
    if (typeof init?.body === "string") staged.push(JSON.parse(init.body));
    const data = url.endsWith("/stage")
      ? {
          change_set_id: "cs-1",
          change_id: "c-1",
          version: 1,
          staged_count: 1,
          base_revision: 6,
          entity_ids: ["sc-312"],
        }
      : url.endsWith("/schema")
        ? { kind: "spacecraft", fields: [] }
        : {};
    return Promise.resolve(new Response(JSON.stringify({ data })));
  });
  const w = mount(OperationPanel, {
    props: { missionId: missionId(mission), detail: detail(), canStage },
    attachTo: document.body,
  });
  return { w, staged };
}
const radio = (label: string, value: "On" | "Off") =>
  [...document.querySelectorAll(`[role="radiogroup"][aria-label="${label}"] [role="radio"]`)].find(
    (b) => b.textContent?.trim() === value,
  ) as HTMLElement | undefined;

describe("Operation switches (#309, U40)", () => {
  it("turning off opens a sheet that says what it stops, on Cancel; Stage stages the off", async () => {
    const { w, staged } = render();
    await flushPromises();
    radio("Commanding", "Off")?.click();
    await flushPromises();
    expect(document.body.textContent).toContain(
      "Turning commanding off stops new requests and releases for EARENDIL-312.",
    );
    expect(document.activeElement?.textContent?.trim()).toBe("Cancel");
    expect(staged).toEqual([]);
    [...document.querySelectorAll("button")]
      .find((b) => b.textContent?.trim() === "Stage")
      ?.click();
    await flushPromises();
    expect(staged).toEqual([
      {
        summary: "EARENDIL-312 · turn commanding off",
        source: { surface: "spacecraft" },
        ops: [
          {
            kind: "spacecraft",
            action: "update",
            entity_id: "sc-312",
            changes: [{ path: "commanding_enabled", value: false }],
          },
        ],
      },
    ]);
    w.unmount();
  });

  it("a staged switch shows its target and 'Staged · applies with r7', the r kept lower-case", async () => {
    vi.stubGlobal("fetch", (url: string) => {
      const data = url.endsWith("/schema")
        ? { kind: "spacecraft", fields: [] }
        : url.endsWith("/config")
          ? configWithStagedOff()
          : {};
      return Promise.resolve(new Response(JSON.stringify({ data })));
    });
    const w = mount(OperationPanel, {
      props: { missionId: missionId("m-staged"), detail: detail(), canStage: true },
      attachTo: document.body,
    });
    await flushPromises();
    const tag = w.findAll("span").find((s) => s.text().startsWith("Staged · applies with"));
    expect(tag?.text()).toBe("Staged · applies with r7");
    expect(tag?.find("span.normal-case").text()).toBe("r7");
    expect(radio("Commanding", "Off")?.getAttribute("aria-checked")).toBe("true");
    w.unmount();
  });

  it("someone else's staged switch: 'Not staged: …' with the way back (path_already_staged)", async () => {
    vi.stubGlobal("fetch", (url: string) =>
      Promise.resolve(
        url.endsWith("/stage")
          ? new Response(
              JSON.stringify({
                error: {
                  code: "path_already_staged",
                  message: "Someone else already staged a change to this field.",
                  details: { change_id: "c-9", path: "telemetry_enabled" },
                },
              }),
              { status: 409 },
            )
          : new Response(
              JSON.stringify({
                data: url.endsWith("/schema") ? { kind: "spacecraft", fields: [] } : {},
              }),
            ),
      ),
    );
    // The refusal's Open change set is a link, so this mount has a router.
    const stub = { render: () => null };
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: "/sc", name: "setup.spacecraft.one", component: stub },
        { path: "/changes", name: "setup.changes", component: stub },
      ],
    });
    await router.push("/sc");
    const w = mount(OperationPanel, {
      props: { missionId: missionId("m-taken"), detail: detail(), canStage: true },
      global: { plugins: [router] },
      attachTo: document.body,
    });
    try {
      await flushPromises();
      radio("Telemetry", "Off")?.click();
      await flushPromises();
      [...document.querySelectorAll("button")]
        .find((b) => b.textContent?.trim() === "Stage")
        ?.click();
      await flushPromises();
      expect(w.text()).toContain(
        "Not staged: telemetry is already staged for EARENDIL-312 in the open change set. Discard that change in Setup › Changes to undo it.",
      );
      expect(w.findAll("a").some((a) => a.text() === "Open change set")).toBe(true);
    } finally {
      w.unmount();
    }
  });

  it("someone who can't stage sees the state tags, not the switch", async () => {
    const { w } = render(false, "m-view");
    await flushPromises();
    expect(document.querySelector('[role="radiogroup"]')).toBeNull();
    expect(w.text()).toContain("On");
    w.unmount();
  });
});
