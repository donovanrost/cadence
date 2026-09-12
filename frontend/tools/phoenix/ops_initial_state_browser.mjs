import { fixtureRecord, fixtureString } from "../../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { chromium } from "playwright";
import { readFile, writeFile } from "node:fs/promises";
import { createInterface } from "node:readline";
const [base, mission, user, out] = process.argv.slice(2);
assert.ok(base && mission && user && out, "Expected endpoint, mission, user and output directory");
const manifest = fixtureRecord(
  JSON.parse(
    await readFile(
      new URL("../../../apps/cadence_web/priv/static/cache_manifest.json", import.meta.url),
      "utf8",
    ),
  ),
);
const digestedEntry = fixtureString(fixtureRecord(manifest.latest)["assets/app.js"]);
assert.match(digestedEntry, /^assets\/app-[a-f0-9]{32}\.js$/);
const reader = createInterface({ input: process.stdin });
/** @type {unknown} */
const secret = await new Promise((resolve) =>
  reader.once("line", (line) => {
    reader.close();
    resolve(JSON.parse(line));
  }),
);
process.stdin.destroy();
const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 1366, height: 900 } });
/** @type {string[]} */
const errors = [];
const results = [];
page.setDefaultTimeout(12000);
page.on("pageerror", (e) => errors.push(e.message));
page.on("response", (response) => {
  if (
    response.status() >= 400 &&
    ["script", "stylesheet"].includes(response.request().resourceType())
  )
    errors.push(`Asset failed (${response.status()}): ${new URL(response.url()).pathname}`);
});
const prefix = base + "/missions/" + mission;
const routes = [
  "/ops",
  "/ops/dashboards",
  "/ops/dashboards/new",
  "/ops/dashboards/library",
  "/ops/dashboards/playlists",
  "/ops/dashboards/draft-dashboard",
  "/ops/dashboards/draft-dashboard/edit",
  "/ops/dashboards/draft-dashboard/settings",
  "/ops/dashboards/draft-dashboard/activity",
  "/ops/dashboards/draft-dashboard/diagnostics",
  "/ops/commands",
  "/ops/commands/new",
  "/ops/commands/stages",
  "/ops/commands/stages/new",
  "/ops/explore",
  "/ops/alarms",
  "/ops/timeline",
  "/ops/planning",
  "/ops/planning/new",
  "/ops/planning/policy",
  "/ops/requirements",
  "/ops/requirements/new",
  "/ops/requirement-templates",
  "/ops/contacts",
  "/ops/data-sources",
  "/ops/data-sources/registration/new",
  "/ops/data-operations",
  "/ops/data-operations/manage",
  "/ops/activations",
];
try {
  await page.goto(prefix + "/ops");
  await page.waitForURL(base + "/sign-in");
  await page.locator("#user_email").fill(user);
  await page.locator("#user_password").fill(fixtureString(fixtureRecord(secret).password));
  await page.locator("#sign-in-form").evaluate((f) => {
    if (!(f instanceof HTMLFormElement)) throw Error("Expected sign-in form");
    f.requestSubmit();
  });
  await page.waitForURL((url) => url.pathname !== "/sign-in");
  await page.waitForFunction(() => document.querySelector("[data-phx-main].phx-connected"));
  // Loading the Phoenix-digested entry must reuse the same hashed runtime and connection.
  const connection = await page.evaluateHandle(() =>
    "liveSocket" in window ? window.liveSocket : undefined,
  );
  try {
    await page.addScriptTag({ type: "module", url: base + "/" + digestedEntry });
    assert.equal(
      await page.evaluate(
        (previous) => "liveSocket" in window && window.liveSocket === previous,
        connection,
      ),
      true,
      "The digested entry must not initialize LiveView a second time",
    );
  } finally {
    await connection.dispose();
  }
  if (errors.length) throw Error(`Sign-in and digested startup errors: ${errors.join("; ")}`);
  for (const route of routes) {
    const start = errors.length;
    let failure = null;
    try {
      await page.goto(prefix + route);
      await page.waitForFunction(() => document.querySelector("[data-phx-main].phx-connected"));
      await page.locator("main h1").first().waitFor();
      await page.locator("#host-page-content > *").first().waitFor();
      await page.waitForFunction(
        () => !document.querySelector("[data-host-page-loading], #ops-module-loading"),
      );
    } catch (e) {
      failure = String(e);
    }
    const text = await page.locator("body").innerText();
    const generic =
      (await page.locator("#ops-module-unavailable, [data-host-page-load-failed]").count()) > 0;
    const item = {
      route,
      url: page.url(),
      generic,
      failure,
      errors: errors.slice(start),
      headings: await page.locator("h1,h2").allTextContents(),
      text: text.slice(0, 4500),
    };
    results.push(item);
    await writeFile(out + "/results.json", JSON.stringify(results, null, 2));
    if (generic || failure)
      await page.screenshot({ path: out + "/" + String(results.length) + ".png" });
    assert.equal(generic, false, route + " must have useful content or setup guidance");
    assert.equal(failure, null, route + " must render");
    assert.deepEqual(item.errors, [], route + " must not crash");
    if (route === "/ops/dashboards") {
      assert.equal(
        await page.locator("#open-draft-dashboard").getAttribute("href"),
        "/missions/" + mission + "/ops/dashboards/draft-dashboard/edit",
      );
    }
    if (
      route === "/ops/dashboards/draft-dashboard" ||
      route.endsWith("/draft-dashboard/diagnostics")
    ) {
      assert.equal(await page.locator("#dashboard-publication-required").count(), 1);
      assert.equal(
        await page.locator("#dashboard-publication-editor").getAttribute("href"),
        "/missions/" + mission + "/ops/dashboards/draft-dashboard/edit",
      );
      await page.locator("#dashboard-publication-refresh").click();
      await page.waitForFunction(() => {
        const button = document.querySelector("#dashboard-publication-refresh");
        return button instanceof HTMLButtonElement && !button.disabled;
      });
      assert.equal(await page.locator("#dashboard-publication-required").count(), 1);
      if (!route.endsWith("/diagnostics")) {
        await page.screenshot({ path: out + "/publication-desktop.png" });
        await page.setViewportSize({ width: 390, height: 844 });
        await page.screenshot({ path: out + "/publication-mobile.png" });
        assert.equal(
          await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
          true,
        );
        await page.setViewportSize({ width: 1366, height: 900 });
        await page.locator("#dashboard-publication-editor").click();
        await page.waitForURL(prefix + "/ops/dashboards/draft-dashboard/edit");
        await page.locator("#dashboard-editor-feature").waitFor();
      }
    }
  }
  console.log(
    "OPS_LIFECYCLE_AUDIT_OK " +
      JSON.stringify(results.map(({ route, generic, failure }) => ({ route, generic, failure }))),
  );
} finally {
  await browser.close();
}
