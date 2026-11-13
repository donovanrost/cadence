import { describe, expect, it } from "vite-plus/test";
import { fetchScopedApps } from "./api.ts";

/** L19 (plans/spacecraft-apps.md): one spacecraft's apps come from its own path, same rows as A1. */
describe("scoped apps (L19)", () => {
  it("reads the mission's apps, or one spacecraft's", async () => {
    const urls: string[] = [];
    const original = globalThis.fetch;
    globalThis.fetch = async (input) => {
      urls.push(String(input));
      return new Response(JSON.stringify({ data: { apps: [], permissions: [] } }), { status: 200 });
    };
    try {
      const signal = new AbortController().signal;
      await fetchScopedApps({ missionId: "m1", spacecraftId: null }, signal);
      await fetchScopedApps({ missionId: "m1", spacecraftId: "sc 4" }, signal);
    } finally {
      globalThis.fetch = original;
    }
    expect(urls[0]).toMatch(/\/missions\/m1\/apps$/);
    expect(urls[1]).toMatch(/\/missions\/m1\/spacecraft\/sc%204\/apps$/);
  });
});
