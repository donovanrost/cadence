import { fixtureRows, fixtureString } from "../../../../../test-support/json-fixture.ts";
import { required } from "../../../../../test-support/required.ts";
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
  // Vite loads the checked local entry module through an untyped SSR API.
  const components = /** @type {typeof import("../../provider-accounts.ts")} */ (
    await server.ssrLoadModule("/src/provider-accounts.ts")
  );
  for (const sample of fixtureRows(process.argv[2])) {
    const fixture = (() => {
      switch (sample.component) {
        case "ProviderAccountListPage":
          return {
            kind: /** @type {const} */ ("list"),
            // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
            component: components.ProviderAccountListPage,
            props: components.readAccountDirectory(
              sample.props,
              fixtureString(sample.organization_id),
              1,
            ),
          };
        case "ProviderAccountNew":
          return {
            kind: /** @type {const} */ ("new"),
            // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
            component: components.ProviderAccountNew,
            props: components.readRegistration(sample.props, 1),
          };
        case "ProviderAccountShow": {
          const { account, ...view } = components.readAccountDetail(
            sample.props,
            fixtureString(sample.organization_id),
            1,
          );
          assert.equal(account.organization_id, sample.organization_id);
          return {
            kind: /** @type {const} */ ("show"),
            // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
            component: components.ProviderAccountShow,
            props: view,
          };
        }
        default:
          throw Error("Unknown test component");
      }
    })();
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
    const app = createSSRApp(fixture.component, fixture.props);
    app.config.warnHandler = (message) => {
      throw new Error(message);
    };
    const html = await renderToString(app);
    const window = new Window();
    try {
      window.document.body.innerHTML = html;
      assert.ok(Array.isArray(sample.ids));
      for (const id of sample.ids.map(fixtureString)) {
        assert.ok(window.document.getElementById(id), String(sample.component) + ": missing " + id);
      }
      if (fixture.kind === "new") {
        for (const key of fixture.props.form.hidden_field_keys) {
          /** @type {import("./registration.contracts.ts").Field} */
          const field = fixture.props.form.fields[key];
          const input = window.document.getElementById(field.id);
          assert.ok(input instanceof window.HTMLInputElement);
          assert.equal(input.name, field.name);
          assert.equal(input.value, field.value);
          assert.equal(input.type, "hidden");
        }
      }
      if (fixture.kind === "list") {
        for (const card of fixture.props.provider_accounts) {
          const link = required(
            required(window.document.getElementById(card.__dom_id)).querySelector("a"),
          );
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
