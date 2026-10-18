import { required } from "../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { createApp, defineComponent, h, nextTick } from "vue";
import { inApplicationShell } from "./page-portal";
import { withImmediateVueUnmount } from "./live-vue-lifecycle";

afterEach(() => {
  document.body.innerHTML = "";
});

test("destroying a page removes teleported content without another navigation event", async () => {
  document.body.innerHTML = '<main id="application-content"></main><div id="transport"></div>';
  const app = createApp(
    inApplicationShell(
      defineComponent({
        setup: () => () => h("article", { id: "departed-page" }, "Page"),
      }),
    ),
  );
  const transport = required(document.querySelector("#transport"));
  app.mount(transport);
  await nextTick();
  expect(document.querySelector("#departed-page")).not.toBeNull();

  const cleanup = vi.fn();
  const hook = withImmediateVueUnmount({ destroyed: cleanup });
  const instance = { vue: { app } };
  transport.remove();
  hook.destroyed.call(instance);

  expect(document.querySelector("#departed-page")).toBeNull();
  expect(instance.vue.app).toBeNull();
  expect(cleanup).toHaveBeenCalledOnce();
  expect(cleanup.mock.contexts[0]).toBe(instance);
});

test("document navigation preserves the native form until the browser submits it", async () => {
  document.body.innerHTML = '<main id="application-content"></main><div id="transport"></div>';
  const app = createApp(
    inApplicationShell(
      defineComponent({
        setup: () => () =>
          h("form", { id: "native-admin-form", action: "/admin-mode", method: "post" }, [
            h("input", { name: "_csrf_token", value: "csrf" }),
            h("input", { name: "admin_mode[password]", type: "password", value: "fixture" }),
          ]),
      }),
    ),
  );
  app.mount(required(document.querySelector("#transport")));
  await nextTick();
  const form = required(document.querySelector<HTMLFormElement>("#native-admin-form"));
  const cleanup = vi.fn();
  const instance = { vue: { app }, liveSocket: { isUnloaded: () => true } };
  withImmediateVueUnmount({ destroyed: cleanup }).destroyed.call(instance);

  expect(form.isConnected).toBe(true);
  expect(new FormData(form).get("_csrf_token")).toBe("csrf");
  expect(new FormData(form).get("admin_mode[password]")).toBe("fixture");
  expect(instance.vue.app).toBe(app);
  expect(cleanup).toHaveBeenCalledOnce();
  app.unmount();
});
