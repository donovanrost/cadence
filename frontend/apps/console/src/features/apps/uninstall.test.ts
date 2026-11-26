import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import AppActions from "./AppActions.vue";
import type { App } from "./api.ts";

/** #679: Uninstall is offered on an installed or a disabled app, behind a confirm that names the verb. */
type Change = typeof import("./api.ts").changeApp;
const call = vi.hoisted(() => ({ fn: vi.fn<Change>() }));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  changeApp: (...args: Parameters<Change>) => call.fn(...args),
}));
afterEach(() => call.fn.mockReset());
const app = (state: App["state"]): App => ({
  key: "limits",
  name: "Limits",
  platform: false,
  description: null,
  installed: state === "installed",
  state,
  version: "1",
  available_version: 1,
  update_available: false,
  consequence_if_missing: null,
  status: null,
  surfaces: [],
});
const mountActions = (state: App["state"]) =>
  mount(AppActions, {
    props: {
      missionId: missionId("m-1"),
      app: app(state),
      uninstallScope: { kind: "mission", missionName: "EARENDIL", spacecraftCount: 3 },
    },
    attachTo: document.body,
  });
const labels = (w: ReturnType<typeof mountActions>) => w.findAll("button").map((b) => b.text());

describe("Uninstall on a mission app (#679)", () => {
  it("is offered on an installed app and on a disabled one, not on one that isn't installed", () => {
    expect(labels(mountActions("installed"))).toContain("Uninstall");
    expect(labels(mountActions("disabled"))).toContain("Uninstall");
    expect(labels(mountActions("not_installed"))).not.toContain("Uninstall");
  });

  it("asks first, in concrete words, and only the confirm uninstalls", async () => {
    call.fn.mockResolvedValue({ kind: "applied", app: app("not_installed") });
    const w = mountActions("installed");
    await w
      .findAll("button")
      .find((b) => b.text() === "Uninstall")
      ?.trigger("click");
    expect(call.fn).not.toHaveBeenCalled();
    const text = w.find("dialog").text();
    expect(text).toContain("Uninstall Limits?");
    expect(text).toContain("It stops on 3 spacecraft in EARENDIL.");
    expect(text).toContain("Its configuration is kept.");
    await w
      .findAll("dialog button")
      .find((b) => b.text() === "Uninstall Limits")
      ?.trigger("click");
    await flushPromises();
    expect(call.fn).toHaveBeenCalledWith(missionId("m-1"), "limits", "uninstall", null);
    expect(w.emitted("changed")).toHaveLength(1);
  });

  it("says a refusal in the row, as it does for the other verbs", async () => {
    call.fn.mockResolvedValue({
      kind: "failed",
      error: { kind: "forbidden", code: "forbidden", message: "no" },
    });
    const w = mountActions("disabled");
    await w
      .findAll("button")
      .find((b) => b.text() === "Uninstall")
      ?.trigger("click");
    await w
      .findAll("dialog button")
      .find((b) => b.text() === "Uninstall Limits")
      ?.trigger("click");
    await flushPromises();
    expect(w.find('[role="alert"]').exists()).toBe(true);
  });
});
