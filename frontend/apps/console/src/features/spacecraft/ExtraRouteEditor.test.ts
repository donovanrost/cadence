import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { decode, missionId } from "@/api/index.ts";
import ExtraRouteEditor from "./ExtraRouteEditor.vue";
import { detailReader } from "./detail.ts";

const option = (value: string, label: string) => ({ value, label });
const roles = [
  option("none", "Not used"),
  option("primary", "Primary"),
  option("candidate", "Candidate"),
  option("contributing", "Contributing"),
];
const field = (path: string, label: string, extra: Record<string, unknown> = {}) => ({
  path,
  label,
  type: "enum",
  unit: null,
  enum: null,
  range: null,
  default: null,
  required: false,
  help: null,
  visible_when: null,
  ...extra,
});
// domain 39c9e7ab3's generated form (config_kind_schema.ex), with ux U79's words.
const schema = {
  kind: "spacecraft_route",
  fields: [
    field("spacecraft_id", "Spacecraft", {
      required: true,
      create_only: true,
      enum: [option("sc-1", "EARENDIL-389"), option("sc-2", "EARENDIL-390")],
    }),
    field("ground_station_id", "Station", {
      required: true,
      enum: [option("gs-1", "Inuvik · INU"), option("gs-2", "Svalbard · SVB")],
    }),
    field("transport_id", "Transport", {
      enum: [option("t-1", "INU S-band · Inuvik")],
      help: "Leave empty to use the station's transport for each direction.",
    }),
    field("downlink", "Downlink", { required: true, enum: roles, default: "primary" }),
    field("uplink", "Uplink", { required: true, enum: roles, default: "none" }),
    field("display_name", "Route name", { type: "string" }),
    field("purpose_label", "Purpose", { type: "string" }),
  ],
};
const station = (id: string, name: string, code: string | null) => ({
  id,
  display_name: name,
  code,
  provider: null,
  region: null,
  lifecycle_state: "active",
  transport_count: null,
  routing_rule_count: null,
  health: null,
});
const stageOk = {
  change_set_id: "cs-1",
  change_id: "c-1",
  version: 1,
  staged_count: 1,
  base_revision: 3,
  entity_ids: ["route-1"],
};

function detail() {
  const result = decode(detailReader, {
    spacecraft: {
      id: "sc-1",
      name: "EARENDIL-389",
      scid: 389,
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
  });
  if (!result.ok) throw new Error(result.error.message);
  return result.value;
}

type Reply = { status: number; body: unknown };
function stub(stage: Reply) {
  const urls: string[] = [];
  const bodies: unknown[] = [];
  vi.stubGlobal("fetch", (url: string, init?: RequestInit) => {
    urls.push(url);
    if (typeof init?.body === "string") bodies.push(JSON.parse(init.body));
    const reply: Reply = url.endsWith("/schema")
      ? { status: 200, body: { data: schema } }
      : url.endsWith("/ground-stations")
        ? {
            status: 200,
            body: {
              data: {
                stations: [station("gs-1", "Inuvik", "INU"), station("gs-2", "Svalbard", null)],
              },
            },
          }
        : url.includes("/routes/")
          ? {
              status: 200,
              body: {
                data: {
                  id: "route-1",
                  document: {
                    spacecraft_id: "sc-1",
                    ground_station_id: "gs-1",
                    transport_id: null,
                    downlink: "primary",
                    uplink: "none",
                    display_name: null,
                    purpose_label: "Anomaly recovery",
                  },
                },
              },
            }
          : stage;
    return Promise.resolve(new Response(JSON.stringify(reply.body), { status: reply.status }));
  });
  return { urls, bodies };
}
afterEach(() => vi.unstubAllGlobals());

async function render(routeId: string) {
  const stubRoute = { render: () => null };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: "/sc/:spacecraftId", name: "setup.spacecraft.one", component: stubRoute }],
  });
  const w = mount(ExtraRouteEditor, {
    props: { missionId: missionId("m-1"), detail: detail(), routeId },
    global: { plugins: [router] },
    attachTo: document.body,
  });
  await flushPromises();
  return w;
}
const select = (w: Awaited<ReturnType<typeof render>>, label: string) =>
  w.findAll("label").find((l) => l.text().startsWith(label));
const fieldOf = (w: Awaited<ReturnType<typeof render>>, label: string) =>
  w.findAll("select, input").find((el) => {
    const id = el.attributes("id");
    return id !== undefined && select(w, label)?.attributes("for") === id;
  });

