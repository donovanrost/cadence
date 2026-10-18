import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CatalogRevisionShow from "./CatalogRevisionShow.vue";
import { assertRevision } from "./validation";
import { breadcrumbs, catalogHref } from "../../shared/test-support";
test("revision links imported catalog usage back to spacecraft configuration", () => {
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
    spacecraft_usage: {
      mission_id: "mission-a",
      usage: [
        {
          id: "spacecraft-1",
          name: "KESTREL-01",
          active: true,
          saved: true,
          href: "/missions/mission-a/spacecraft/spacecraft-1?section=changes",
        },
      ],
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
  expect(wrapper.get("#catalog-spacecraft-usage a").attributes("href")).toBe(
    "/missions/mission-a/spacecraft/spacecraft-1?section=changes",
  );
  expect(wrapper.find("#catalog-qualification").exists()).toBe(false);
  expect(wrapper.find("#catalog-revision-runtime-action").exists()).toBe(false);
  wrapper.unmount();
  expect(() =>
    assertRevision({
      ...data,
      spacecraft_usage: { ...data.spacecraft_usage, mission_id: "another-mission" },
    }),
  ).toThrow();
  expect(() => assertRevision({ ...data, provenance: { rows: [] } })).toThrow();
});
