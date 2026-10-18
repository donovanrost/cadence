import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
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
  const wrapper = mount(pageHeaderHarness("/missions/:mission_id/catalog").stage(CatalogIndex), {
    props: data,
  });
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
  const wrapper = mount(
    pageHeaderHarness("/missions/:mission_id/catalog/databases/:catalog_database_id").stage(
      CatalogDatabaseShow,
    ),
    { props: data },
  );
  expect(wrapper.find("#revision-row-one").exists()).toBe(true);
  expect(wrapper.find("#import-row-one").exists()).toBe(true);
  await wrapper.get("#add-revision-toggle").trigger("click");
  expect(wrapper.findComponent(CatalogDatabaseShow).emitted("toggle-revision-form")).toHaveLength(
    1,
  );
  expect(wrapper.find("#catalog-upload-form").exists()).toBe(true);
  wrapper.unmount();
});

test.each([
  [{ active_count: 0, saved_count: 0 }, "No active or saved spacecraft configurations"],
  [{ active_count: 0, saved_count: 2 }, "Saved configuration on 2 spacecraft"],
  [{ active_count: 1, saved_count: 0 }, "Active on 1 spacecraft"],
  [
    { active_count: 1, saved_count: 1 },
    "Active on 1 spacecraft · Saved configuration on 1 spacecraft",
  ],
])("directory, database and revision history agree on usage %j", (usage, label) => {
  const index = databaseIndexFixture();
  required(index.presentation.card.rows[0]).spacecraft_usage = usage;
  const detail = databaseShowFixture();
  detail.database.spacecraft_usage = usage;
  required(detail.revisions[0]).spacecraft_usage = usage;
  assertDatabaseIndex(index);
  assertDatabaseShow(detail);
  const list = mount(CatalogIndex, { props: index });
  const database = mount(CatalogDatabaseShow, { props: detail });
  expect(list.get("#database-row-one-usage").text()).toBe(label);
  expect(list.get("#database-row-one-usage").attributes("href")).toBe(
    detail.navigation.catalog.href + "/databases/one",
  );
  expect(database.get("#catalog-spacecraft-usage-summary").text()).toBe(label);
  expect(database.get("#revision-row-one-usage").text()).toBe(label);
  list.unmount();
  database.unmount();
});
test("usage counts must be present, nonnegative safe integers", () => {
  for (const invalid of [
    undefined,
    null,
    { active_count: -1, saved_count: 0 },
    { active_count: 1, saved_count: 0.5 },
  ]) {
    const data = databaseShowFixture();
    expect(() =>
      assertDatabaseShow({ ...data, database: { ...data.database, spacecraft_usage: invalid } }),
    ).toThrow();
    const index = databaseIndexFixture();
    expect(() =>
      assertDatabaseIndex({
        ...index,
        presentation: {
          ...index.presentation,
          card: {
            ...index.presentation.card,
            rows: [{ ...required(index.presentation.card.rows[0]), spacecraft_usage: invalid }],
          },
        },
      }),
    ).toThrow();
  }
});
