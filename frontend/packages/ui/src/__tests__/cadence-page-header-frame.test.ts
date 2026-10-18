import { Fragment, createApp, defineComponent, h } from "vue";
import CadencePageHeaderFrame from "../CadencePageHeaderFrame.vue";
import { required, nativeElement } from "../../../../test-support/mounted-contract";
import assert from "node:assert/strict";
import { elementAttributes, installDom } from "../../../../test-support/mounted-contract";

import { test } from "vite-plus/test";

test("cadence page header frame native behavior", async () => {
  const dom = installDom('<div id="compact-contract"></div><div id="ops-contract"></div>');

  assert.equal(CadencePageHeaderFrame.inheritAttrs, false);
  type VariantProp = { required: true; validator(value: string): boolean };
  // oxlint-disable-next-line typescript/no-unsafe-assignment, typescript/no-unsafe-member-access -- vue-tsc checks this SFC's runtime prop definition; typed lint cannot resolve its constructor props.
  const variant: VariantProp = CadencePageHeaderFrame.props.variant;
  assert.equal(variant.required, true);
  assert.equal(variant.validator("compact"), true);
  assert.equal(variant.validator("ops"), true);
  assert.equal(variant.validator("other"), false);

  let compactLead: HTMLElement | null = null;
  let compactNav: HTMLElement | null = null;
  let compactLink: HTMLElement | null = null;
  let compactAction: HTMLElement | null = null;
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
                ref: (element: unknown) => {
                  compactLead = nativeElement(element);
                },
                id: "compact-lead",
              }),
              h(Fragment, null, [
                [
                  h("nav", {
                    ref: (element: unknown) => {
                      compactNav = nativeElement(element);
                    },
                    id: "compact-navigation",
                  }),
                  h(Fragment, null, [
                    h(
                      "a",
                      {
                        ref: (element: unknown) => {
                          compactLink = nativeElement(element);
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
                          ref: (element: unknown) => {
                            compactAction = nativeElement(element);
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

  const compactHost = required(dom.window.document.querySelector<HTMLElement>("#compact-contract"));
  const compactApp = createApp(CompactContract);
  compactApp.mount(compactHost);

  const compactHeader = required(compactHost.firstElementChild);
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
  assert.deepEqual(elementAttributes(required<HTMLElement>(compactLink)), {
    "data-phx-link": "redirect",
    "data-phx-link-state": "push",
    href: "/admin?from=header&mode=compact",
    id: "compact-link",
  });
  required<HTMLElement>(compactAction).click();
  assert.equal(forwardedClicks, 1, "forwarded native listeners retain bubbling behavior");

  let opsSummary: HTMLElement | null = null;
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
                  ref: (element: unknown) => {
                    opsSummary = nativeElement(element);
                  },
                  id: "ops-summary",
                }),
              ]),
            ],
          },
        );
    },
  });

  const opsHost = required(dom.window.document.querySelector<HTMLElement>("#ops-contract"));
  const opsApp = createApp(OpsContract);
  opsApp.mount(opsHost);

  const opsHeader = required(opsHost.firstElementChild);
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
