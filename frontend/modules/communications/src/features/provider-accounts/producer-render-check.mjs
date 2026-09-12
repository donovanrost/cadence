// Run from the Phoenix producer test with sandbox-generated DTOs, never live credentials.
import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "vite";
import vue from "@vitejs/plugin-vue";
import { Window } from "happy-dom";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";

const directory = dirname(fileURLToPath(import.meta.url));
const server = await createServer({
  configFile: false,
  root: resolve(directory, "../../.."),
  plugins: [vue()],
  server: { middlewareMode: true, hmr: false },
  ssr: { noExternal: ["@cadence/ui"] },
  logLevel: "error",
});
try {
  const components = await server.ssrLoadModule("/src/provider-accounts.ts");
  for (const sample of JSON.parse(process.argv[2])) {
    if (sample.component === "ProviderAccountListPage") {
      sample.props = components.readAccountDirectory(sample.props, sample.organization_id, 1);
    }
    if (sample.component === "ProviderAccountNew") {
      sample.props = components.readRegistration(sample.props, 1);
    }
    if (sample.component === "ProviderAccountShow") {
      const { account, ...view } = components.readAccountDetail(
        sample.props,
        sample.organization_id,
        1,
      );
      assert.equal(account.organization_id, sample.organization_id);
      sample.props = view;
    }
    const component = components[sample.component];
    assert.ok(component, "Unknown test component");
    const app = createSSRApp(component, sample.props);
    app.config.warnHandler = (message) => {
      throw new Error(message);
    };
    const html = await renderToString(app);
    const window = new Window();
    try {
      window.document.body.innerHTML = html;
      for (const id of sample.ids) {
        assert.ok(window.document.getElementById(id), sample.component + ": missing " + id);
      }
      if (sample.component === "ProviderAccountNew") {
        for (const key of sample.props.form.hidden_field_keys) {
          const field = sample.props.form.fields[key];
          const input = window.document.getElementById(field.id);
          assert.equal(input.name, field.name);
          assert.equal(input.value, field.value);
          assert.equal(input.type, "hidden");
        }
      }
      if (sample.component === "ProviderAccountListPage") {
        for (const card of sample.props.provider_accounts) {
          const link = window.document.getElementById(card.__dom_id).querySelector("a");
          assert.equal(link.getAttribute("href"), card.href);
          assert.ok(link.textContent.includes(card.display_name));
        }
      }
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Provider-account producer/renderer contract passed.");
} finally {
  await server.close();
}
