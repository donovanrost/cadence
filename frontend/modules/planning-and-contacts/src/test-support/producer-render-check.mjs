import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";
import { Window } from "happy-dom";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";
const server = await createServer({
  configFile: false,
  root: resolve(dirname(fileURLToPath(import.meta.url)), "../.."),
  plugins: [vue()],
  server: { middlewareMode: true, hmr: false },
  logLevel: "error",
});
try {
  const components = await server.ssrLoadModule("/src/index.ts");
  const failures = [];
  for (const { component, props, expected = {} } of JSON.parse(process.argv[2])) {
    assert.ok(Object.hasOwn(components, component), "Unknown test component");
    const app = createSSRApp(components[component], props);
    const warnings = [];
    app.config.warnHandler = (message) => {
      warnings.push(message);
    };
    const window = new Window();
    try {
      window.document.body.innerHTML = await renderToString(app);
      const doc = window.document;
      assert.deepEqual(warnings, []);
      for (const id of expected.presentIds ?? []) {
        assert.ok(doc.getElementById(id), "Expected rendered element " + id);
      }
      for (const id of expected.absentIds ?? []) {
        assert.equal(doc.getElementById(id), null, "Unexpected rendered element " + id);
      }
      for (const [id, value] of Object.entries(expected.fieldValues ?? {})) {
        const input = doc.getElementById(id);
        assert.ok(input, "Expected native field " + id);
        assert.equal(input.type === "checkbox" ? input.checked : input.value, value);
      }
      assert.ok(doc.querySelector("h1,h2"));
      const rootId = props.page?.id ?? props.header?.id ?? props.record?.id;
      if (rootId) assert.ok(doc.getElementById(rootId), "Preserved page identity");
      for (const field of Object.values(props.search?.fields ?? {})) {
        assert.ok(doc.getElementById(field.id), "Preserved search input " + field.id);
        assert.equal(doc.getElementById(field.id).getAttribute("name"), field.name);
      }
      console.log(component + " producer props rendered through domain entry");
    } catch (error) {
      failures.push({ component, message: error.message });
    } finally {
      await window.happyDOM.close();
    }
  }
  assert.deepEqual(failures, [], "Every existing planning producer must render");
  console.log("Planning ownership producer/consumer render checks passed");
} finally {
  await server.close();
}
