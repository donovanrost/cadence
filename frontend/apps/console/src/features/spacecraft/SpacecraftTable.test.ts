import { mount } from "@vue/test-utils";
import { createMemoryHistory, createRouter } from "vue-router";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { directoryPageReader, type SpacecraftRow } from "./api.ts";
import SpacecraftTable from "./SpacecraftTable.vue";

const summary = {
  total: 2,
  profiles: 0,
  without_profile: 2,
  without_scid: 0,
  without_routing_rule: 2,
  awaiting_first_aos: 0,
};
const raw = (id: string, scid: number, extra: Record<string, unknown> = {}) => ({
  id,
  name: id.toUpperCase(),
  scid,
  norad_id: null,
  plane: null,
  slot: null,
  profile: null,
  routing_rule_count: 0,
  ready: false,
  last_received_at: null,
  ...extra,
});
function rows(): readonly SpacecraftRow[] {
  const r = decode(directoryPageReader, {
    spacecraft: [
      raw("earendil-004", 4, {
        approval_withdrawn: {
          revision_id: "mission_model_revision:r3",
          decision: { kind: "withdrawn", by: null, at: "2026-11-20T09:12:00Z", reason: null },
        },
      }),
      raw("earendil-005", 5, { approval_withdrawn: null }),
    ],
    summary,
    telemetry: "ok",
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value.rows;
}

/** E2b (#546; U109): the directory row's "No longer approved" badge. */
describe("SpacecraftTable", () => {
  it("badges a craft whose running revision is no longer approved, and only that one", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: "/", component: { render: () => null } },
        {
          path: "/s/:spacecraftId",
          name: "setup.spacecraft.one",
          component: { render: () => null },
        },
      ],
    });
    await router.push("/");
    const w = mount(SpacecraftTable, { props: { rows: rows() }, global: { plugins: [router] } });
    const body = w.findAll("tbody tr");
    expect(body[0]?.text()).toContain("No longer approved");
    expect(body[1]?.text()).not.toContain("No longer approved");
    w.unmount();
  });
});
