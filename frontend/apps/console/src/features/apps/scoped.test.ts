import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader, spacecraftId } from "@/api";
import { changeApp, fetchScopedApps } from "./api.ts";

/** L19 (plans/spacecraft-apps.md): one spacecraft's apps come from its own path, same rows as A1. */
describe("scoped apps (L19)", () => {
  it("reads the mission's apps, or one spacecraft's", async () => {
    const urls: string[] = [];
    const original = globalThis.fetch;
    globalThis.fetch = async (input) => {
      urls.push(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
      return new Response(
        JSON.stringify({ data: { apps: [], spacecraft_count: 0, permissions: [] } }),
        { status: 200 },
      );
    };
    try {
      const signal = new AbortController().signal;
      await fetchScopedApps({ missionId: missionIdReader("m1"), spacecraftId: null }, signal);
      await fetchScopedApps(
        { missionId: missionIdReader("m1"), spacecraftId: spacecraftId("sc 4") },
        signal,
      );
    } finally {
      globalThis.fetch = original;
    }
    expect(urls[0]).toMatch(/\/missions\/m1\/apps$/);
    expect(urls[1]).toMatch(/\/missions\/m1\/spacecraft\/sc%204\/apps$/);
  });

  it("sends a spacecraft's install / disable / uninstall to its own path (api b18dcf7b5)", async () => {
    const calls: string[] = [];
    const original = globalThis.fetch;
    globalThis.fetch = async (input, init) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
      calls.push(`${init?.method ?? "GET"} ${url}`);
      return new Response("{}", { status: 500 });
    };
    try {
      await changeApp(missionIdReader("m1"), "telemetry_decom", "install", spacecraftId("sc 4"));
      await changeApp(missionIdReader("m1"), "limits", "disable");
    } finally {
      globalThis.fetch = original;
    }
    expect(calls[0]).toMatch(
      /^POST .*\/missions\/m1\/spacecraft\/sc%204\/apps\/telemetry_decom\/install$/,
    );
    expect(calls[1]).toMatch(/^POST .*\/missions\/m1\/apps\/limits\/disable$/);
  });
});
