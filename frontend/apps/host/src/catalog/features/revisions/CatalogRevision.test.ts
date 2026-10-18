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

test("revision keeps source links and model counts visible with complete provenance in one disclosure", () => {
  const row = (
    label: string,
    value: string | number | null,
    style: "default" | "mono" | "hash",
    href: string | null = null,
  ) => ({ label, value, style, href });
  const hash = "abcdef0123456789".repeat(4);
  const wrapper = mount(CatalogRevisionShow, {
    props: {
      revision: { title: "Flight software 3.2", number_label: "Revision 7" },
      navigation: breadcrumbs,
      provenance: {
        id: "catalog-revision-provenance",
        title: "Revision provenance",
        rows: [
          row("Artifact", "flight.yaml", "default", `${catalogHref}/artifacts/one`),
          row("Import run", "import_run_complete", "mono", `${catalogHref}/imports/one`),
          row("Content SHA-256", hash, "hash"),
        ],
      },
      spacecraft_usage: { mission_id: "mission-a", usage: [] },
      mission_model: {
        id: "catalog-mission-model",
        title: "Mission Model",
        available: true,
        empty_message: "Unavailable",
        rows: [
          row("Revision", `mission_model_revision:${hash}`, "hash"),
          row("Declarations", 547, "default"),
          row("Revision label", "Flight software 3.2", "mono"),
        ],
      },
    },
  });
  expect(wrapper.get("#catalog-revision-provenance a").text()).toBe("flight.yaml");
  expect(wrapper.get("#catalog-mission-model").text()).toContain("547");
  expect(wrapper.get("#catalog-mission-model").text()).toContain("Flight software 3.2");
  expect(wrapper.get("#catalog-mission-model").text()).not.toContain(hash);
  const details = wrapper.get("#catalog-revision-technical-details");
  expect(details.attributes("open")).toBeUndefined();
  expect(details.text()).toContain(`mission_model_revision:${hash}`);
  expect(details.get("a").attributes("href")).toBe(`${catalogHref}/imports/one`);
  expect(details.findAll("button")).toHaveLength(3);
  wrapper.unmount();
});
