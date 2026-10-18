import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import CadenceTechnicalDetails from "./CadenceTechnicalDetails.vue";

let wrapper: ReturnType<typeof mount>;
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

const value = "mission_model_revision:" + "0123456789abcdef".repeat(4);
function mountDetails() {
  wrapper = mount(CadenceTechnicalDetails, {
    props: {
      id: "diagnostics",
      context: "Kestrel",
      items: [
        { label: "Model revision ID", value },
        { label: "Import run ID", value: "import/one?exact=yes#original", href: "/imports/one" },
        { label: "Runtime identity", value: null },
      ],
    },
    attachTo: document.body,
  });
  return wrapper;
}

test("starts collapsed and retains full diagnostic values, links and labeled copy actions", async () => {
  const write = vi.spyOn(navigator.clipboard, "writeText").mockResolvedValue();
  const app = mountDetails();
  expect(app.get("details").attributes("open")).toBeUndefined();
  expect(app.get("summary").text()).toBe("Technical details for Kestrel");
  expect(app.get("a").attributes("href")).toBe("/imports/one");
  expect(app.findAll("button")).toHaveLength(2);
  expect(app.text()).toContain("Not available");
  await app.get("#diagnostics-copy-0").trigger("click");
  await flushPromises();
  expect(write).toHaveBeenCalledWith(value);
  expect(app.get("#diagnostics-copy-0").attributes("aria-label")).toBe(
    "Copy Model revision ID for Kestrel",
  );
  expect(app.findAll('[role="status"]')[0]?.text()).toBe("Copied to clipboard");
});

test("announces a failed copy and leaves the complete value available for manual selection", async () => {
  vi.spyOn(navigator.clipboard, "writeText").mockRejectedValue(new Error("denied"));
  const app = mountDetails();
  await app.get("#diagnostics-copy-0").trigger("click");
  await flushPromises();
  expect(app.get("#diagnostics-copy-0").attributes("data-clipboard-failed")).toBe("true");
  expect(app.findAll('[role="status"]')[0]?.text()).toBe("Copy failed");
  expect(app.text()).toContain(value);
});
