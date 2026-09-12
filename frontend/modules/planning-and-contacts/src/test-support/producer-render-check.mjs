import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";
import { Window } from "happy-dom";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";
/** @param {unknown} value @returns {value is Record<string, unknown>} */
const record = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
/** @param {unknown} value @returns {string[]} */
function ids(value) {
  if (value === undefined) return [];
  assert.ok(Array.isArray(value));
  return value.map((value) => {
    assert.equal(typeof value, "string");
    return String(value);
  });
}
const input = process.argv[2];
assert.ok(input, "Missing producer fixtures");
/** @type {unknown} */
const fixtures = JSON.parse(input);
assert.ok(Array.isArray(fixtures));
const server = await createServer({
  configFile: false,
  root: resolve(dirname(fileURLToPath(import.meta.url)), "../.."),
  plugins: [vue()],
  server: { middlewareMode: true, hmr: false },
  logLevel: "error",
});
try {
  // Vite loads this workspace's compiled SFC exports at runtime.
  /** @type {Record<string, import("vue").Component>} */
  const components = await server.ssrLoadModule("/src/index.ts");
  const failures = [];
  for (const fixture of fixtures) {
    assert.ok(record(fixture));
    const { component, props, expected = {} } = fixture;
    assert.equal(typeof component, "string");
    assert.ok(typeof component === "string" && record(props) && record(expected));
    assert.ok(Object.hasOwn(components, component), "Unknown test component");
    const entry = components[component];
    assert.ok(entry);
    const app = createSSRApp(entry, props);
    /** @type {string[]} */
    const warnings = [];
    app.config.warnHandler = (message) => {
      warnings.push(message);
    };
    const window = new Window();
    try {
      window.document.body.innerHTML = await renderToString(app);
      const doc = window.document;
      assert.deepEqual(warnings, []);
      for (const id of ids(expected.presentIds)) {
        assert.ok(doc.getElementById(id), "Expected rendered element " + id);
      }
      for (const id of ids(expected.absentIds)) {
        assert.equal(doc.getElementById(id), null, "Unexpected rendered element " + id);
      }
      for (const [id, value] of Object.entries(
        record(expected.fieldValues) ? expected.fieldValues : {},
      )) {
        const input = doc.getElementById(id);
        assert.ok(
          input instanceof window.HTMLInputElement ||
            input instanceof window.HTMLSelectElement ||
            input instanceof window.HTMLTextAreaElement,
          "Expected native field " + id,
        );
        assert.equal(
          input instanceof window.HTMLInputElement && input.type === "checkbox"
            ? input.checked
            : input.value,
          value,
        );
      }
      assert.ok(doc.querySelector("h1,h2"));
      const rootId =
        (record(props.page) ? props.page.id : undefined) ??
        (record(props.header) ? props.header.id : undefined) ??
        (record(props.record) ? props.record.id : undefined);
      if (rootId) {
        assert.ok(typeof rootId === "string");
        assert.ok(doc.getElementById(rootId), "Preserved page identity");
      }
      const fields = record(props.search) && record(props.search.fields) ? props.search.fields : {};
      for (const field of Object.values(fields)) {
        assert.ok(record(field) && typeof field.id === "string");
        const control = doc.getElementById(field.id);
        assert.ok(control, "Preserved search input " + field.id);
        assert.equal(control.getAttribute("name"), field.name);
      }
      console.log(component + " producer props rendered through domain entry");
    } catch (error) {
      failures.push({ component, message: error instanceof Error ? error.message : String(error) });
    } finally {
      await window.happyDOM.close();
    }
  }
  assert.deepEqual(failures, [], "Every existing planning producer must render");
  console.log("Planning ownership producer/consumer render checks passed");
} finally {
  await server.close();
}
