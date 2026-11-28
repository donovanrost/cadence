import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode, missionId, spacecraftId } from "@/api";
import { appsReader, type App } from "./api.ts";
import AppRow from "./AppRow.vue";

function app(status: unknown): App {
  const r = decode(appsReader, {
    apps: [
      {
        key: "telemetry_decom",
        name: "Telemetry decom",
        description: "Decodes packets into parameters.",
        platform: true,
        installed: true,
        state: "installed",
        version: 1,
        available_version: 1,
        update_available: false,
        consequence_if_missing: null,
        status,
      },
    ],
    spacecraft_count: 1,
    permissions: [],
  });
  if (!r.ok || !r.value.apps[0]) throw new Error("fixture must decode");
  return r.value.apps[0];
}

const render = (a: App) =>
  mount(AppRow, {
    props: {
      missionId: missionId("mission_1"),
      app: a,
      canInstall: false,
      uninstallScope: { kind: "spacecraft" },
    },
  });

describe("an app row (L19)", () => {
  it("says what the server's status adds, in the console's own words", () => {
    const w = render(app({ state: "activation_pending", label: "free server text", version: "1" }));
    expect(w.text()).toContain("Waiting for activation approval");
    expect(w.text()).not.toContain("free server text");
  });

  it("adds nothing when the lifecycle tag already says it", () => {
    const w = render(app({ state: "active", label: "Active", version: "1" }));
    expect(w.text()).toContain("Platform · always on");
    expect(w.text()).not.toContain("Waiting");
    expect(w.text()).not.toContain("Status not known");
  });

  it("an app row is its name and its verbs, with no link (#672)", () => {
    const row = { ...app({ state: "active", label: null, version: "1" }), platform: false };
    const w = mount(AppRow, {
      props: {
        missionId: missionId("mission_1"),
        app: row,
        canInstall: true,
        uninstallScope: { kind: "spacecraft" },
        spacecraftId: spacecraftId("sc_1"),
      },
      global: { stubs: { RouterLink: true } },
    });
    expect(w.text()).toContain("Telemetry decom");
    expect(w.find("router-link-stub").exists()).toBe(false);
    expect(w.findAll("button").map((b) => b.text())).toEqual(
      expect.arrayContaining(["Disable", "Uninstall"]),
    );
  });

  it("says an unknown state is not known rather than guessing", () => {
    const w = render(app({ state: "rebooting", label: null, version: "1" }));
    expect(w.text()).toContain("Status not known");
  });
});
