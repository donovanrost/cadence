import { describe, expect, it } from "vite-plus/test";
import { defineComponent, h } from "vue";
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
  it("mounts a domain renderer into the caller-owned root and unmounts it", () => {
    const root = document.createElement("div");
    const renderer = defineComponent({
      props: { bridge: { type: Object }, context: { type: Object } },
      setup() {
        return () => h("article", { id: "mounted-surface" }, "Full page");
      },
    });

    const mount = mountFullPageSurface(root, renderer, application, context, {} as never);
    expect(root.querySelector("#mounted-surface")?.textContent).toBe("Full page");
    mount.unmount();
    expect(root.querySelector("#mounted-surface")).toBeNull();
  });
});
