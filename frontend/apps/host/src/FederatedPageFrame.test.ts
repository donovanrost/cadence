// @vitest-environment happy-dom
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import { h } from "vue";
import type { CatalogApplication, MissionHostContext } from "@cadence/plugin-sdk";
import FederatedPageFrame from "./FederatedPageFrame.vue";

const application: CatalogApplication = {
  applicationKey: "comms",
  applicationVersion: 1,
  displayName: "Comms",
  description: "Mission communications setup.",
  package: { packageId: "cadence.comms", version: 1 },
  surface: {
    surfaceId: "transports",
    version: 1,
    purpose: "collection",
    scope: "mission",
    placement: "application_workspace",
    navigation: { label: "Transports", order: 30 },
    dataContract: { id: "cadence.comms.transports", version: 1 },
    actions: [],
    renderer: { kind: "federated-vue", exposedModule: "./Application" },
  },
  release: {
    federation: "module_federation",
    releaseId: "comms-v1",
    remoteName: "cadence_comms",
    manifestUrl: "/assets/application-host/comms/mf-manifest.json",
    exposedModule: "./Application",
  },
};
const context = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "m1",
  missionName: "Kestrel",
  spacecraftId: null,
  spacecraftName: null,
} as MissionHostContext;

test("a surface standing in for a host page gets that page's host-drawn header", () => {
  const wrapper = mount(FederatedPageFrame, {
    props: {
      application: { ...application, hostRoute: "/missions/:mission_id/comms/transports" },
      context,
    },
    slots: { default: () => h("p", { id: "surface" }) },
  });
  expect(wrapper.get("#host-page-heading h1").text()).toBe("Transports");
  expect(wrapper.get(".cd-page-breadcrumbs").text()).toContain("Kestrel");
  expect(wrapper.get('a[href="/missions/m1/comms"]').text()).toBe("Comms");
  expect(wrapper.find("#surface").exists()).toBe(true);
  wrapper.unmount();
});

test("a surface with no host page renders bare", () => {
  const wrapper = mount(FederatedPageFrame, {
    props: { application, context },
    slots: { default: () => h("p", { id: "surface" }) },
  });
  expect(wrapper.find("#host-page-heading").exists()).toBe(false);
  expect(wrapper.find("#surface").exists()).toBe(true);
  wrapper.unmount();
});
