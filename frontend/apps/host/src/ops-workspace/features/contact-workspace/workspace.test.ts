import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import { createMemoryHistory } from "vue-router";
import { VueQueryPlugin } from "@tanstack/vue-query";
import { scheduleFixture } from "../../../../../../modules/planning-and-contacts/src/features/contact-scheduling/contact-schedule.test-support";
import { contactRecordFixture } from "../../../../../../modules/planning-and-contacts/src/features/contact-scheduling/contact-record.test-support";
import { required } from "../../../../../../test-support/required";
import ContactWorkspaceApp from "./ContactWorkspaceApp.vue";
import { createContactWorkspaceRouter } from "./router";
import { createWorkspaceClient, createWorkspaceQueryClient, workspaceClientKey } from "./client";
import { readWorkspaceBootstrap, workspaceBase, workspaceDestination } from "./contracts";

const bootstrap = readWorkspaceBootstrap({
  version: 1,
  actor_id: "operator-one",
  organization_id: "org-one",
  mission_id: "mission-one",
  context: {
    version: 1,
    user: { user_id: "operator-one", display_name: "Operator", email: "operator@example.test" },
    organization: { organization_id: "org-one", display_name: "Organization" },
    mission: { mission_id: "mission-one", display_name: "Mission", slug: "mission" },
    csrf_token: "test-csrf",
    capabilities: [],
    dock_surfaces: [],
  },
});
const base = workspaceBase(bootstrap.missionId);
const cleanups: (() => void)[] = [];
afterEach(() => {
  cleanups
    .splice(0)
    .reverse()
    .forEach((cleanup) => cleanup());
  vi.unstubAllGlobals();
});
function envelope(data: unknown) {
  return {
    version: 1,
    actor_id: bootstrap.actorId,
    organization_id: bootstrap.organizationId,
    mission_id: bootstrap.missionId,
    data,
  };
}
type Request = { url: string; options: RequestInit; reply(data: unknown, status?: number): void };
async function setup() {
  const requests: Request[] = [];
  vi.stubGlobal(
    "fetch",
    (url: string, options: RequestInit) =>
      new Promise<Response>((resolve) => {
        requests.push({
          url,
          options,
          reply: (data, status = 200) => resolve(new Response(JSON.stringify(data), { status })),
        });
      }),
  );
  const queries = createWorkspaceQueryClient();
  queries.setDefaultOptions({
    queries: { ...queries.getDefaultOptions().queries, refetchInterval: false },
  });
  const client = createWorkspaceClient(bootstrap, queries);
  const router = createContactWorkspaceRouter(bootstrap.missionId, createMemoryHistory());
  await router.push(`${base}?spacecraft_id=craft-one`);
  await router.isReady();
  const wrapper = mount(ContactWorkspaceApp, {
    props: { bootstrap },
    global: {
      plugins: [router, [VueQueryPlugin, { queryClient: queries }]],
      provide: { [workspaceClientKey]: client },
    },
  });
  cleanups.push(() => {
    wrapper.unmount();
    queries.clear();
    router.options.history.destroy();
  });
  await flushPromises();
  return { requests, queries, client, router, wrapper };
}
async function schedule(requests: Request[]) {
  required(requests.at(-1)).reply(envelope({ schedule: scheduleFixture() }));
  await flushPromises();
}
function input(wrapper: VueWrapper, selector: string) {
  const element = wrapper.get(selector).element;
  if (!(element instanceof HTMLInputElement)) throw Error("Expected input");
  return element;
}

test("the route and shell render before data; edits do not make requests", async () => {
  const { requests, wrapper, router } = await setup();
  expect(router.currentRoute.value.path).toBe(base);
  expect(wrapper.find("#ops-workspace-header").exists()).toBe(true);
  expect(wrapper.find("#contact-workspace-loading").exists()).toBe(true);
  await schedule(requests);
  expect(wrapper.find("#ops-contact-schedule-page").exists()).toBe(true);
  await wrapper.get("#search-start").setValue("2099-09-10T12:00:00");
  expect(requests).toHaveLength(1);
  expect(input(wrapper, "#search-start").value).toContain("2099-09-10");
});

test("A → B → Back shows cached A immediately and ignores departed B", async () => {
  const { requests, wrapper, router } = await setup();
  await schedule(requests);
  const shell = wrapper.get("#ops-workspace-header").element;
  await router.push(`${base}/records/scheduled-one`);
  await flushPromises();
  const delayed = required(requests.at(-1));
  expect(wrapper.find("#contact-workspace-loading").exists()).toBe(true);
  router.back();
  await flushPromises();
  expect(wrapper.find("#ops-contact-schedule-page").exists()).toBe(true);
  expect(wrapper.get("#ops-workspace-header").element).toBe(shell);
  expect(delayed.options.signal?.aborted).toBe(true);
  delayed.reply(envelope({ record: contactRecordFixture() }));
  await flushPromises();
  expect(wrapper.find("#ops-contact-record-page").exists()).toBe(false);
});

