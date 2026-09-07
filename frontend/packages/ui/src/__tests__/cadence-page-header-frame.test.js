import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  loadSfc,
  integrationRequire,
} from "../../../../test-support/mounted-contract.js";

import { test } from "vite-plus/test";

test("cadence page header frame native behavior", async () => {
  const testDirectory = dirname(fileURLToPath(import.meta.url));
  const componentPath = resolve(testDirectory, "../CadencePageHeaderFrame.vue");
  const source = await readFile(componentPath, "utf8");
  const dom = installDom('<div id="compact-contract"></div><div id="ops-contract"></div>');
  const CadencePageHeaderFrame = (await loadSfc(componentPath)).component;
  const { Fragment, createApp, defineComponent, h } = integrationRequire("vue");

  assert.equal(CadencePageHeaderFrame.inheritAttrs, false);
  assert.equal(CadencePageHeaderFrame.props.variant.required, true);
  assert.equal(CadencePageHeaderFrame.props.variant.validator("compact"), true);
  assert.equal(CadencePageHeaderFrame.props.variant.validator("ops"), true);
  assert.equal(CadencePageHeaderFrame.props.variant.validator("other"), false);

  let compactLead = null;
  let compactNav = null;
  let compactLink = null;
  let compactAction = null;
  let forwardedClicks = 0;
  const CompactContract = defineComponent({
    name: "CadencePageHeaderFrameCompactContract",
    setup() {
      return () =>
        h(
          CadencePageHeaderFrame,
          {
            variant: "compact",
            id: "compact-page-header",
            class: "caller-class-must-not-alter-variant",
            "aria-label": "Compact <header> & frame",
            "data-header-owner": "caller",
            onClick: () => {
              forwardedClicks += 1;
            },
          },
          {
            default: () => [
              h("div", {
                ref: (element) => {
                  compactLead = element;
                },
                id: "compact-lead",
              }),
              h(Fragment, null, [
                [
                  h("nav", {
                    ref: (element) => {
                      compactNav = element;
                    },
                    id: "compact-navigation",
                  }),
                  h(Fragment, null, [
                    h(
                      "a",
                      {
                        ref: (element) => {
                          compactLink = element;
                        },
                        id: "compact-link",
                        href: "/admin?from=header&mode=compact",
                        "data-phx-link": "redirect",
                        "data-phx-link-state": "push",
                      },
                      "Admin <home>",
                    ),
                    [
                      h(
                        "button",
                        {
                          ref: (element) => {
                            compactAction = element;
                          },
                          id: "compact-action",
                          type: "button",
                        },
                        "Run & verify",
                      ),
                    ],
                  ]),
                ],
              ]),
            ],
          },
        );
    },
  });

  const compactHost = dom.window.document.querySelector("#compact-contract");
  const compactApp = createApp(CompactContract);
  compactApp.mount(compactHost);

  const compactHeader = compactHost.firstElementChild;
  assert.equal(compactHost.children.length, 1);
  assert.equal(compactHeader.tagName, "HEADER");
  assert.deepEqual(elementAttributes(compactHeader), {
    "aria-label": "Compact <header> & frame",
    class: "border-b border-primary/20 pb-4",
    "data-header-owner": "caller",
    id: "compact-page-header",
  });
  assert.deepEqual(
    [...compactHeader.childNodes].map((node) => node.nodeName),
    ["DIV", "NAV", "A", "BUTTON"],
  );
  assert.strictEqual(compactHeader.children[0], compactLead);
  assert.strictEqual(compactHeader.children[1], compactNav);
  assert.strictEqual(compactHeader.children[2], compactLink);
  assert.strictEqual(compactHeader.children[3], compactAction);
  assert.deepEqual(elementAttributes(compactLink), {
    "data-phx-link": "redirect",
    "data-phx-link-state": "push",
    href: "/admin?from=header&mode=compact",
    id: "compact-link",
  });
  compactAction.click();
  assert.equal(forwardedClicks, 1, "forwarded native listeners retain bubbling behavior");

  let opsSummary = null;
  const OpsContract = defineComponent({
    name: "CadencePageHeaderFrameOpsContract",
    setup() {
      return () =>
        h(
          CadencePageHeaderFrame,
          { variant: "ops", id: "ops-page-header", "data-mode": "operations" },
          {
            default: () => [
              h("div", { id: "ops-copy" }),
              h(Fragment, null, [
                h("div", {
                  ref: (element) => {
                    opsSummary = element;
                  },
                  id: "ops-summary",
                }),
              ]),
            ],
          },
        );
    },
  });

  const opsHost = dom.window.document.querySelector("#ops-contract");
  const opsApp = createApp(OpsContract);
  opsApp.mount(opsHost);

  const opsHeader = opsHost.firstElementChild;
  assert.equal(opsHost.children.length, 1);
  assert.equal(opsHeader.tagName, "HEADER");
  assert.deepEqual(elementAttributes(opsHeader), {
    class: "border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7",
    "data-mode": "operations",
    id: "ops-page-header",
  });
  assert.deepEqual(
    [...opsHeader.childNodes].map((node) => node.nodeName),
    ["DIV", "DIV"],
  );
  assert.strictEqual(opsHeader.children[1], opsSummary);

  compactApp.unmount();
  opsApp.unmount();
  assert.equal(compactHost.children.length, 0);
  assert.equal(opsHost.children.length, 0);

  console.log("cadence_page_header_frame_test passed (compact + ops exact-DOM contracts)");
});
