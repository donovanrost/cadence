import assert from "node:assert/strict";
import { chromium } from "playwright";
import { createInterface } from "node:readline";
import { fixtureRecord, fixtureString } from "../../test-support/json-fixture.ts";

const [base, mission, user, first, second, revision, out] = process.argv.slice(2);
assert.ok(base && mission && user && first && second && revision && out);
const reader = createInterface({ input: process.stdin });
/** @type {unknown} */
const secret = await new Promise((resolve, reject) =>
  reader.once("line", (line) => {
    reader.close();
    try {
      resolve(JSON.parse(line));
    } catch (error) {
      reject(error);
    }
  }),
);
process.stdin.destroy();
const browser = await chromium.launch({ channel: "chrome", headless: true });
const context = await browser.newContext({ viewport: { width: 1512, height: 1000 } });
const page = await context.newPage();
page.setDefaultTimeout(20000);
/** @type {string[]} */
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
const path = `/missions/${mission}/spacecraft/${first}`;
try {
  await page.goto(`${base}${path}`);
  await page.waitForURL(`${base}/sign-in`);
  await page.locator("#user_email").fill(user);
  await page.locator("#user_password").fill(fixtureString(fixtureRecord(secret).password));
  await page.locator('#sign-in-form button[type="submit"]').click();
  await page.waitForURL((url) => url.pathname !== "/sign-in");
  await page.goto(`${base}${path}`);
  await page.locator("#spacecraft-configuration-workspace").waitFor();
  assert.equal(await page.locator("h1").count(), 1);
  const shell = await page.locator("#application-shell").elementHandle();
  assert.ok(shell);
  try {
    const sections = page.getByRole("navigation", { name: "Spacecraft sections" });
    await sections.getByRole("link", { name: "Catalog & applications" }).click();
    await page.getByRole("button", { name: "Choose catalog", exact: true }).click();
    await page.getByRole("button", { name: "Use in draft", exact: true }).click();
    await page.getByRole("button", { name: /Telemetry Decom Turn incoming/ }).click();
    await page.getByRole("checkbox", { name: "Enable Telemetry Decom", exact: true }).check();
    await page.getByRole("checkbox", { name: /HEALTH APID 42/ }).check();
    await page.screenshot({ path: `${out}/packet-inputs.png`, animations: "disabled" });
    await page.getByRole("button", { name: "Done", exact: true }).click();
    await page.getByRole("button", { name: /Commanding Build and validate/ }).click();
    await page.getByRole("checkbox", { name: "Enable Commanding", exact: true }).check();
    await page.getByRole("button", { name: "Done", exact: true }).click();
    await page.getByRole("link", { name: "Mission catalog", exact: true }).click();
    await page.waitForURL(`${base}/missions/${mission}/catalog`);
    await page.goBack();
    await page.locator("#spacecraft-save-draft").waitFor();
    assert.equal(
      await page
        .getByRole("button", { name: /Commanding Build and validate/ })
        .innerText()
        .then((text) => text.includes("Configured")),
      true,
    );
    await page.locator("#spacecraft-switcher [data-overlay-trigger]").click();
    await page
      .locator(`a[href="/missions/${mission}/spacecraft/${second}?section=catalog"]`)
      .click();
    await page.getByRole("button", { name: "Choose catalog", exact: true }).waitFor();
    assert.equal(await page.locator("#spacecraft-save-draft").count(), 0);
    await page.locator("#spacecraft-switcher [data-overlay-trigger]").click();
    await page.locator(`a[href="${path}?section=catalog"]`).click();
    await page.locator("#spacecraft-save-draft").click();
    await page
      .getByText("Draft saved. Active configuration remains in use.", { exact: true })
      .waitFor();
    await sections.getByRole("link", { name: /^Changes/ }).click();
    await page.locator("#spacecraft-submit-review").click();
    await page.getByText("Awaiting review", { exact: true }).waitFor();
    await page.screenshot({ path: `${out}/changes-desktop.png`, animations: "disabled" });
    await page
      .locator(`a[href="/missions/${mission}/catalog/revisions/${revision}"]`)
      .first()
      .click();
    await page
      .locator("#catalog-spacecraft-usage")
      .getByRole("link", { name: "Review changes for KESTREL-01" })
      .click();
    await page.getByText("Awaiting review", { exact: true }).waitFor();
    assert.equal(
      await shell.evaluate(
        (node) => node.isConnected && node === document.querySelector("#application-shell"),
      ),
      true,
    );
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: `${out}/changes-mobile.png`, animations: "disabled" });
    assert.equal(
      await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      true,
    );
    assert.deepEqual(errors, []);
  } finally {
    await shell.dispose();
  }
  process.stdout.write("SPACECRAFT_CONFIGURATION_BROWSER_OK\n");
} catch (error) {
  await page.screenshot({ path: `${out}/failure.png`, animations: "disabled" });
  process.stderr.write(
    `${String(error)}\n${(await page.locator("body").innerText()).slice(0, 12000)}\n${errors.join("\n")}\n`,
  );
  process.exitCode = 1;
} finally {
  await browser.close();
}
