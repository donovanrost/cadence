import {
  fixtureRows,
  fixtureRecord,
  fixtureString,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import DirectoryDestination from "./DirectoryDestination.vue";

const fixture = () => ({
  version: 2,
  context: { organization_id: "org-1", mission_id: "mission-1" },
  filters: {
    query: "Flight /?&+",
    tags: ["thermal & power", "eps"],
    starred: true,
    archived: true,
    sort: "name",
    page: 2,
  },
});
const params = (filters: Record<string, unknown>) =>
  Object.fromEntries(
    Object.entries({
      query: filters.query || undefined,
      tags: Array.isArray(filters.tags) && filters.tags.length ? filters.tags.join(",") : undefined,
      starred: filters.starred ? "true" : undefined,
      archived: filters.archived ? "true" : undefined,
      sort: filters.sort === "updated" ? undefined : filters.sort,
      page: filters.page === 1 ? undefined : String(filters.page),
    }).filter(([, value]) => value !== undefined),
  );
const props = (model: unknown = fixture()) => ({
  model,
  organizationId: "org-1",
  missionId: "mission-1",
});

test("all filters survive encoded navigation to the canonical directory", () => {
  const wrapper = mount(DirectoryDestination, { props: props() });
  const url = new URL(required(wrapper.get("a").attributes("href")), "https://cadence.test");
  expect(url.pathname).toBe("/missions/mission-1/ops/dashboards");
  expect(Object.fromEntries(url.searchParams)).toEqual(params(fixture().filters));
  expect(wrapper.findAll("form,button")).toHaveLength(0);
  wrapper.unmount();
});

test.each([
  null,
  {},
  { ...fixture(), version: 1 },
  ...[
    { query: 1 },
    { query: "x".repeat(513) },
    { query: "bad\nquery" },
    { tags: "eps" },
    { tags: [1] },
    { starred: "true" },
    { sort: "widgets" },
    { page: 0 },
    { page: 1.2 },
    { page: 1_000_001 },
    { page: "2" },
  ].map((filters) => ({ ...fixture(), filters: { ...fixture().filters, ...filters } })),
  { ...fixture(), context: { organization_id: "foreign", mission_id: "mission-1" } },
  { ...fixture(), context: { organization_id: "org-1", mission_id: "foreign" } },
])("malformed or foreign context cannot expose an actionable directory: %j", (model) => {
  const wrapper = mount(DirectoryDestination, { props: props(model) });
  expect(wrapper.findAll("a")).toHaveLength(0);
  expect(wrapper.find("[role=status]").exists()).toBe(true);
  wrapper.unmount();
});

test("host context changes remove the previous destination immediately", async () => {
  const wrapper = mount(DirectoryDestination, { props: props() });
  await wrapper.setProps({ missionId: "mission-2" });
  expect(wrapper.findAll("a")).toHaveLength(0);
  await wrapper.setProps({
    model: { ...fixture(), context: { organization_id: "org-1", mission_id: "mission-2" } },
  });
  expect(wrapper.get("a").attributes("href")).toContain("/missions/mission-2/ops/dashboards?");
  await wrapper.setProps({ organizationId: "foreign" });
  expect(wrapper.findAll("a")).toHaveLength(0);
  wrapper.unmount();
});

test("actual producer models mount without accepting injected destinations", () => {
  const models = process.env.CADENCE_DIRECTORY_DESTINATIONS
    ? fixtureRows(process.env.CADENCE_DIRECTORY_DESTINATIONS)
    : [fixture()];
  for (const model of models) {
    const context = fixtureRecord(model.context);
    const organizationId = fixtureString(context.organization_id);
    const missionId = fixtureString(context.mission_id);
    const wrapper = mount(DirectoryDestination, {
      props: {
        model: { ...model, href: "https://foreign.test" },
        organizationId,
        missionId,
      },
    });
    const url = new URL(required(wrapper.get("a").attributes("href")), "https://cadence.test");
    expect(url.origin).toBe("https://cadence.test");
    expect(url.pathname).toBe(`/missions/${encodeURIComponent(missionId)}/ops/dashboards`);
    expect(Object.fromEntries(url.searchParams)).toEqual(params(fixtureRecord(model.filters)));
    wrapper.unmount();
  }
});
