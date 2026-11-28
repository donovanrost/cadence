// @vitest-environment happy-dom
import { defineComponent, h, nextTick, provide, ref } from "vue";
import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import {
  pageHeaderKey,
  useManagementHeader,
  useManagementHeaders,
  useOpsHeader,
  type PageAction,
  type PageHeaderHost,
} from "./page-header";
import { readPageHeader } from "./page-header-validation";
import { href } from "./routes";

// The catalog holds only the application-surface route (a management resource page), so the header
// type rules are exercised on it; the Ops and collection policies are still admitted at runtime
// (readPageHeader below).
const surface = "/missions/:mission_id/applications/:application_key/:surface_id" as const;
const link = href(surface, { mission_id: "m", application_key: "ops_console", surface_id: "s" });
const ops = { kind: "collection", layer: "ops" } as const;

test("header rules are type errors", () => {
  const a: PageAction = { id: "a", label: "A", href: link };
  const typed = () => {
    // @ts-expect-error -- resource pages must name their resource
    useManagementHeader(surface, { description: "Settings" });
    useManagementHeader(surface, {
      title: "Pass Overview",
      status: { tone: "warning", label: "Off" },
    });
    useManagementHeader(surface, { title: "Pass Overview", actions: [a, a], more: [a] });
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
    useOpsHeader(surface, {});
    useManagementHeader(surface, { title: "Pass Overview", facts: ["3 configured"], primary: a });
    // @ts-expect-error -- records reload with the browser; there is no refresh
    useManagementHeader(surface, { title: "Pass Overview", refresh: { run: () => {} } });
    // @ts-expect-error -- management headers hold two quiet buttons
    useManagementHeader(surface, { title: "Pass Overview", actions: [a, a, a] });
    useManagementHeader(surface, { title: "Packet bindings", identifier: "packet_bindings" });
  };
  expect(typed).toBeTypeOf("function");
});

test("a component serving several routes types each header by its route", () => {
  const typed = () => {
    useManagementHeaders({ [surface]: () => ({ title: "Pass Overview" }) });
    // @ts-expect-error -- the application surface route is a resource page and must be named
    useManagementHeaders({ [surface]: { description: "Settings" } });
  };
  expect(typed).toBeTypeOf("function");
});

test("the host admits only well-formed headers for the route's policy", () => {
  expect(readPageHeader({ description: "Latest evaluated limit states." }, ops)).toEqual({
    description: "Latest evaluated limit states.",
  });
  const record = { kind: "resource", layer: "management" } as const;
  expect(readPageHeader({ title: "Mission catalog", identifier: "catalog_01" }, record)).toEqual({
    title: "Mission catalog",
    identifier: "catalog_01",
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
  const host: PageHeaderHost = { route: () => surface, claim, update, release };
  const count = ref(1);
  const Page = defineComponent(() => {
    useManagementHeader(surface, () => ({
      title: "Pass Overview",
      facts: [`${count.value} active`],
    }));
    return () => h("div");
  });
  const wrapper = mount(
    defineComponent(() => {
      provide(pageHeaderKey, host);
      return () => h(Page);
    }),
  );
  expect(claim).toHaveBeenCalledWith(expect.any(Symbol), [surface]);
  expect(update).toHaveBeenLastCalledWith(expect.any(Symbol), {
    title: "Pass Overview",
    facts: ["1 active"],
  });
  count.value = 2;
  await nextTick();
  expect(update).toHaveBeenLastCalledWith(expect.any(Symbol), {
    title: "Pass Overview",
    facts: ["2 active"],
  });
  wrapper.unmount();
  expect(release).toHaveBeenCalledOnce();
});
