import { Fragment, createApp, defineComponent, h, nextTick, ref } from "vue";
import CadenceTableFrame from "../CadenceTableFrame.vue";
import { required, nativeElement, nativeInput } from "../../../../test-support/mounted-contract";
import assert from "node:assert/strict";
import { elementAttributes, installDom } from "../../../../test-support/mounted-contract";

import { test } from "vite-plus/test";

test("cadence table frame native behavior", async () => {
  const dom = installDom(
    '<div id="table-contract"></div><div id="native-contract"></div><div id="default-contract"></div>',
  );

  assert.equal(CadenceTableFrame.inheritAttrs, false);

  let callerHead: HTMLElement | null = null;
  let callerBody: HTMLElement | null = null;
  let callerHeaderRow: HTMLElement | null = null;
  let callerDataRow: HTMLElement | null = null;
  let callerNameCell: HTMLElement | null = null;
  let callerActionsCell: HTMLElement | null = null;
  let callerFilter: HTMLInputElement | null = null;
  let callerAction: HTMLElement | null = null;
  let callerLink: HTMLElement | null = null;
  let filterModel: import("vue").Ref<string> | null = null;
  let actionClicks = 0;
  let bubbledClicks = 0;

  const callerTableChildren = () => [
    h(Fragment, null, [
      [
        h(
          "thead",
          {
            ref: (element: unknown) => {
              callerHead = nativeElement(element);
            },
            id: "missions-table-head",
          },
          [
            h(
              "tr",
              {
                ref: (element: unknown) => {
                  callerHeaderRow = nativeElement(element);
                },
                id: "missions-header-row",
              },
              [
                h("th", { id: "missions-name-heading", scope: "col" }, "Mission"),
                h("th", { id: "missions-actions-heading", scope: "col" }, "Actions"),
              ],
            ),
          ],
        ),
      ],
      h(Fragment, null, [
        [
          h(
            "tbody",
            {
              ref: (element: unknown) => {
                callerBody = nativeElement(element);
              },
              id: "missions-table-body",
            },
            [
              h(
                "tr",
                {
                  ref: (element: unknown) => {
                    callerDataRow = nativeElement(element);
                  },
                  id: "mission-row-7",
                },
                [
                  h(
                    "td",
                    {
                      ref: (element: unknown) => {
                        callerNameCell = nativeElement(element);
                      },
                      id: "mission-name-7",
                    },
                    [
                      h("input", {
                        ref: (element: unknown) => {
                          callerFilter = nativeInput(element);
                        },
                        id: "mission-filter-7",
                        name: "mission[filter]",
                        type: "text",
                        value: required<import("vue").Ref<string>>(filterModel).value,
                        onInput: (event: Event) => {
                          required<import("vue").Ref<string>>(filterModel).value = required(
                            nativeInput(event.currentTarget),
                          ).value;
                        },
                      }),
                    ],
                  ),
                  h(
                    "td",
                    {
                      ref: (element: unknown) => {
                        callerActionsCell = nativeElement(element);
                      },
                      id: "mission-actions-7",
                    },
                    [
                      h(
                        "button",
                        {
                          ref: (element: unknown) => {
                            callerAction = nativeElement(element);
                          },
                          id: "mission-select-7",
                          type: "button",
                          onClick: () => {
                            actionClicks += 1;
                          },
                        },
                        "Select & verify",
                      ),
                      h(
                        "a",
                        {
                          ref: (element: unknown) => {
                            callerLink = nativeElement(element);
                          },
                          id: "mission-link-7",
                          href: "/missions/7?from=table&mode=ops",
                          "data-phx-link": "redirect",
                          "data-phx-link-state": "push",
                        },
                        "Open <mission>",
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ]),
    ]),
  ];

  const TableContract = defineComponent({
    name: "CadenceTableFrameContract",
    setup() {
      filterModel = ref("alpha");

      return () =>
        h(
          CadenceTableFrame,
          {
            id: "missions-table",
            class: ["caller-grid", { "table-striped": true }],
            "aria-label": "Missions <table> & controls",
            "data-table-owner": "caller",
            onClick: () => {
              bubbledClicks += 1;
            },
          },
          { default: callerTableChildren },
        );
    },
  });

  const nativeTableChildren = () => [
    h("thead", { id: "missions-table-head" }, [
      h("tr", { id: "missions-header-row" }, [
        h("th", { id: "missions-name-heading", scope: "col" }, "Mission"),
        h("th", { id: "missions-actions-heading", scope: "col" }, "Actions"),
      ]),
    ]),
    h("tbody", { id: "missions-table-body" }, [
      h("tr", { id: "mission-row-7" }, [
        h("td", { id: "mission-name-7" }, [
          h("input", {
            id: "mission-filter-7",
            name: "mission[filter]",
            type: "text",
            value: "alpha",
          }),
        ]),
        h("td", { id: "mission-actions-7" }, [
          h("button", { id: "mission-select-7", type: "button" }, "Select & verify"),
          h(
            "a",
            {
              id: "mission-link-7",
              href: "/missions/7?from=table&mode=ops",
              "data-phx-link": "redirect",
              "data-phx-link-state": "push",
            },
            "Open <mission>",
          ),
        ]),
      ]),
    ]),
  ];

  const NativeTableContract = defineComponent({
    name: "NativeTableContract",
    setup() {
      return () =>
        h(
          "table",
          {
            id: "missions-table",
            class: "table caller-grid table-striped",
            "aria-label": "Missions <table> & controls",
            "data-table-owner": "caller",
          },
          nativeTableChildren(),
        );
    },
  });

  const tableHost = required(dom.window.document.querySelector<HTMLElement>("#table-contract"));
  const nativeHost = required(dom.window.document.querySelector<HTMLElement>("#native-contract"));
  const tableApp = createApp(TableContract);
  const nativeApp = createApp(NativeTableContract);
  tableApp.mount(tableHost);
  nativeApp.mount(nativeHost);

  const table = required(tableHost.firstElementChild);
  const nativeTable = required(nativeHost.firstElementChild);
  assert.equal(tableHost.children.length, 1, "the frame adds no wrapper");
  assert.equal(table.tagName, "TABLE");
  assert.deepEqual(elementAttributes(table), {
    "aria-label": "Missions <table> & controls",
    class: "table caller-grid table-striped",
    "data-table-owner": "caller",
    id: "missions-table",
  });
  assert.deepEqual(
    [...table.childNodes].map((node) => node.nodeName),
    ["THEAD", "TBODY"],
  );
  assert.deepEqual(
    [...required<HTMLElement>(callerHead).childNodes].map((node) => node.nodeName),
    ["TR"],
  );
  assert.deepEqual(
    [...required<HTMLElement>(callerHeaderRow).childNodes].map((node) => node.nodeName),
    ["TH", "TH"],
  );
  assert.deepEqual(
    [...required<HTMLElement>(callerBody).childNodes].map((node) => node.nodeName),
    ["TR"],
  );
  assert.deepEqual(
    [...required<HTMLElement>(callerDataRow).childNodes].map((node) => node.nodeName),
    ["TD", "TD"],
  );
  assert.strictEqual(table.children[0], callerHead);
  assert.strictEqual(table.children[1], callerBody);
  assert.strictEqual(required<HTMLElement>(callerHead).children[0], callerHeaderRow);
  assert.strictEqual(required<HTMLElement>(callerBody).children[0], callerDataRow);
  assert.strictEqual(required<HTMLElement>(callerDataRow).children[0], callerNameCell);
  assert.strictEqual(required<HTMLElement>(callerDataRow).children[1], callerActionsCell);
  assert.strictEqual(required<HTMLElement>(callerNameCell).children[0], callerFilter);
  assert.strictEqual(required<HTMLElement>(callerActionsCell).children[0], callerAction);
  assert.strictEqual(required<HTMLElement>(callerActionsCell).children[1], callerLink);
  assert.deepEqual(elementAttributes(required<HTMLElement>(callerLink)), {
    "data-phx-link": "redirect",
    "data-phx-link-state": "push",
    href: "/missions/7?from=table&mode=ops",
    id: "mission-link-7",
  });
  assert.equal(
    table.outerHTML,
    nativeTable.outerHTML,
    "the frame is byte-identical to an equivalent native table",
  );

  required<HTMLElement>(callerAction).click();
  assert.equal(actionClicks, 1, "the caller-owned native button keeps its event handler");
  assert.equal(bubbledClicks, 1, "the forwarded table listener keeps native bubbling behavior");

  required<HTMLInputElement>(callerFilter).value = "beta";
  required<HTMLInputElement>(callerFilter).dispatchEvent(
    new dom.window.Event("input", { bubbles: true }),
  );
  await nextTick();
  assert.equal(
    required<import("vue").Ref<string>>(filterModel).value,
    "beta",
    "the caller-owned input updates its Vue model",
  );
  required<import("vue").Ref<string>>(filterModel).value = "gamma";
  await nextTick();
  assert.equal(
    required<HTMLInputElement>(callerFilter).value,
    "gamma",
    "the Vue model updates the same native input",
  );

  const DefaultClassContract = defineComponent({
    name: "CadenceTableFrameDefaultClassContract",
    setup() {
      return () => h(CadenceTableFrame, { id: "default-table" }, { default: () => [h("tbody")] });
    },
  });
  const defaultHost = required(dom.window.document.querySelector<HTMLElement>("#default-contract"));
  const defaultApp = createApp(DefaultClassContract);
  defaultApp.mount(defaultHost);
  assert.equal(
    required(defaultHost.firstElementChild).outerHTML,
    '<table id="default-table" class="table"><tbody></tbody></table>',
  );

  tableApp.unmount();
  nativeApp.unmount();
  defaultApp.unmount();
  assert.equal(tableHost.children.length, 0);
  assert.equal(nativeHost.children.length, 0);
  assert.equal(defaultHost.children.length, 0);

  console.log("cadence_table_frame_test passed (compiled SFC + exact native table contract)");
});
