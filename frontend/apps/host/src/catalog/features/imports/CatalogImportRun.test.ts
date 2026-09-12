import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CatalogImportRunShow from "./CatalogImportRunShow.vue";
import { assertImportRun } from "./validation";
import { breadcrumbs } from "../../shared/test-support";
test("import run renders model evidence and diagnostics as escaped text", () => {
  const data = {
    navigation: breadcrumbs,
    status: { label: "Failed", tone: "blocked" as const },
    run_details: {
      importer: { id: "importer-name", label: "Cadence YAML" },
      started_at: "2026-09-06",
      completed_at: null,
    },
    mission_model: {
      id: "import-model",
      revision_id: "revision-1",
      declaration_count: 1,
      plan_count: 1,
    },
    diagnostic_groups: [
      {
        title: "Errors",
        items: [
          { code: "invalid", message: "<script>bad()</script>", detail: null, path: "/packet" },
        ],
      },
    ],
    failure_reason: "Invalid catalog",
  };
  assertImportRun(data);
  const wrapper = mount(CatalogImportRunShow, { props: data });
  expect(wrapper.find("#import-model").exists()).toBe(true);
  expect(wrapper.get("#importer-name").text()).toBe("Cadence YAML");
  expect(wrapper.find("script").exists()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
  expect(() => assertImportRun({ ...data, diagnostic_groups: [{}] })).toThrow();
});
