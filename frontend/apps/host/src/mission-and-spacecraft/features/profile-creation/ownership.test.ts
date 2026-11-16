import { expect, test } from "vite-plus/test";
import { SpacecraftTypeNew as publicForm } from "../../spacecraft";
import SpacecraftTypeNew from "./SpacecraftTypeNew.vue";

// Sweep row 2 deleted the spacecraft federated app's profile_new wrapper; the host's public name
// still resolves to its own profile form.
test("the historical profile entry resolves to the host public API", () => {
  expect(publicForm).toBe(SpacecraftTypeNew);
});
