import { createApp, defineComponent, h, nextTick, ref } from "vue";
import CadenceCollapsible from "../CadenceCollapsible.vue";
import CadenceCollapsibleTrigger from "../CadenceCollapsibleTrigger.vue";
import CadenceCollapsibleContent from "../CadenceCollapsibleContent.vue";
import { required } from "../../../../test-support/required";
import assert from "node:assert/strict";
import { flushVue, installDom } from "../../../../test-support/mounted-contract";

import { test } from "vite-plus/test";

test("cadence collapsible adapter native behavior", async () => {
  const scenarios = Object.freeze([
    "the controlled root preserves the server-authored public root instead of adding a wrapper",
    "compound trigger and content preserve the explicit aria-controls and id relationship",
    "arbitrary server siblings retain their order around collapsible content",
    "trigger activation requests the next state without opening or closing optimistically",
    "closed content is unmounted and disabled roots reject activation",
  ]);

  const dom = installDom();

  const open = ref(false);
  const disabled = ref(false);
  const requestedStates: boolean[] = [];

  const RuntimeOracle = defineComponent({
    name: "CadenceCollapsibleRuntimeOracle",
    setup() {
      return () =>
        h(
          CadenceCollapsible,
          {
            open: open.value,
            contentId: "catalog-revision-upload-slot",
            disabled: disabled.value,
            onRequestChange: (nextOpen: boolean) => requestedStates.push(nextOpen),
          },
          {
            default: () =>
              h(
                "main",
                {
                  id: "catalog-database-show-surface",
                  class: "space-y-6",
                  "data-state": open.value ? "closed" : "open",
                  "data-disabled": disabled.value ? undefined : "child-stale",
                  "data-server-root": "preserved",
                },
                [
                  h("header", { id: "catalog-header" }, [
                    h(CadenceCollapsibleTrigger, null, {
                      default: () =>
                        h(
                          "button",
                          {
                            id: "add-revision-toggle",
                            type: "button",
                            "aria-controls": "stale-child-content-id",
                            "aria-expanded": "true",
                            class: "btn",
                            disabled: !disabled.value,
                            "data-disabled": "child-stale",
                            "data-state": "child-stale",
                            "data-server-trigger": "preserved",
                          },
                          open.value ? "Cancel" : "+ Add revision",
                        ),
                    }),
                  ]),
                  h("section", { id: "database-summary" }, "Database"),
                  h(CadenceCollapsibleContent, null, {
                    default: () =>
                      h(
                        "div",
                        {
                          id: "stale-child-content-id",
                          "data-state": "child-stale",
                          "data-server-content": "preserved",
                        },
                        "Upload form",
                      ),
                  }),
                  h("section", { id: "catalog-revision-history" }, "Revision history"),
                  h("section", { id: "catalog-import-attempts" }, "Import attempts"),
                ],
              ),
          },
        );
    },
  });

  const app = createApp(RuntimeOracle);
  app.mount(required(dom.window.document.querySelector("#app")));
  await flushVue(nextTick);

  const publicRoot = required(
    dom.window.document.querySelector<HTMLElement>("#catalog-database-show-surface"),
  );
  const trigger = required(
    dom.window.document.querySelector<HTMLButtonElement>("#add-revision-toggle"),
  );
  const childIds = () => [...publicRoot.children].map((child) => child.id);

  assert.equal(required(dom.window.document.querySelector("#app")).children.length, 1);
  assert.equal(required(publicRoot.parentElement).id, "app");
  assert.equal(publicRoot.className, "space-y-6");
  assert.equal(publicRoot.getAttribute("data-server-root"), "preserved");
  assert.equal(publicRoot.getAttribute("data-state"), "closed");
  assert.equal(publicRoot.getAttribute("data-disabled"), null);
  assert.equal(trigger.getAttribute("aria-controls"), "catalog-revision-upload-slot");
  assert.equal(trigger.getAttribute("aria-expanded"), "false");
  assert.equal(trigger.disabled, false);
  assert.equal(trigger.getAttribute("data-server-trigger"), "preserved");
  assert.equal(dom.window.document.querySelector("#catalog-revision-upload-slot"), null);
  assert.deepEqual(childIds(), [
    "catalog-header",
    "database-summary",
    "catalog-revision-history",
    "catalog-import-attempts",
  ]);

  trigger.click();
  await flushVue(nextTick);
  assert.deepEqual(requestedStates, [true]);
  assert.equal(publicRoot.getAttribute("data-state"), "closed");
  assert.equal(trigger.getAttribute("aria-expanded"), "false");
  assert.equal(dom.window.document.querySelector("#catalog-revision-upload-slot"), null);

  open.value = true;
  await flushVue(nextTick);
  const content = required(
    dom.window.document.querySelector<HTMLElement>("#catalog-revision-upload-slot"),
  );
  assert.ok(content);
  assert.equal(content.getAttribute("data-server-content"), "preserved");
  assert.equal(content.getAttribute("data-state"), "open");
  assert.equal(trigger.getAttribute("aria-controls"), content.id);
  assert.equal(trigger.getAttribute("aria-expanded"), "true");
  assert.equal(publicRoot.getAttribute("data-state"), "open");
  assert.equal(publicRoot.getAttribute("data-disabled"), null);
  assert.deepEqual(childIds(), [
    "catalog-header",
    "database-summary",
    "catalog-revision-upload-slot",
    "catalog-revision-history",
    "catalog-import-attempts",
  ]);

  trigger.click();
  await flushVue(nextTick);
  assert.deepEqual(requestedStates, [true, false]);
  assert.ok(
    dom.window.document.querySelector("#catalog-revision-upload-slot"),
    "content stays mounted until the server-authored prop closes it",
  );

  open.value = false;
  await flushVue(nextTick);
  assert.equal(dom.window.document.querySelector("#catalog-revision-upload-slot"), null);
  assert.equal(publicRoot.getAttribute("data-state"), "closed");
  assert.deepEqual(childIds(), [
    "catalog-header",
    "database-summary",
    "catalog-revision-history",
    "catalog-import-attempts",
  ]);

  disabled.value = true;
  await flushVue(nextTick);
  assert.equal(trigger.disabled, true);
  assert.equal(trigger.getAttribute("data-disabled"), "");
  assert.equal(publicRoot.getAttribute("data-disabled"), "");
  trigger.click();
  await flushVue(nextTick);
  assert.deepEqual(requestedStates, [true, false]);

  disabled.value = false;
  await flushVue(nextTick);
  assert.equal(trigger.disabled, false);
  assert.equal(trigger.getAttribute("data-disabled"), null);
  assert.equal(publicRoot.getAttribute("data-disabled"), null);

  app.unmount();

  console.log(`cadence_collapsible_adapter_test passed (${scenarios.length} scenarios)`);
});
