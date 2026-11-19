import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import EventTypeFilter from "./EventTypeFilter.vue";
import { rawKindLabel } from "./model.ts";

vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  fetchRawKinds: () =>
    Promise.resolve({
      ok: true,
      value: [
        { raw_kind: "scheduled_contact_canceled", kind: "contact", count: 214 },
        { raw_kind: "limit_violation", kind: "limit", count: 40 },
        { raw_kind: "source_watermark_settled", kind: "data", count: 9 },
      ],
    }),
}));

async function mountAt(query: Record<string, string> = {}) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: "/t", name: "t", component: { render: () => null } }],
  });
  await router.push({ path: "/t", query });
  const w = mount(EventTypeFilter, {
    props: {
      missionId: missionId("m1"),
      window: { from: new Date("2026-11-15T00:00:00Z"), to: new Date("2026-11-16T00:00:00Z") },
      kinds: ["contact", "limit"],
    },
    global: { plugins: [router] },
    attachTo: document.body,
  });
  await flushPromises();
  return { w, router };
}

describe("Event type filter (ux U71 A9b, api 4a2f470d8)", () => {
  it("lists types in the shown groups, in fold words with counts, most frequent first", async () => {
    const { w } = await mountAt();
    await w.get("button[aria-expanded]").trigger("click");
    await flushPromises();
    expect(document.activeElement?.getAttribute("type")).toBe("search");
    const labels = w
      .findAll("label")
      .map((l) => l.text())
      .filter((t) => t.includes("("));
    expect(labels).toEqual(["Contacts canceled (214)", "Limit violations (40)"]);
    w.unmount();
  });
  it("writes ?raw_kind= and Clear filters resets the groups, the types and the threshold", async () => {
    const { w, router } = await mountAt({ kind: "contact,limit", severity: "caution" });
    await w.get("button[aria-expanded]").trigger("click");
    await flushPromises();
    await w.findAll("input[type=checkbox]")[0]?.trigger("change");
    await flushPromises();
    expect(router.currentRoute.value.query["raw_kind"]).toBe("scheduled_contact_canceled");
    await w
      .findAll("button")
      .find((b) => b.text() === "Clear filters")
      ?.trigger("click");
    await flushPromises();
    expect(router.currentRoute.value.query).toEqual({});
    w.unmount();
  });
  it("words an unknown raw kind in sentence case", () => {
    expect(rawKindLabel("contact_window_shifted")).toBe("Contact window shifted");
  });
});
