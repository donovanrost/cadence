import { describe, expect, it } from "vite-plus/test";
import { uninstallLines } from "./uninstall-words.ts";
import { versionMeta } from "./versions.ts";

const row = {
  state: "installed" as const,
  version: "2",
  available_version: 3,
  update_available: true,
};

describe("version meta (#679)", () => {
  it("names the newer version only when the server says an update exists", () => {
    expect(versionMeta(row)).toBe("v2 · v3 available");
    expect(versionMeta({ ...row, update_available: false })).toBe("v2");
    expect(versionMeta({ ...row, state: "disabled" })).toBe("v2 · v3 available");
  });

  it("never compares versions itself: an older shipped one with the flag off stays plain", () => {
    expect(versionMeta({ ...row, available_version: 1, update_available: false })).toBe("v2");
  });

  it("shows the version an app would install when it isn't installed", () => {
    expect(
      versionMeta({
        state: "not_installed",
        version: null,
        available_version: 3,
        update_available: false,
      }),
    ).toBe("v3");
  });
});

describe("uninstall confirm lines (#679)", () => {
  it("names the spacecraft it stops on, and that the configuration is kept", () => {
    expect(
      uninstallLines({ kind: "mission", missionName: "Aurora", spacecraftCount: 500 }),
    ).toEqual(["It stops on 500 spacecraft in Aurora.", "Its configuration is kept."]);
    expect(uninstallLines({ kind: "mission", missionName: "Aurora", spacecraftCount: 1 })[0]).toBe(
      "It stops on 1 spacecraft in Aurora.",
    );
    expect(uninstallLines({ kind: "spacecraft" })[0]).toBe("It stops on this spacecraft.");
  });

  it("doesn't claim a stop where there is no spacecraft", () => {
    expect(uninstallLines({ kind: "mission", missionName: "Aurora", spacecraftCount: 0 })[0]).toBe(
      "There are no spacecraft in Aurora yet, so nothing stops.",
    );
  });
});
