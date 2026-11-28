import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, h, ref } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { useOpsHeader, useOpsHeaders } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import HostPage from "./HostPage.vue";

const commands = "/missions/:mission_id/ops/commands";
const request = "/missions/:mission_id/ops/commands/requests/:command_request_id/history";
const breadcrumbs = [{ label: "Kestrel", href: "/missions/m" }, { label: "Commands" }];
let wrapper: ReturnType<typeof mount> | undefined;
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

function render(route: string, page: ReturnType<typeof defineComponent>, title = "Commands") {
  wrapper = mount(HostPage, {
    props: { title, route, breadcrumbs, section: "Observe" },
    slots: { default: () => h(page) },
  });
  return wrapper;
}

test("the host draws a page's typed header with one primary, quiet actions and refresh", async () => {
  const run = vi.fn(async () => {});
  const reading = ref(false);
  const page = defineComponent(() => {
    useOpsHeader(commands, () => ({
      description: "Every command request in this mission.",
      facts: ["3 in flight"],
      actions: [
        { id: "posture", label: "Current posture", href: href(commands, { mission_id: "m" }) },
      ],
      primary: { id: "ack", label: "Acknowledge", run },
      refresh: { run, pending: reading.value },
    }));
    return () => h("p", "body");
  });
  const host = render(commands, page);
  await flushPromises();
  const heading = host.get("#host-page-heading");
  expect(heading.attributes("data-page-heading-source")).toBe("page");
  expect(heading.get("h1").text()).toBe("Commands");
  expect(heading.text()).toContain("Every command request in this mission.");
  expect(heading.text()).toContain("3 in flight");
  expect(heading.get("#host-action-posture").attributes("href")).toBe("/missions/m/ops/commands");
  expect(heading.get("#host-action-ack").classes()).toContain("btn-primary");
  expect(heading.findAll(".btn-primary")).toHaveLength(1);
  await heading.get("#host-page-refresh").trigger("click");
  expect(run).toHaveBeenCalledOnce();
  reading.value = true;
  await flushPromises();
  expect(heading.get("#host-page-refresh").attributes("disabled")).toBeDefined();
});

test("resource pages name themselves and show their status", async () => {
  const page = defineComponent(() => {
    useOpsHeader(request, {
      title: "Pass Overview",
      status: { tone: "warning", label: "Archived" },
    });
    return () => h("p");
  });
  const host = render(request, page, "Command Request");
  await flushPromises();
  expect(host.get("h1").text()).toBe("Pass Overview");
  expect(host.get("#host-page-heading").text()).toContain("Archived");
});

test("a header claimed for another route is refused and the route's own header stays", async () => {
  const error = vi.spyOn(console, "error").mockImplementation(() => {});
  const page = defineComponent(() => {
    useOpsHeaders({ [request]: { title: "Wrong page" } });
    return () => h("p");
  });
  const host = render(commands, page);
  await flushPromises();
  expect(error).toHaveBeenCalled();
  expect(host.get("h1").text()).toBe("Commands");
  expect(host.get("#host-page-heading").text()).not.toContain("Wrong page");
});

test("pages not yet migrated keep publishing through CadencePageHeading", async () => {
  const page = defineComponent(
    () => () => h(CadencePageHeading, null, { title: () => "Legacy title" }),
  );
  const host = render(commands, page);
  await flushPromises();
  expect(host.get("#host-page-heading").attributes("data-page-heading-source")).toBe("application");
  expect(host.get("#host-page-heading").text()).toContain("Legacy title");
});
