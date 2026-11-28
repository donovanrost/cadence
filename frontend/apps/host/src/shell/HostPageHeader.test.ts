import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { useManagementHeader, useManagementHeaders } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import HostPage from "./HostPage.vue";

// The application surface route is the host page FederatedPageFrame still draws (#708 deleted the
// last Ops routes); the settings route is only the "other route" a page wrongly claims.
const surface = "/missions/:mission_id/applications/:application_key/:surface_id";
const settings = "/missions/:mission_id/settings";
const breadcrumbs = [{ label: "Kestrel", href: "/missions/m" }, { label: "Data Sources" }];
let wrapper: ReturnType<typeof mount> | undefined;
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

function render(route: string, page: ReturnType<typeof defineComponent>, title = "Data Sources") {
  wrapper = mount(HostPage, {
    props: { title, route, breadcrumbs, section: "System" },
    slots: { default: () => h(page) },
  });
  return wrapper;
}

test("the host draws a page's typed header with one primary and quiet actions", async () => {
  const run = vi.fn(async () => {});
  const page = defineComponent(() => {
    useManagementHeader(surface, () => ({
      title: "Data Sources",
      description: "Every telemetry source in this mission.",
      facts: ["3 sources"],
      actions: [
        {
          id: "settings",
          label: "Mission settings",
          href: href(settings, { mission_id: "m" }),
        },
      ],
      primary: { id: "register", label: "Register source", run },
    }));
    return () => h("p", "body");
  });
  const host = render(surface, page);
  await flushPromises();
  const heading = host.get("#host-page-heading");
  expect(heading.attributes("data-page-heading-source")).toBe("page");
  expect(heading.get("h1").text()).toBe("Data Sources");
  expect(heading.text()).toContain("Every telemetry source in this mission.");
  expect(heading.text()).toContain("3 sources");
  expect(heading.get("#host-action-settings").attributes("href")).toBe("/missions/m/settings");
  expect(heading.get("#host-action-register").classes()).toContain("btn-primary");
  expect(heading.findAll(".btn-primary")).toHaveLength(1);
  await heading.get("#host-action-register").trigger("click");
  expect(run).toHaveBeenCalledOnce();
});

test("resource pages name themselves and show their status", async () => {
  const page = defineComponent(() => {
    useManagementHeader(surface, {
      title: "Pass Overview",
      status: { tone: "warning", label: "Archived" },
    });
    return () => h("p");
  });
  const host = render(surface, page, "Ops Console");
  await flushPromises();
  expect(host.get("h1").text()).toBe("Pass Overview");
  expect(host.get("#host-page-heading").text()).toContain("Archived");
});

test("a header claimed for another route is refused and the route's own header stays", async () => {
  const error = vi.spyOn(console, "error").mockImplementation(() => {});
  const page = defineComponent(() => {
    useManagementHeaders({ [settings]: { description: "Wrong page" } });
    return () => h("p");
  });
  const host = render(surface, page);
  await flushPromises();
  expect(error).toHaveBeenCalled();
  expect(host.get("h1").text()).toBe("Data Sources");
  expect(host.get("#host-page-heading").text()).not.toContain("Wrong page");
});

test("pages not yet migrated keep publishing through CadencePageHeading", async () => {
  const page = defineComponent(
    () => () => h(CadencePageHeading, null, { title: () => "Legacy title" }),
  );
  const host = render(surface, page);
  await flushPromises();
  expect(host.get("#host-page-heading").attributes("data-page-heading-source")).toBe("application");
  expect(host.get("#host-page-heading").text()).toContain("Legacy title");
});
