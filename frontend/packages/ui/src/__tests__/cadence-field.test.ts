import { createApp, defineComponent, h } from "vue";
import CadenceField from "../CadenceField.vue";
import { required, nativeInput } from "../../../../test-support/mounted-contract";
import assert from "node:assert/strict";
import { installDom } from "../../../../test-support/mounted-contract";

import { test } from "vite-plus/test";

test("cadence field native behavior", async () => {
  const dom = installDom('<div id="field-contract"></div><div id="field-optional-contract"></div>');

  let nativeControl: HTMLInputElement | null = null;
  const inputEvents: (EventTarget | null)[] = [];
  const Contract = defineComponent({
    setup() {
      return () =>
        h(
          CadenceField,
          {
            controlId: "ground_station_id",
            wrapperClass: "fieldset mb-3",
            label: "Ground Station ID",
            labelClass: "hud-label block mb-1.5",
          },
          {
            default: () =>
              h("input", {
                ref: (element: unknown) => {
                  nativeControl = nativeInput(element);
                },
                id: "ground_station_id",
                name: "ground_station[ground_station_id]",
                type: "text",
                value: "dss-14",
                required: true,
                disabled: true,
                placeholder: "DSS-14",
                class: "w-full input",
                onInput: (event: Event) => inputEvents.push(event.currentTarget),
              }),
            help: () => h("p", { class: "mt-1 text-xs" }, "Server-authored help"),
            errors: () => [
              h("p", { class: "mt-1.5 text-sm text-error" }, "can't be blank"),
              h("p", { class: "mt-1.5 text-sm text-error" }, "has already been taken"),
            ],
          },
        );
    },
  });

  const host = required(dom.window.document.querySelector<HTMLElement>("#field-contract"));
  const app = createApp(Contract);
  app.mount(host);

  const root = required(host.firstElementChild);
  const input = required(root.querySelector<HTMLInputElement>("input"));

  assert.strictEqual(
    input,
    required<HTMLInputElement>(nativeControl),
    "the slotted native control keeps its DOM identity",
  );
  assert.equal(
    root.outerHTML,
    '<div class="fieldset mb-3"><label for="ground_station_id"><span class="hud-label block mb-1.5">Ground Station ID</span><input id="ground_station_id" name="ground_station[ground_station_id]" type="text" required="" disabled="" placeholder="DSS-14" class="w-full input" value="dss-14"></label><p class="mt-1 text-xs">Server-authored help</p><p class="mt-1.5 text-sm text-error">can\'t be blank</p><p class="mt-1.5 text-sm text-error">has already been taken</p></div>',
    "wrapper, label, label text, native control, help, and errors render without extra nodes",
  );

  input.dispatchEvent(new dom.window.Event("input", { bubbles: true }));
  assert.deepEqual(inputEvents, [input], "native input events reach the owning consumer unchanged");

  app.unmount();
  assert.equal(host.children.length, 0);

  const optionalHost = required(
    dom.window.document.querySelector<HTMLElement>("#field-optional-contract"),
  );
  const OptionalContract = defineComponent({
    setup() {
      return () =>
        h(
          CadenceField,
          {
            wrapperClass: "fieldset mb-3",
            label: "Unassociated field",
            labelClass: "hud-label block mb-1.5",
          },
          {
            default: () =>
              h("input", { id: "unassociated-field", type: "text", value: "unchanged" }),
          },
        );
    },
  });
  const optionalApp = createApp(OptionalContract);
  optionalApp.mount(optionalHost);

  const optionalRoot = required(optionalHost.firstElementChild);
  const optionalLabel = required(optionalRoot.querySelector<HTMLElement>("label"));
  assert.equal(
    optionalLabel.hasAttribute("for"),
    false,
    "omitted controlId emits no label for attribute",
  );
  assert.equal(
    optionalRoot.outerHTML,
    '<div class="fieldset mb-3"><label><span class="hud-label block mb-1.5">Unassociated field</span><input id="unassociated-field" type="text" value="unchanged"></label></div>',
    "optional controlId preserves the native field shell without a new label attribute",
  );

  optionalApp.unmount();
  assert.equal(optionalHost.children.length, 0);

  console.log("cadence_field_test passed");
});
