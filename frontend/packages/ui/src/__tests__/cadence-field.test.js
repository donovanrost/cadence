import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  expectedNodeVersion,
  installDom,
  loadSfc,
  integrationRequire,
} from "../../../../test-support/mounted-contract.js";

import { test } from "vite-plus/test";

test("cadence field native behavior", async () => {
  const testDirectory = dirname(fileURLToPath(import.meta.url));
  const componentPath = resolve(testDirectory, "../CadenceField.vue");
  const source = await readFile(componentPath, "utf8");
  const dom = installDom('<div id="field-contract"></div><div id="field-optional-contract"></div>');
  const CadenceField = (await loadSfc(componentPath)).component;
  const { createApp, defineComponent, h } = integrationRequire("vue");

  let nativeControl = null;
  const inputEvents = [];
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
                ref: (element) => {
                  nativeControl = element;
                },
                id: "ground_station_id",
                name: "ground_station[ground_station_id]",
                type: "text",
                value: "dss-14",
                required: true,
                disabled: true,
                placeholder: "DSS-14",
                class: "w-full input",
                onInput: (event) => inputEvents.push(event.currentTarget),
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

  const host = dom.window.document.querySelector("#field-contract");
  const app = createApp(Contract);
  app.mount(host);

  const root = host.firstElementChild;
  const input = root.querySelector("input");

  assert.strictEqual(input, nativeControl, "the slotted native control keeps its DOM identity");
  assert.equal(
    root.outerHTML,
    '<div class="fieldset mb-3"><label for="ground_station_id"><span class="hud-label block mb-1.5">Ground Station ID</span><input id="ground_station_id" name="ground_station[ground_station_id]" type="text" required="" disabled="" placeholder="DSS-14" class="w-full input" value="dss-14"></label><p class="mt-1 text-xs">Server-authored help</p><p class="mt-1.5 text-sm text-error">can\'t be blank</p><p class="mt-1.5 text-sm text-error">has already been taken</p></div>',
    "wrapper, label, label text, native control, help, and errors render without extra nodes",
  );

  input.dispatchEvent(new dom.window.Event("input", { bubbles: true }));
  assert.deepEqual(inputEvents, [input], "native input events reach the owning consumer unchanged");

  app.unmount();
  assert.equal(host.children.length, 0);

  const optionalHost = dom.window.document.querySelector("#field-optional-contract");
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

  const optionalRoot = optionalHost.firstElementChild;
  const optionalLabel = optionalRoot.querySelector("label");
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
