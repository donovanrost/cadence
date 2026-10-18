import { createApp, defineComponent, h, nextTick, ref } from "vue";
import CadenceCollapsible from "../CadenceCollapsible.vue";
import CadenceCollapsibleTrigger from "../CadenceCollapsibleTrigger.vue";
import CadenceCollapsibleContent from "../CadenceCollapsibleContent.vue";
import { required } from "../../../../test-support/required";
import assert from "node:assert/strict";
import { flushVue, installDom } from "../../../../test-support/mounted-contract";

import { test } from "vite-plus/test";

test("cadence collapsible livevue reconciliation native behavior", async () => {
  const scenarios = Object.freeze([
    "client-seeded mode requires a caller-owned seed epoch",
    "the first client-owned state is seeded from the server open prop",
    "client interaction updates effective state immediately",
    "unrelated prop reconciliation does not overwrite client-owned state",
    "an epoch change intentionally reseeds from the current server open prop",
    "keep-mounted content preserves native identity, value, id, and aria-controls",
    "controlled request, acknowledgement, and unmount behavior remains unchanged",
  ]);

  const dom = installDom('<div id="client-app"></div><div id="controlled-app"></div>');

  assert.throws(
    () =>
      createApp(CadenceCollapsible, {
        open: false,
        contentId: "missing-seed-content",
        clientSeeded: true,
      }).mount(document.createElement("div")),
    /client-seeded mode requires seedEpoch/,
  );

  const serverOpen = ref(true);
  const seedEpoch = ref(1);
  const reconciliationLabel = ref("initial");
  const clientDisabled = ref(false);
  const clientRequestedStates: boolean[] = [];

  const ClientSeededOracle = defineComponent({
    name: "CadenceCollapsibleClientSeededOracle",
    setup() {
      return () =>
        h(
          CadenceCollapsible,
          {
            open: serverOpen.value,
            contentId: "client-seeded-content",
            disabled: clientDisabled.value,
            clientSeeded: true,
            seedEpoch: seedEpoch.value,
            unmountOnHide: false,
            onRequestChange: (nextOpen: boolean) => clientRequestedStates.push(nextOpen),
          },
          {
            default: ({ open, disabled }: { open: boolean; disabled: boolean }) =>
              h(
                "section",
                {
                  id: "client-seeded-root",
                  "data-state": "caller-stale",
                  "data-disabled": "caller-stale",
                  "data-slot-open": String(open),
                  "data-slot-disabled": String(disabled),
                  "data-reconciliation": reconciliationLabel.value,
                },
                [
                  h(CadenceCollapsibleTrigger, null, {
                    default: () =>
                      h(
                        "button",
                        {
                          id: "client-seeded-trigger",
                          type: "button",
                          "aria-controls": "caller-stale-content",
                          "aria-expanded": "caller-stale",
                          "data-state": "caller-stale",
                        },
                        open ? "Close" : "Open",
                      ),
                  }),
                  h(CadenceCollapsibleContent, null, {
                    default: () =>
                      h(
                        "div",
                        {
                          id: "caller-stale-content",
                          "data-state": "caller-stale",
                        },
                        [
                          h("input", {
                            id: "client-seeded-input",
                            name: "client_seeded[draft]",
                          }),
                        ],
                      ),
                  }),
                ],
              ),
          },
        );
    },
  });

  const clientApp = createApp(ClientSeededOracle);
  clientApp.mount(required(dom.window.document.querySelector("#client-app")));
  await flushVue(nextTick);

  const clientRoot = required(
    dom.window.document.querySelector<HTMLElement>("#client-seeded-root"),
  );
  const clientTrigger = required(
    dom.window.document.querySelector<HTMLButtonElement>("#client-seeded-trigger"),
  );
  const clientContent = () => dom.window.document.querySelector("#client-seeded-content");
  const assertClientRelationship = (expectedContent: Element | null) => {
    assert.ok(expectedContent);
    assert.equal(clientTrigger.getAttribute("aria-controls"), "client-seeded-content");
    assert.equal(expectedContent.id, "client-seeded-content");
    assert.equal(clientTrigger.getAttribute("aria-controls"), expectedContent.id);
  };

  const firstClientContent = clientContent();
  const firstClientInput = required(
    dom.window.document.querySelector<HTMLInputElement>("#client-seeded-input"),
  );
  assert.ok(firstClientContent);
  assert.ok(firstClientInput);
  assert.equal(serverOpen.value, true);
  assert.equal(clientRoot.getAttribute("data-slot-open"), "true");
  assert.equal(clientRoot.getAttribute("data-state"), "open");
  assert.equal(clientTrigger.getAttribute("aria-expanded"), "true");
  assert.equal(firstClientContent.getAttribute("data-state"), "open");
  assert.equal(firstClientContent.hasAttribute("hidden"), false);
  assertClientRelationship(firstClientContent);

  firstClientInput.value = "operator draft";
  clientTrigger.click();
  await flushVue(nextTick);

  assert.deepEqual(clientRequestedStates, [false]);
  assert.equal(serverOpen.value, true, "a client request does not mutate the server seed");
  assert.equal(clientRoot.getAttribute("data-slot-open"), "false");
  assert.equal(clientRoot.getAttribute("data-state"), "closed");
  assert.equal(clientTrigger.getAttribute("aria-expanded"), "false");
  assert.equal(clientContent(), firstClientContent);
  assert.equal(firstClientContent.getAttribute("data-state"), "closed");
  assert.equal(firstClientContent.hasAttribute("hidden"), true);
  assert.equal(dom.window.document.querySelector("#client-seeded-input"), firstClientInput);
  assert.equal(firstClientInput.value, "operator draft");
  assertClientRelationship(firstClientContent);

  clientTrigger.click();
  await flushVue(nextTick);
  assert.deepEqual(clientRequestedStates, [false, true]);
  assert.equal(clientRoot.getAttribute("data-slot-open"), "true");
  assert.equal(clientRoot.getAttribute("data-state"), "open");
  assert.equal(clientTrigger.getAttribute("aria-expanded"), "true");
  assert.equal(clientContent(), firstClientContent);
  assert.equal(firstClientInput.value, "operator draft");

  serverOpen.value = false;
  reconciliationLabel.value = "unrelated-livevue-patch";
  clientDisabled.value = true;
  await flushVue(nextTick);

  assert.equal(clientRoot.getAttribute("data-reconciliation"), "unrelated-livevue-patch");
  assert.equal(clientRoot.getAttribute("data-slot-open"), "true");
  assert.equal(clientRoot.getAttribute("data-slot-disabled"), "true");
  assert.equal(clientRoot.getAttribute("data-state"), "open");
  assert.equal(clientRoot.getAttribute("data-disabled"), "");
  assert.equal(clientTrigger.disabled, true);
  assert.equal(clientContent(), firstClientContent);
  assert.equal(firstClientInput.value, "operator draft");
  assertClientRelationship(firstClientContent);

  clientDisabled.value = false;
  seedEpoch.value = 2;
  await flushVue(nextTick);

  assert.equal(clientRoot.getAttribute("data-slot-open"), "false");
  assert.equal(clientRoot.getAttribute("data-state"), "closed");
  assert.equal(clientTrigger.getAttribute("aria-expanded"), "false");
  assert.equal(clientContent(), firstClientContent);
  assert.equal(firstClientContent.getAttribute("data-state"), "closed");
  assert.equal(firstClientContent.hasAttribute("hidden"), true);
  assert.equal(dom.window.document.querySelector("#client-seeded-input"), firstClientInput);
  assert.equal(firstClientInput.value, "operator draft");
  assertClientRelationship(firstClientContent);

  serverOpen.value = true;
  reconciliationLabel.value = "same-epoch-livevue-patch";
  await flushVue(nextTick);
  assert.equal(clientRoot.getAttribute("data-reconciliation"), "same-epoch-livevue-patch");
  assert.equal(clientRoot.getAttribute("data-slot-open"), "false");
  assert.equal(clientRoot.getAttribute("data-state"), "closed");
  assert.equal(clientContent(), firstClientContent);
  assert.equal(firstClientInput.value, "operator draft");

  seedEpoch.value = 3;
  await flushVue(nextTick);
  assert.equal(clientRoot.getAttribute("data-slot-open"), "true");
  assert.equal(clientRoot.getAttribute("data-state"), "open");
  assert.equal(clientTrigger.getAttribute("aria-expanded"), "true");
  assert.equal(clientContent(), firstClientContent);
  assert.equal(firstClientContent.hasAttribute("hidden"), false);
  assert.equal(firstClientInput.value, "operator draft");
  assertClientRelationship(firstClientContent);

  const controlledOpen = ref(false);
  const controlledRequestedStates: boolean[] = [];

  const ControlledOracle = defineComponent({
    name: "CadenceCollapsibleControlledReconciliationOracle",
    setup() {
      return () =>
        h(
          CadenceCollapsible,
          {
            open: controlledOpen.value,
            contentId: "controlled-content",
            onRequestChange: (nextOpen: boolean) => controlledRequestedStates.push(nextOpen),
          },
          {
            default: ({ open }: { open: boolean }) =>
              h(
                "section",
                {
                  id: "controlled-root",
                  "data-slot-open": String(open),
                },
                [
                  h(CadenceCollapsibleTrigger, null, {
                    default: () =>
                      h("button", { id: "controlled-trigger", type: "button" }, "Toggle"),
                  }),
                  h(CadenceCollapsibleContent, null, {
                    default: () =>
                      h("div", { id: "caller-controlled-content" }, [
                        h("input", { id: "controlled-input", value: "controlled" }),
                      ]),
                  }),
                ],
              ),
          },
        );
    },
  });

  const controlledApp = createApp(ControlledOracle);
  controlledApp.mount(required(dom.window.document.querySelector("#controlled-app")));
  await flushVue(nextTick);

  const controlledRoot = required(
    dom.window.document.querySelector<HTMLElement>("#controlled-root"),
  );
  const controlledTrigger = required(
    dom.window.document.querySelector<HTMLElement>("#controlled-trigger"),
  );
  assert.equal(controlledRoot.getAttribute("data-slot-open"), "false");
  assert.equal(controlledRoot.getAttribute("data-state"), "closed");
  assert.equal(controlledTrigger.getAttribute("aria-controls"), "controlled-content");
  assert.equal(controlledTrigger.getAttribute("aria-expanded"), "false");
  assert.equal(dom.window.document.querySelector("#controlled-content"), null);

  controlledTrigger.click();
  await flushVue(nextTick);
  assert.deepEqual(controlledRequestedStates, [true]);
  assert.equal(controlledRoot.getAttribute("data-slot-open"), "false");
  assert.equal(controlledRoot.getAttribute("data-state"), "closed");
  assert.equal(controlledTrigger.getAttribute("aria-expanded"), "false");
  assert.equal(dom.window.document.querySelector("#controlled-content"), null);

  controlledOpen.value = true;
  await flushVue(nextTick);
  const acknowledgedContent = required(
    dom.window.document.querySelector<HTMLElement>("#controlled-content"),
  );
  const acknowledgedInput = required(
    dom.window.document.querySelector<HTMLInputElement>("#controlled-input"),
  );
  assert.ok(acknowledgedContent);
  assert.ok(acknowledgedInput);
  assert.equal(controlledRoot.getAttribute("data-slot-open"), "true");
  assert.equal(controlledRoot.getAttribute("data-state"), "open");
  assert.equal(controlledTrigger.getAttribute("aria-expanded"), "true");
  assert.equal(controlledTrigger.getAttribute("aria-controls"), acknowledgedContent.id);

  controlledTrigger.click();
  await flushVue(nextTick);
  assert.deepEqual(controlledRequestedStates, [true, false]);
  assert.equal(controlledRoot.getAttribute("data-slot-open"), "true");
  assert.equal(controlledTrigger.getAttribute("aria-expanded"), "true");
  assert.equal(dom.window.document.querySelector("#controlled-content"), acknowledgedContent);

  controlledOpen.value = false;
  await flushVue(nextTick);
  assert.equal(controlledRoot.getAttribute("data-slot-open"), "false");
  assert.equal(controlledRoot.getAttribute("data-state"), "closed");
  assert.equal(controlledTrigger.getAttribute("aria-expanded"), "false");
  assert.equal(dom.window.document.querySelector("#controlled-content"), null);
  assert.equal(acknowledgedContent.isConnected, false);
  assert.equal(acknowledgedInput.isConnected, false);

  controlledApp.unmount();
  clientApp.unmount();

  console.log(
    `cadence_collapsible_livevue_reconciliation_test passed (${scenarios.length} scenarios; JSDOM state/reconciliation only, browser Enter/Space/focus remains a separate gate)`,
  );
});
