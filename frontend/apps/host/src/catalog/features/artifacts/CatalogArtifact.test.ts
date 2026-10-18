import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CatalogArtifactShowPage from "./CatalogArtifactShowPage.vue";
import { artifactFixture } from "./fixtures.test-support";
import { assertArtifact } from "./validation";
test("artifact renders its original download and emits a path-bound reimport intent", async () => {
  const data = artifactFixture();
  assertArtifact(data);
  const wrapper = mount(CatalogArtifactShowPage, { props: data });
  expect(wrapper.get("#catalog-artifact-download-link").attributes("href")).toBe(
    "/missions/mission-a/catalog/artifacts/one/download",
  );
  await wrapper.get("#catalog-artifact-reimport-button").trigger("click");
  expect(wrapper.emitted("reimport")).toEqual([[]]);
  wrapper.unmount();
  data.presentation.artifact_show.artifact.download_href = "//external.test/file";
  expect(() => assertArtifact(data)).toThrow();
});
