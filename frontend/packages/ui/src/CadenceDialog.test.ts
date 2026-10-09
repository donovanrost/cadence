import { flushPromises, mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CadenceDialog from "./CadenceDialog.vue";

test("renders a titled modal decision with caller-owned actions", async () => {
  const app = mount(CadenceDialog, {
    props: { open: true, title: "Discard changes?", description: "Unsaved edits will be lost." },
    slots: { actions: '<button type="button" id="discard">Discard</button>' },
    attachTo: document.body,
  });
  await flushPromises();
  const dialog = document.querySelector('[role="dialog"]');
  expect(dialog?.textContent).toContain("Discard changes?");
  expect(dialog?.textContent).toContain("Unsaved edits will be lost.");
  expect(document.getElementById("discard")).not.toBeNull();
  await app.setProps({ open: false });
  await flushPromises();
  expect(document.querySelector('[role="dialog"]')).toBeNull();
  // A closed dialog must not leave a page-blocking layer behind.
  expect(document.querySelector(".cadence-sheet-layer")).toBeNull();
  app.unmount();
});