test("query navigation settles without a document reload and modified links stay native", async () => {
  const { requests, wrapper, router } = await setup();
  await schedule(requests);
  const link = wrapper.find('a[href*="/contact-workspace/records/"]');
  expect(link.exists()).toBe(true);
  await link.trigger("click", { ctrlKey: true });
  expect(router.currentRoute.value.path).toBe(base);
  await wrapper.get("#spacecraft-query").setValue("another");
  await wrapper.get("#contact-spacecraft-filter").trigger("submit");
  await flushPromises();
  expect(router.currentRoute.value.query.spacecraft_q).toBe("another");
  expect(wrapper.find("#contact-workspace-loading").exists()).toBe(true);
  expect(required(requests.at(-1)).url).toContain("spacecraft_q=another");
});

test("refresh replaces server evidence without resetting local search inputs", async () => {
  const { requests, wrapper, queries } = await setup();
  await schedule(requests);
  await wrapper.get("#search-start").setValue("2099-09-10T12:00:00");
  const refresh = queries.invalidateQueries();
  await flushPromises();
  const next = scheduleFixture();
  next.initial_window.starts_at = "2099-09-11T12:00:00Z";
  next.initial_window.ends_at = "2099-09-11T13:00:00Z";
  required(requests.at(-1)).reply(envelope({ schedule: next }));
  await refresh;
  await flushPromises();
  expect(input(wrapper, "#search-start").value).toContain("2099-09-10");
});

test("a failed record leaves navigation usable and retry recovers that record", async () => {
  const { requests, wrapper, router } = await setup();
  await schedule(requests);
  await router.push(`${base}/records/scheduled-one`);
  await flushPromises();
  required(requests.at(-1)).reply({ code: "unavailable" }, 404);
  await flushPromises();
  expect(wrapper.find("#contact-workspace-error").exists()).toBe(true);
  expect(wrapper.find("#ops-contact-schedule-page").exists()).toBe(false);
  await wrapper.get("#contact-workspace-retry").trigger("click");
  required(requests.at(-1)).reply(envelope({ record: contactRecordFixture() }));
  await flushPromises();
  expect(wrapper.find("#ops-contact-record-page").exists()).toBe(true);
});

test("a changed session clears cached data and removes action controls", async () => {
  const { requests, wrapper, queries, router } = await setup();
  await schedule(requests);
  await router.push(`${base}/records/scheduled-one`);
  await flushPromises();
  required(requests.at(-1)).reply({ code: "session_changed" }, 409);
  await flushPromises();
  expect(wrapper.find("#contact-workspace-session-changed").exists()).toBe(true);
  expect(wrapper.find("#contact-search-submit").exists()).toBe(false);
  expect(queries.getQueryCache().getAll()).toHaveLength(0);
});

test("foreign identities never enter the cache", async () => {
  const { requests, wrapper } = await setup();
  required(requests.at(-1)).reply({
    ...envelope({ schedule: scheduleFixture() }),
    mission_id: "foreign",
  });
  await flushPromises();
  expect(wrapper.find("#ops-contact-schedule-page").exists()).toBe(false);
  expect(wrapper.find("#contact-workspace-error").exists()).toBe(true);
});

test("a different record ID cannot replace the requested record", async () => {
  const { requests, wrapper, router } = await setup();
  await schedule(requests);
  await router.push(`${base}/records/another-record`);
  await flushPromises();
  required(requests.at(-1)).reply(envelope({ record: contactRecordFixture() }));
  await flushPromises();
  expect(wrapper.find("#ops-contact-record-page").exists()).toBe(false);
  expect(wrapper.find("#contact-workspace-error").exists()).toBe(true);
});

test("navigation mapping keeps reservation review, foreign missions, and external URLs native", () => {
  const origin = "https://cadence.test";
  expect(
    workspaceDestination(
      "/missions/mission-one/ops/contacts?spacecraft_id=x",
      "mission-one",
      origin,
    ),
  ).toBe(`${base}?spacecraft_id=x`);
  for (const href of [
    "/missions/other/ops/contacts",
    "/missions/mission-one/ops/contacts/reservation-one",
    "https://external.test/",
  ])
    expect(workspaceDestination(href, "mission-one", origin)).toBeNull();
});
