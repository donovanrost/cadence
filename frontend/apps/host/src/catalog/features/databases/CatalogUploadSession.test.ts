import { mount } from "@vue/test-utils";
import { h, nextTick } from "vue";
import { afterEach, expect, test, vi } from "vite-plus/test";
import CatalogUploadSession from "./CatalogUploadSession.vue";
import CatalogUploadForm from "./CatalogUploadForm.vue";
import { databaseUploadFixture } from "./fixtures.test-support";
import { nativeUpload } from "./native-upload";

const session = () => ({
  path: "/missions/mission-a/catalog/new",
  token: "session-one",
  attempt: 0,
  error: null as string | null,
});
const cleanup: Array<() => void> = [];
afterEach(() => {
  cleanup
    .splice(0)
    .reverse()
    .forEach((dispose) => dispose());
  document.body.replaceChildren();
});

function setup(withEntry = false) {
  const active = session();
  const form = document.createElement("form");
  form.id = "catalog-native-upload-form";
  form.dataset.catalogPath = active.path;
  form.dataset.catalogToken = active.token;
  for (const key of ["path", "token", "name", "revision_label", "revision_notes"]) {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = `catalog_upload[${key}]`;
    form.append(input);
  }
  const file = document.createElement("input");
  file.id = "phx-upload-one";
  file.name = "catalog_artifact";
  file.dataset.phxUploadRef = file.id;
  file.type = "file";
  form.append(file);
  document.body.append(form);
  const submit = vi.fn((event: Event) => event.preventDefault());
  const change = vi.fn();
  form.addEventListener("submit", submit);
  form.addEventListener("change", change);
  const data: InstanceType<typeof CatalogUploadForm>["$props"] = databaseUploadFixture();
  if (withEntry) {
    data.upload.entries.push({
      ref: "entry-one",
      client_name: "mission.yaml",
      client_size: 11,
      client_type: "application/yaml",
      progress: 50,
      done: false,
      valid: true,
      preflighted: true,
      errors: [],
    });
  }
  const cancel = vi.fn();
  const navigate = vi.fn();
  const wrapper = mount(CatalogUploadSession, {
    attachTo: document.body,
    props: { session: active, cancel, navigate },
    slots: { default: () => h(CatalogUploadForm, { ...data, submit_disabled: false }) },
  });
  cleanup.push(() => wrapper.unmount());
  return { wrapper, active, form, file, submit, change, cancel, navigate };
}

test("field and file changes delegate to the existing Phoenix-owned nodes", async () => {
  const { wrapper, form, file, change, active } = setup();
  const originalNodes = [...form.children];
  await wrapper.get("#catalog_database_name").setValue("Flight");
  expect(new FormData(form).get("catalog_upload[name]")).toBe("Flight");
  expect(new FormData(form).get("catalog_upload[token]")).toBe(active.token);
  expect(change).toHaveBeenCalledOnce();

  const bytes = new File(["packets: []"], "mission.yaml", { type: "application/yaml" });
  const transfer = new DataTransfer();
  transfer.items.add(bytes);
  const visible = wrapper.get<HTMLInputElement>("#catalog-upload-file-input");
  visible.element.files = transfer.files;
  await visible.trigger("change");
  expect(file.files?.[0]).toBe(bytes);
  expect(change).toHaveBeenCalledTimes(2);
  expect([...form.children]).toEqual(originalNodes);
  expect(document.getElementById("phx-upload-one")).toBe(file);
  expect(wrapper.find("progress").exists()).toBe(false); // Entries come from Phoenix, not local guesses.
});

test("submit dispatches once while pending and server failure restores an editable form", async () => {
  const { wrapper, form, submit, active } = setup();
  await wrapper.get("#catalog_database_name").setValue("Flight");
  await wrapper.get("#catalog-upload-form").trigger("submit");
  await wrapper.get("#catalog-upload-form").trigger("submit");
  expect(submit).toHaveBeenCalledOnce();
  expect(new FormData(form).get("catalog_upload[name]")).toBe("Flight");
  expect(wrapper.find("#catalog-upload-pending").exists()).toBe(true);
  expect(wrapper.get("#catalog-upload-submit").attributes("disabled")).toBeDefined();
  await wrapper.setProps({ session: { ...active, attempt: 1, error: "Check the file." } });
  expect(wrapper.find("#catalog-upload-pending").exists()).toBe(false);
  expect(wrapper.get("#catalog-upload-error").text()).toBe("Check the file.");
  expect(wrapper.get<HTMLInputElement>("#catalog_database_name").element.value).toBe("Flight");
  await wrapper.get("#catalog-upload-form").trigger("submit");
  expect(submit).toHaveBeenCalledTimes(2);
});

test("stale native sessions cannot change fields or submit", async () => {
  const { wrapper, form, submit, active } = setup();
  form.dataset.catalogToken = "replacement";
  expect(() => nativeUpload(active, { name: "Forged" })).toThrow();
  await wrapper.get("#catalog-upload-form").trigger("submit");
  expect(submit).not.toHaveBeenCalled();
  expect(new FormData(form).get("catalog_upload[name]")).toBe("");
  expect(wrapper.find("#catalog-upload-error").exists()).toBe(true);
});

test("only a completion for this session and mission can navigate", async () => {
  const { wrapper, active, navigate } = setup();
  const href = "/missions/mission-a/catalog/imports/run-one";
  const dispatch = (detail: object) =>
    window.dispatchEvent(new CustomEvent("phx:catalog:uploaded", { detail }));
  dispatch({ ...active, href, token: "old-session" });
  dispatch({ ...active, href, path: "/missions/mission-b/catalog/new" });
  dispatch({ ...active, href: "/missions/mission-b/catalog/imports/run-one" });
  expect(navigate).not.toHaveBeenCalled();
  dispatch({ ...active, href });
  expect(navigate).toHaveBeenCalledExactlyOnceWith(href);
  wrapper.unmount();
  cleanup.pop();
  dispatch({ ...active, href });
  expect(navigate).toHaveBeenCalledOnce();
});

test("a connection interruption clears pending state and warns before retry", async () => {
  const { wrapper } = setup();
  await wrapper.get("#catalog-upload-form").trigger("submit");
  window.dispatchEvent(new Event("offline"));
  await nextTick();
  expect(wrapper.find("#catalog-upload-pending").exists()).toBe(false);
  expect(wrapper.get("#catalog-upload-error").text()).toContain("Check the import history");
});

test("removal delegates the Phoenix entry ref with the active path and token", async () => {
  const { wrapper, cancel, active } = setup(true);
  expect(wrapper.get("progress").attributes("value")).toBe("50");
  await wrapper.get("#catalog-upload-form li button").trigger("click");
  expect(cancel).toHaveBeenCalledExactlyOnceWith({
    catalog_upload: { path: active.path, token: active.token },
    ref: "entry-one",
  });
  expect(wrapper.get<HTMLInputElement>("#catalog-upload-file-input").element.value).toBe("");
});

test("a stale or ambiguous Phoenix upload reference cannot receive the selected file", () => {
  const { active, file, form } = setup();
  file.dataset.phxUploadRef = "replacement-ref";
  expect(() => nativeUpload(active, {})).toThrow("Upload controls are unavailable.");
  file.dataset.phxUploadRef = file.id;
  form.append(file.cloneNode());
  expect(() => nativeUpload(active, {})).toThrow("Upload controls are unavailable.");
});
