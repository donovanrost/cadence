import { afterEach, expect, test } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import { defineComponent, h, nextTick } from "vue";
import { inApplicationShell } from "./page-portal";
const wrappers: Array<{ unmount(): void }> = [];
afterEach(() => {
  for (const wrapper of wrappers.splice(0)) wrapper.unmount();
  document.body.innerHTML = "";
});
test("page survives shell updates, delayed shell mount and transport prop changes", async () => {
  const Page = defineComponent({
    props: { csrfToken: String },
    setup: (props) => () =>
      h("form", { id: "portal-form" }, [
        h("input", { name: "_csrf_token", value: props.csrfToken }),
        h("input", { name: "email" }),
      ]),
  });
  const page = mount(inApplicationShell(Page), {
    attachTo: document.body,
    attrs: { csrfToken: "first" },
  });
  wrappers.push(page);
  expect(document.querySelector("#portal-form")).toBeNull();
  const shell = mount(
    defineComponent({
      props: { count: Number },
      setup: (props) => () =>
        h("main", [h("span", props.count), h("div", { id: "application-content" })]),
    }),
    { attachTo: document.body, props: { count: 0 } },
  );
  wrappers.push(shell);
  await flushPromises();
  await nextTick();
  const field = document.querySelector<HTMLInputElement>('[name="email"]')!;
  field.value = "typed@example.test";
  await shell.setProps({ count: 1 });
  await page.setProps({ csrfToken: "refreshed" });
  await flushPromises();
  expect(document.querySelector('[name="email"]')).toBe(field);
  expect(field.value).toBe("typed@example.test");
  expect(document.querySelector<HTMLInputElement>('[name="_csrf_token"]')!.value).toBe("refreshed");
  page.unmount();
  expect(document.querySelector("#portal-form")).toBeNull();
});
