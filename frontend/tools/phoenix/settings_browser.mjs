import assert from "node:assert/strict";
import { chromium } from "playwright";
import { createInterface } from "node:readline";
import { fixtureRecord, fixtureString } from "../../test-support/json-fixture.ts";
const [base, mission, requester, reviewer, first, second, out] = process.argv.slice(2);
assert.ok(base && mission && requester && reviewer && first && second && out);
const input = createInterface({ input: process.stdin });
/** @type {unknown} */
const secret = await new Promise((resolve, reject) =>
  input.once("line", (line) => {
    input.close();
    try {
      resolve(JSON.parse(line));
    } catch (error) {
      reject(error);
    }
  }),
);
process.stdin.destroy();
const browser = await chromium.launch({ channel: "chrome", headless: true });
const firstContext = await browser.newContext({ viewport: { width: 1512, height: 1000 } });
const secondContext = await browser.newContext({ viewport: { width: 1512, height: 1000 } });
const page = await firstContext.newPage();
const teammate = await secondContext.newPage();
/** @type {string[]} */
const errors = [];
for (const current of [page, teammate]) {
  current.setDefaultTimeout(20000);
  current.on("pageerror", (error) => errors.push(error.message));
}
/** @param {import("playwright").Page} current @param {string} email */
async function login(current, email) {
  await current.goto(base + "/sign-in");
  await current.locator("#user_email").fill(email);
  await current.locator("#user_password").fill(fixtureString(fixtureRecord(secret).password));
  await current.locator('#sign-in-form button[type="submit"]').click();
  await current.waitForURL((url) => url.pathname !== "/sign-in");
}
/** @param {import("playwright").Page} current */
async function save(current) {
  await current.getByRole("button", { name: "Save changes", exact: true }).click();
  await current.getByText("Changes saved.", { exact: true }).waitFor();
}
const settings = `/missions/${mission}/settings`;
const firstPath = `/missions/${mission}/spacecraft/${first}?section=changes`;
const secondPath = `/missions/${mission}/spacecraft/${second}?section=changes`;
try {
  await login(page, requester);
  await login(teammate, reviewer);
  await page.goto(base + firstPath);
  await page
    .getByRole("navigation", { name: "Settings", exact: true })
    .getByRole("link", { name: "Settings", exact: true })
    .click();
  await page.waitForURL(base + settings);
  await page.getByRole("radio", { name: /^One authorized operator/ }).check();
  await page
    .getByRole("navigation", { name: "Settings sections" })
    .getByRole("link", { name: "Commanding" })
    .click();
  await page.getByRole("radio", { name: /^Minimized/ }).check();
  await save(page);
  await page
    .getByRole("navigation", { name: "Settings sections" })
    .getByRole("link", { name: /Governance/ })
    .click();
  assert.equal(
    await page.getByRole("radio", { name: /^One authorized operator/ }).isChecked(),
    true,
  );
  await save(page);
  await page.screenshot({ path: `${out}/mission-settings.png`, animations: "disabled" });
  assert.equal(await page.locator("h1").count(), 1);
  await page.goto(base + firstPath);
  await page.locator("#spacecraft-activate").click();
  await page.getByText("Configuration activated", { exact: true }).waitFor();
  assert.equal(await page.locator("#spacecraft-activate").count(), 0);
  await page.getByRole("link", { name: "View catalog", exact: true }).click();
  await page.locator("#catalog-spacecraft-usage").waitFor();
  assert.equal(await page.locator("#catalog-qualification").count(), 0);
  assert.equal(await page.getByRole("button", { name: "Approve catalog model" }).count(), 0);
  await page.getByRole("link", { name: "Review changes for KESTREL-01", exact: true }).click();
  await page.waitForURL(base + firstPath);
  await page.getByText("Configuration activated", { exact: true }).waitFor();
  await page.goto(base + "/settings");
  await page
    .getByRole("checkbox", { name: "Allow missions to override this requirement" })
    .uncheck();
  await save(page);
  await page.screenshot({ path: `${out}/organization-settings.png`, animations: "disabled" });
  await page.goto(base + settings);
  await page.getByText("Required by organization", { exact: true }).first().waitFor();
  assert.equal(
    await page.getByRole("radio", { name: /^One authorized operator/ }).isDisabled(),
    true,
  );
  await page.goto(base + secondPath);
  await page.locator("#spacecraft-submit-review").click();
  await page.getByText("Awaiting review", { exact: true }).waitFor();
  assert.equal(await page.getByRole("button", { name: "Approve & activate" }).count(), 0);
  await teammate.goto(base + secondPath);
  await teammate
    .getByRole("textbox", { name: "Review rationale" })
    .fill("Verified the exact catalog and spacecraft comparison.");
  await teammate.getByRole("button", { name: "Approve & activate" }).click();
  await teammate.getByText("Configuration activated", { exact: true }).waitFor();
  await page.getByText("Configuration activated", { exact: true }).waitFor();
  assert.equal(await teammate.locator("#spacecraft-submit-review").count(), 0);
  await teammate.screenshot({ path: `${out}/approved-configuration.png`, animations: "disabled" });
  await page.goto(base + settings + "/commanding.defaults");
  await page.getByRole("radio", { name: /^Minimized/ }).waitFor();
  assert.equal(await page.getByRole("radio", { name: /^Minimized/ }).isChecked(), true);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: `${out}/settings-mobile.png`, animations: "disabled" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  assert.deepEqual(errors, []);
  process.stdout.write("SETTINGS_BROWSER_OK\n");
} catch (error) {
  await page.screenshot({ path: `${out}/failure.png`, animations: "disabled" });
  process.stderr.write(
    `${String(error)}\n${(await page.locator("body").innerText()).slice(0, 10000)}\n${errors.join("\n")}\n`,
  );
  process.exitCode = 1;
} finally {
  await browser.close();
}
