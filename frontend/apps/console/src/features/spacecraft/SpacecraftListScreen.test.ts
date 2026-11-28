import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import SpacecraftListScreen from "./SpacecraftListScreen.vue";

vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useMissionScope: () =>
    computed(() => ({
      mission: { id: missionId("m-1"), name: "EARENDIL" },
      organization: { id: "org-1" },
    })),
  useSession: () => ({}),
  canAdministerOrganization: () => true,
}));

const row = (n: number) => ({
  id: `sc-${n}`,
  name: `Craft ${n}`,
  scid: n,
  norad_id: null,
  plane: null,
  slot: null,
  profile: null,
  routing_rule_count: 0,
  ready: false,
  last_received_at: null,
});

/** `total` craft, `size` a page, answering `q` by name and the cursor as the first index. */
function server(total: number, size: number) {
  const urls: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      urls.push(input);
      const url = new URL(input, "http://x");
      const q = url.searchParams.get("q");
      const cursor = url.searchParams.get("cursor");
      const all = Array.from({ length: total }, (_, i) => i + 1).filter(
        (n) => q === null || `craft ${n}`.includes(q.toLowerCase()),
      );
      const from = cursor === null ? 0 : Number(cursor);
      const to = Math.min(from + size, all.length);
      const body = {
        data: {
          spacecraft: all.slice(from, to).map(row),
          ...(cursor === null
            ? {
                summary: {
                  total,
                  profiles: 0,
                  without_profile: total,
                  without_scid: 0,
                  without_routing_rule: total,
                  awaiting_first_aos: total,
                },
              }
            : {}),
          telemetry: "ok",
        },
        meta: { next_cursor: to < all.length ? String(to) : null },
      };
      return Promise.resolve(new Response(JSON.stringify(body)));
    }),
  );
  return urls;
}

async function mountScreen() {
  const stub = { template: "<div />" };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC; the lint type service can't resolve .vue imports.
      { path: "/spacecraft", name: "setup.spacecraft", component: SpacecraftListScreen },
      { path: "/spacecraft/new", name: "setup.spacecraft.new", component: stub },
      { path: "/spacecraft/:spacecraftId", name: "setup.spacecraft.one", component: stub },
    ],
  });
  await router.push("/spacecraft");
  const w = mount(
    { template: "<RouterView />" },
    { attachTo: document.body, global: { plugins: [router] } },
  );
  await flushPromises();
  return w;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
  document.body.innerHTML = "";
});

describe("Setup › Spacecraft directory (#796)", () => {
  it("reads the mission's counts from the server and says how many rows are shown", async () => {
    server(450, 200);
    const w = await mountScreen();
    expect(w.text()).toContain("450 spacecraft");
    expect(w.text()).toContain("200 of 450");
    expect(w.findAll("tbody tr")).toHaveLength(200);
    w.unmount();
  });

  it("keeps the filter box mounted and focused while its own typing reloads the list", async () => {
    vi.useFakeTimers();
    server(450, 200);
    const w = await mountScreen();
    const box = w.get('input[type="search"]');
    (box.element as HTMLInputElement).focus();
    await box.setValue("craft 4");
    await vi.advanceTimersByTimeAsync(300);
    // The query started over: the box is the same element and still has focus.
    expect(w.find('input[type="search"]').element).toBe(box.element);
    expect(document.activeElement).toBe(box.element);
    await flushPromises();
    expect(w.find('input[type="search"]').element).toBe(box.element);
    expect(document.activeElement).toBe(box.element);
    w.unmount();
  });

  it("Load more appends the next page and focuses its first new row inside the panel", async () => {
    server(450, 200);
    const w = await mountScreen();
    const more = w.findAll("button").find((b) => b.text() === "Load more");
    if (!more) throw new Error("no Load more");
    await more.trigger("click");
    await flushPromises();
    expect(w.findAll("tbody tr")).toHaveLength(400);
    expect((document.activeElement as HTMLElement).textContent).toBe("Craft 201");
    // The later page sent no counts: the subtitle and the shown-of-total keep the first page's.
    expect(w.text()).toContain("450 spacecraft");
    expect(w.text()).toContain("400 of 450");
    w.unmount();
  });

  it("a filter with no match says so and keeps the box to clear it", async () => {
    vi.useFakeTimers();
    server(450, 200);
    const w = await mountScreen();
    await w.get('input[type="search"]').setValue("zzz");
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();
    expect(w.text()).toContain("No spacecraft match");
    expect(w.find('input[type="search"]').exists()).toBe(true);
    w.unmount();
  });
});