describe("U79 Add / Edit extra route", () => {
  it("adds with this spacecraft preset as the only choice, Primary / Not used preselected", async () => {
    stub({ status: 200, body: { data: stageOk } });
    const w = await render("new");
    const spacecraft = fieldOf(w, "Spacecraft");
    expect(
      spacecraft
        ?.findAll("option")
        .map((o) => o.text())
        .filter((t) => t !== "" && t !== "Choose…"),
    ).toEqual(["EARENDIL-389"]);
    expect((fieldOf(w, "Downlink")?.element as HTMLSelectElement | undefined)?.value).toBe(
      "primary",
    );
    expect((fieldOf(w, "Uplink")?.element as HTMLSelectElement | undefined)?.value).toBe("none");
    w.unmount();
  });

  it("stages a create named from the station's code and the spacecraft", async () => {
    const { bodies } = stub({ status: 200, body: { data: stageOk } });
    const w = await render("new");
    await fieldOf(w, "Station")?.setValue("gs-1");
    await w.get("form").trigger("submit");
    await flushPromises();
    expect(bodies).toHaveLength(1);
    expect(bodies[0]).toMatchObject({
      summary: "Add extra route INU · EARENDIL-389",
      ops: [
        {
          kind: "spacecraft_route",
          action: "create",
          document: {
            spacecraft_id: "sc-1",
            ground_station_id: "gs-1",
            downlink: "primary",
            uplink: "none",
          },
        },
      ],
    });
    w.unmount();
  });

  it("edits from the stored document, without the spacecraft field, named the same way", async () => {
    const { urls, bodies } = stub({ status: 200, body: { data: stageOk } });
    const w = await render("route-1");
    expect(urls.some((u) => u.endsWith("/spacecraft/sc-1/routes/route-1"))).toBe(true);
    expect(select(w, "Spacecraft")).toBeUndefined();
    await fieldOf(w, "Uplink")?.setValue("candidate");
    await w.get("form").trigger("submit");
    await flushPromises();
    expect(bodies).toEqual([
      expect.objectContaining({
        summary: "Edit extra route INU · EARENDIL-389",
        ops: [
          {
            kind: "spacecraft_route",
            action: "update",
            entity_id: "route-1",
            changes: [{ path: "uplink", value: "candidate" }],
          },
        ],
      }),
    ]);
    w.unmount();
  });

  it("shows each U79 refusal on its field, and the duplicate in the callout", async () => {
    const errors = [
      { path: "downlink", message: "Choose a role for downlink, uplink or both" },
      { path: "ground_station_id", message: "Choose a station" },
      { path: "transport_id", message: "INU S-band can't carry uplink" },
      { path: "", message: "EARENDIL-389 already has this route from its profile." },
    ];
    stub({
      status: 422,
      body: {
        error: {
          code: "invalid_op",
          message: "A staged change is invalid.",
          details: { index: 0, errors },
        },
      },
    });
    const w = await render("new");
    // The form's own required check runs first, so choose a station before the server refuses.
    await fieldOf(w, "Station")?.setValue("gs-1");
    await w.get("form").trigger("submit");
    await flushPromises();
    for (const e of errors.slice(0, 3)) {
      const input = fieldOf(
        w,
        e.path === "downlink"
          ? "Downlink"
          : e.path === "ground_station_id"
            ? "Station"
            : "Transport",
      );
      const described = input?.attributes("aria-describedby") ?? "";
      const text = described
        .split(" ")
        .map((id) => document.getElementById(id)?.textContent ?? "")
        .join(" ");
      expect(text).toContain(e.message);
    }
    expect(w.get('[role="status"]:not(.sr-only)').text()).toBe(
      "Nothing was staged. EARENDIL-389 already has this route from its profile.",
    );
    w.unmount();
  });

  it("says plainly when the route can't be loaded (404), with the way back and no Retry", async () => {
    vi.stubGlobal("fetch", (url: string) => {
      const reply = url.endsWith("/schema")
        ? { status: 200, body: { data: schema } }
        : url.endsWith("/ground-stations")
          ? { status: 200, body: { data: { stations: [] } } }
          : {
              status: 404,
              body: { error: { code: "spacecraft_route_not_found", message: "Not found." } },
            };
      return Promise.resolve(new Response(JSON.stringify(reply.body), { status: reply.status }));
    });
    const w = await render("route-9");
    expect(w.text()).toContain(
      "This extra route can't be opened for editing. It may have been removed.",
    );
    expect(w.findAll("button").some((b) => b.text() === "Retry")).toBe(false);
    expect(
      w
        .findAll("a")
        .find((a) => a.text() === "Back to routing")
        ?.attributes("href"),
    ).toBe("/sc/sc-1");
    expect(w.find("form").exists()).toBe(false);
    w.unmount();
  });
});
