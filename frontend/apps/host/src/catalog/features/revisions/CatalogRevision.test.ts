import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CatalogRevisionShow from "./CatalogRevisionShow.vue";
import { assertRevision } from "./validation";
import { breadcrumbs, catalogHref } from "../../shared/test-support";
test("revision renders provenance links and retains disabled runtime activation", () => {
  const data = {
    revision: { title: "Revision 1", number_label: "#1" },
    navigation: breadcrumbs,
    provenance: {
      id: "catalog-revision-provenance",
      title: "Provenance",
      rows: [
        {
          label: "Artifact",
          value: "mission.yaml",
          href: `${catalogHref}/artifacts/one`,
          style: "default" as const,
        },
      ],
    },
    runtime_usage: {
      id: "runtime-usage",
      title: "Runtime",
      summary_id: "summary",
      summary: "Not bound",
      action: { id: "catalog-revision-runtime-action", label: "Use revision", disabled: true },
    },
    mission_model: {
      id: "model",
      title: "Model",
      rows: [],
      available: false,
      empty_message: "Not available",
    },
  };
  assertRevision(data);
  const wrapper = mount(CatalogRevisionShow, { props: data });
  expect(wrapper.get("#catalog-revision-provenance a").attributes("href")).toBe(
    `${catalogHref}/artifacts/one`,
  );
  expect(wrapper.get("#catalog-revision-runtime-action").attributes("disabled")).toBeDefined();
  wrapper.unmount();
  expect(() => assertRevision({ ...data, provenance: { rows: [] } })).toThrow();
});
