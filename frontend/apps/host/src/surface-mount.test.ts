import { describe, expect, it } from "vite-plus/test";
import { defineComponent, h } from "vue";
import { fullPageSurfaceProps } from "@cadence/plugin-sdk";
import { mountFullPageSurface } from "./surface-mount";

const application = {
  applicationKey: "mount_test",
  applicationVersion: 1,
  displayName: "Mount test",
  description: "Tests the generic full-page mount.",
  package: { packageId: "cadence.mount-test", version: 1 },
  surface: {
    surfaceId: "overview",
    version: 1,
    purpose: "overview",
    scope: "mission",
    placement: "application_workspace",
    navigation: { label: "Overview", order: 1 },
    dataContract: { id: "cadence.mount-test.overview", version: 1 },
    actions: [],
    renderer: { kind: "federated-vue", exposedModule: "./Application" },
  },
  release: {
    federation: "module_federation",
    releaseId: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    remoteName: "cadence_mount_test",
    manifestUrl: "/releases/mount-test/mf-manifest.json",
    exposedModule: "./Application",
  },
} as const;

const context = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
} as const;

describe("full-page surface mount", () => {
  it("passes the complete four-prop contract and unmounts it", () => {
    const root = document.createElement("div");
    const received: Record<string, unknown>[] = [];
    const renderer = defineComponent({
      props: {
        application: { type: Object, required: true },
        surface: { type: Object, required: true },
        bridge: { type: Object, required: true },
        context: { type: Object, required: true },
      },
      setup(props) {
        received.push(props);
        return () => h("article", { id: "mounted-surface" }, "Full page");
      },
    });

    const bridge = {} as never;
    const mount = mountFullPageSurface(root, renderer, application, context, bridge);
    expect(root.querySelector("#mounted-surface")?.textContent).toBe("Full page");
    expect(received).toHaveLength(1);
    expect(received[0]).toMatchObject({
      application,
      surface: application.surface,
      context,
      bridge,
    });
    mount.unmount();
    expect(root.querySelector("#mounted-surface")).toBeNull();
  });

  it("accepts the published ops workspace placement but not an ops dock", () => {
    expect(() =>
      fullPageSurfaceProps(
        { ...application, surface: { ...application.surface, placement: "ops_workspace" } },
        { ...context, scope: "mission" },
        {} as never,
      ),
    ).not.toThrow();

    expect(() =>
      fullPageSurfaceProps(
        { ...application, surface: { ...application.surface, placement: "ops_dock" } },
        context,
        {} as never,
      ),
    ).toThrow("application_workspace or ops_workspace");
  });
});
