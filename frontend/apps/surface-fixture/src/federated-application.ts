import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import FixtureSurface from "./FixtureSurface.vue";

// The console federation smoke's test-only application (server side:
// Cadence.TestSupport.SurfaceFixtureApplication, registered only in the test environment).
export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: {
    packageId: "cadence.surface-fixture",
    version: 1,
    trust: "first_party",
  },
  compatibility: {
    cadenceApplicationContract: 1,
    cadenceSurfaceContract: 1,
    cadenceFederatedRendererContract: 1,
    cadenceThemeContract: 1,
  },
  application: {
    applicationKey: "surface_fixture",
    version: 1,
    displayName: "Surface Fixture",
    description: "A fixture for the console's federated surface contract.",
    installableScopes: ["mission"],
  },
  surfaces: [
    {
      surfaceId: "mission_surface",
      version: 1,
      purpose: "overview",
      scope: "mission",
      placement: "application_workspace",
      navigation: { label: "Surface fixture", order: 90 },
      dataContract: { id: "cadence.surface_fixture.mission", version: 1 },
      actions: ["record_nonce"],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
  ],
});

export default FixtureSurface;
