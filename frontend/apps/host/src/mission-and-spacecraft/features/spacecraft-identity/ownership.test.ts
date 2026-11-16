import { expect, test } from "vite-plus/test";
import * as publicSpacecraft from "../../spacecraft";
import SpacecraftIdentityForm from "./SpacecraftIdentityForm.vue";

// Sweep row 2 deleted the spacecraft federated app's create/edit wrappers; the host's public names
// still resolve to the single identity form (the legacy native page renders it until its deletion).
test("legacy creation and editing resolve to the single host identity form", () => {
  for (const name of ["SpacecraftNew", "SpacecraftEdit"] as const) {
    expect(publicSpacecraft[name]).toBe(SpacecraftIdentityForm);
  }
});
