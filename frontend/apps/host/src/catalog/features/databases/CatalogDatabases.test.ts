import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CatalogIndex from "./CatalogIndex.vue";
import CatalogDatabaseNew from "./CatalogDatabaseNew.vue";
import CatalogDatabaseShow from "./CatalogDatabaseShow.vue";
import {
  databaseIndexFixture,
  databaseNewFixture,
  databaseShowFixture,
} from "./fixtures.test-support";
import { assertDatabaseIndex, assertDatabaseNew, assertDatabaseShow } from "./validation";

test("database directory renders revision/import navigation from a validated DTO", () => {
  const data = databaseIndexFixture();
  assertDatabaseIndex(data);
  const wrapper = mount(CatalogIndex, { props: data });
  expect(
    wrapper
      .get("#database-row-one")
      .findAll("a")
      .map((a) => a.attributes("href")),
  ).toContain("/missions/mission-a/catalog/revisions/one");
  expect(wrapper.get("#new-database-link").attributes("href")).toBe(
    "/missions/mission-a/catalog/new",
  );
  wrapper.unmount();
  required(data.presentation.card.rows[0]).latest_import.href = "javascript:alert(1)";
  expect(() => assertDatabaseIndex(data)).toThrow();
});
test("new database preserves editable fields and the mission-scoped cancel link", async () => {
  const data = databaseNewFixture();
  assertDatabaseNew(data);
  const wrapper = mount(CatalogDatabaseNew, { props: data });
  await wrapper.get("#catalog_database_name").setValue("Flight");
  expect(wrapper.emitted("validate")?.at(-1)).toEqual([{ catalog_database: { name: "Flight" } }]);
  expect(wrapper.get("#catalog-database-new-cancel").attributes("href")).toBe(
    "/missions/mission-a/catalog",
  );
  expect(wrapper.get("#catalog-upload-submit").attributes("disabled")).toBeDefined();
  wrapper.unmount();
});
test("database details retain disclosure and real revision history", async () => {
  const data = databaseShowFixture();
  assertDatabaseShow(data);
  const wrapper = mount(CatalogDatabaseShow, { props: data });
  expect(wrapper.find("#revision-row-one").exists()).toBe(true);
  expect(wrapper.find("#import-row-one").exists()).toBe(true);
  await wrapper.get("#add-revision-toggle").trigger("click");
  expect(wrapper.emitted("toggle-revision-form")).toHaveLength(1);
  expect(wrapper.find("#catalog-upload-form").exists()).toBe(true);
  wrapper.unmount();
});
