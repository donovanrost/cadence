// @vitest-environment happy-dom
import { defineComponent, h, nextTick, provide, ref } from "vue";
import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import {
  pageHeaderKey,
  useManagementHeader,
  useOpsHeader,
  useOpsHeaders,
  type PageAction,
  type PageHeaderHost,
} from "./page-header";
import { readPageHeader } from "./page-header-validation";
import { href } from "./routes";

const alarms = "/missions/:mission_id/ops/alarms" as const;
const settings = "/missions/:mission_id/ops/dashboards/:dashboard_id/settings" as const;
const viewer = "/missions/:mission_id/ops/dashboards/:dashboard_id" as const;
const transports = "/missions/:mission_id/comms/transports" as const;
const transport = "/missions/:mission_id/comms/transports/:transport_id" as const;
const link = href(alarms, { mission_id: "m" });
const ops = { kind: "collection", layer: "ops" } as const;

test("header rules are type errors", () => {
  const a: PageAction = { id: "a", label: "A", href: link };
  const typed = () => {
    // @ts-expect-error -- collection pages take their title from the route
    useOpsHeader(alarms, { title: "Alarm conditions" });
    // @ts-expect-error -- resource pages must name their resource
    useOpsHeader(settings, { description: "Settings" });
    useOpsHeader(settings, { title: "Pass Overview", status: { tone: "warning", label: "Off" } });
    // @ts-expect-error -- pages that own their identity bar have no host header
    useOpsHeader(viewer, {});
    useOpsHeader(alarms, { actions: [a, a, a], more: [a] });
    // @ts-expect-error -- a fourth button does not compile; overflow goes in `more`
    useOpsHeader(alarms, { actions: [a, a, a, a] });
  };
  // @ts-expect-error -- icons come from the vendored set
  const typo: PageAction = { id: "x", label: "X", icon: "hero-chevon-down", href: link };
  // @ts-expect-error -- links must be built from the route catalog
  const raw: PageAction = { id: "x", label: "X", href: "/missions" };
  // @ts-expect-error -- only menu entries may be destructive
  const danger: PageAction = { id: "x", label: "X", href: link, tone: "danger" };
  expect([typed, typo, raw, danger]).toHaveLength(4);
});

test("each layer has its own contract and only its own routes", () => {
  const a: PageAction = { id: "a", label: "A", href: link };
  const typed = () => {
    // @ts-expect-error -- a management route is not an Ops page
    useOpsHeader(transports, {});
    // @ts-expect-error -- an Ops route is not a management page
    useManagementHeader(alarms, {});
    useManagementHeader(transports, { facts: ["3 configured"], primary: a });
    // @ts-expect-error -- records reload with the browser; there is no refresh
    useManagementHeader(transports, { refresh: { run: () => {} } });
    // @ts-expect-error -- management headers hold two quiet buttons
    useManagementHeader(transports, { actions: [a, a, a] });
    useManagementHeader(transport, { title: "S-band primary", identifier: "transport_01" });
    // @ts-expect-error -- collection pages have no record identifier
    useManagementHeader(transports, { identifier: "transport_01" });
  };
  expect(typed).toBeTypeOf("function");
});

test("a component serving several routes types each header by its route", () => {
  const typed = () => {
    useOpsHeaders({
      [alarms]: { description: "Alarms" },
      [settings]: () => ({ title: "Pass Overview" }),
    });
    // @ts-expect-error -- the settings route is a resource page and must be named
    useOpsHeaders({ [settings]: { description: "Settings" } });
  };
  expect(typed).toBeTypeOf("function");
});

test("the host admits only well-formed headers for the route's policy", () => {
  expect(readPageHeader({ description: "Latest evaluated limit states." }, ops)).toEqual({
    description: "Latest evaluated limit states.",
  });
  const record = { kind: "resource", layer: "management" } as const;
  expect(readPageHeader({ title: "S-band", identifier: "transport_01" }, record)).toEqual({
    title: "S-band",
    identifier: "transport_01",
  });
  const x = { id: "x", label: "X", href: "/a" };
  for (const [value, kind, layer] of [
    [{ title: "Renamed" }, "collection", "ops"],
    [{ description: "x" }, "resource", "ops"],
    [{ actions: [1, 2, 3, 4] }, "collection", "ops"],
    [{ primary: { ...x, href: "//evil.test" } }, "collection", "ops"],
    [{ primary: { ...x, icon: "fa-star" } }, "collection", "ops"],
    [{ actions: [x], more: [{ ...x, label: "Y" }] }, "collection", "ops"],
    [{ eyebrow: "SYSTEM" }, "collection", "ops"],
    [{ description: "x".repeat(241) }, "collection", "ops"],
    [{ title: "A", identifier: "a" }, "resource", "ops"],
    [{ refresh: { run: () => {} } }, "collection", "management"],
    [{ actions: [x, { ...x, id: "y" }, { ...x, id: "z" }] }, "collection", "management"],
    [{ identifier: "a" }, "collection", "management"],
  ] as const)
    expect(() => readPageHeader(value, { kind, layer })).toThrow();
});

test("a page claims the header, keeps it current and releases it on unmount", async () => {
  const claim = vi.fn(),
    update = vi.fn(),
    release = vi.fn();
  const host: PageHeaderHost = { route: () => alarms, claim, update, release };
  const count = ref(1);
  const Page = defineComponent(() => {
    useOpsHeader(alarms, () => ({ facts: [`${count.value} active`] }));
    return () => h("div");
  });
  const wrapper = mount(
    defineComponent(() => {
      provide(pageHeaderKey, host);
      return () => h(Page);
    }),
  );
  expect(claim).toHaveBeenCalledWith(expect.any(Symbol), [alarms]);
  expect(update).toHaveBeenLastCalledWith(expect.any(Symbol), { facts: ["1 active"] });
  count.value = 2;
  await nextTick();
  expect(update).toHaveBeenLastCalledWith(expect.any(Symbol), { facts: ["2 active"] });
  wrapper.unmount();
  expect(release).toHaveBeenCalledOnce();
});
