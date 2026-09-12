import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, h, reactive } from "vue";
import { readFrontendDiagnostic, reportFrontendFailure } from "../frontend-diagnostics";
import { usePageBoundary } from "./use-page-boundary";

afterEach(() => vi.restoreAllMocks());
test("a refreshed snapshot remounts a renderer that previously failed", async () => {
  vi.spyOn(console, "error").mockImplementation(() => {});
  const props = reactive({
    snapshot: { ready: false },
    contributionId: "test.page",
    context: { organizationId: "org" },
    refresh: vi.fn(async () => {
      props.snapshot = { ready: true };
    }),
  });
  const renderer = defineComponent({
    setup: () => () => {
      if (!props.snapshot.ready) throw Error("render failed");
      return h("p", { id: "recovered" }, "Ready");
    },
  });
  const wrapper = mount(
    defineComponent({
      setup() {
        const boundary = usePageBoundary(props, "organization.page");
        return () =>
          h("section", [
            boundary.crashed.value
              ? h("p", { id: "reference" }, boundary.diagnosticId.value)
              : h(renderer),
            h("button", { onClick: boundary.retry }, "Retry"),
          ]);
      },
    }),
  );
  await flushPromises();
  expect(wrapper.find("#reference").exists()).toBe(true);
  await wrapper.get("button").trigger("click");
  await flushPromises();
  expect(wrapper.find("#reference").exists()).toBe(false);
  expect(wrapper.get("#recovered").text()).toBe("Ready");
  wrapper.unmount();
});
test("a contained renderer failure keeps its cause locally and emits one safe correlation record", async () => {
  const log = vi.spyOn(console, "error").mockImplementation(() => {});
  const cause = Error('password=secret {"token":"private"}');
  const broken = defineComponent({
    setup: () => () => {
      throw cause;
    },
  });
  const props = reactive({
    snapshot: {},
    contributionId: "test.page",
    context: { organizationId: "org" },
    refresh: vi.fn(async () => {
      throw Error("private retry failure");
    }),
  });
  const wrapper = mount(
    defineComponent({
      setup() {
        const boundary = usePageBoundary(props, "organization.page");
        return () =>
          h("section", [
            boundary.crashed.value
              ? h("p", { id: "reference" }, boundary.diagnosticId.value)
              : h(broken),
            h("button", { onClick: boundary.retry }, "Retry"),
          ]);
      },
    }),
  );
  await flushPromises();
  const id = wrapper.get("#reference").text();
  expect(readFrontendDiagnostic(id)?.cause).toBe(cause);
  expect(log).toHaveBeenCalledOnce();
  expect(JSON.stringify(log.mock.calls)).not.toMatch(/secret|private|password|token/);
  await wrapper.get("button").trigger("click");
  await flushPromises();
  expect(wrapper.find("#reference").exists()).toBe(true);
  expect(props.refresh).toHaveBeenCalledOnce();
  expect(log).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});
test("diagnostic transport uses allowlisted fields and bounds retained causes", () => {
  const log = vi.spyOn(console, "error").mockImplementation(() => {});
  const context = { boundary: "ops.page", contributionId: "test.page", password: "private" };
  const first = reportFrontendFailure(context, "admission", { token: "private" });
  for (let i = 0; i < 50; i++) reportFrontendFailure(context, "load", Error("private"));
  expect(readFrontendDiagnostic(first.id)).toBeUndefined();
  expect(JSON.stringify(log.mock.calls)).not.toContain("private");
});
