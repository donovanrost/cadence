import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode, missionId } from "@/api";
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
        surfaces: [],
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
  it("shows the server's own status label for the app", () => {
    const w = render(app({ state: "active", label: "Needs a packet binding", version: "1" }));
    expect(w.text()).toContain("Needs a packet binding");
  });

  it("shows nothing extra when the server sends no label", () => {
    const w = render(app({ state: "active", label: null, version: "1" }));
    expect(w.text()).not.toContain("Needs");
    expect(w.text()).toContain("Platform · always on");
  });
});
