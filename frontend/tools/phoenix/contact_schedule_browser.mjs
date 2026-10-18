import assert from "node:assert/strict";
import { chromium } from "playwright";
import { createInterface } from "node:readline";
import { writeFile } from "node:fs/promises";
import { fixtureRecord, fixtureString } from "../../test-support/json-fixture.ts";

const [base, mission, spacecraft, email, output] = process.argv.slice(2);
assert.ok(base && mission && spacecraft && email && output);
const reader = createInterface({ input: process.stdin });
/** @type {unknown} */
const credentials = await new Promise((resolve) =>
  reader.once("line", (line) => {
    reader.close();
    resolve(JSON.parse(line));
  }),
);
process.stdin.destroy();
const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 1366, height: 900 } });
page.setDefaultTimeout(15000);
/** @type {string[]} */
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
const native = `${base}/missions/${mission}/ops/contacts?spacecraft_id=${spacecraft}`;
const remote = `${base}/missions/${mission}/applications/ops_console/contact_schedule/federated?spacecraft_id=${spacecraft}`;
const workspace = `${base}/missions/${mission}/ops/contact-workspace?spacecraft_id=${spacecraft}`;
/** @param {string} id */
async function completed(id) {
  const row = page.locator(`[data-operation-id="${id}"]`);
  for (let attempt = 0; attempt < 30; attempt++) {
    if ((await row.textContent())?.includes("completed")) return;
    await page.locator("#contact-schedule-refresh").click();
    await page.waitForTimeout(200);
  }
  assert.fail(`Operation ${id} did not complete: ${await row.textContent()}`);
}
try {
  await page.goto(native);
  await page.waitForURL(`${base}/sign-in`);
  await page.locator("#user_email").fill(email);
  await page.locator("#user_password").fill(fixtureString(fixtureRecord(credentials).password));
  await page.locator("#sign-in-form").evaluate((form) => {
    if (!(form instanceof HTMLFormElement)) throw Error("Expected sign-in form");
    form.requestSubmit();
  });
  await page.waitForURL((url) => url.pathname !== "/sign-in");
  await page.goto(native);
  await page.locator("#contact-search-submit").click();
  await page.locator("#reserve-opportunity-alpha").click();
  const nativeOperation = page.locator("[data-operation-id]").first();
  await nativeOperation.getByRole("link", { name: "Reservation", exact: true }).waitFor();
  const reserveId = await nativeOperation.getAttribute("data-operation-id");
  assert.ok(reserveId);
  await page.goto(`${base}/missions/${mission}/ops`);
  await page.goto(remote);
  await page.locator(`[data-operation-id="${reserveId}"]`).waitFor();
  await completed(reserveId);
  await page.goto(workspace);
  await page.locator("#ops-contact-schedule-page").waitFor();
  assert.equal(await page.evaluate(() => "liveSocket" in window), false);
  const shell = page.locator("#ops-workspace-header");
  await shell.evaluate((element) => element.setAttribute("data-navigation-probe", "preserved"));
  const documentStart = await page.evaluate(() => performance.timeOrigin);
  let releaseRecord = () => {};
  const recordGate = new Promise((resolve) => {
    releaseRecord = () => resolve(undefined);
  });
  const records = "**/api/cadence/contact-workspace/v1/missions/*/records/*";
  await page.route(records, async (route) => {
    await recordGate;
    await route.fulfill({ status: 503, contentType: "application/json", body: "{}" });
  });
  const started = performance.now();
  await page
    .locator('#contact-scheduled-ledger a[href*="/contact-workspace/records/"]')
    .first()
    .click();
  await page.waitForURL(/\/contact-workspace\/records\//);
  await page.locator("#contact-workspace-loading").waitFor();
  const navigationMs = Math.round(performance.now() - started);
  assert.equal(await shell.getAttribute("data-navigation-probe"), "preserved");
  assert.equal(await page.evaluate(() => performance.timeOrigin), documentStart);
  releaseRecord();
  await page.locator("#contact-workspace-error").waitFor();
  await page.unroute(records);
  await page.locator("#contact-workspace-retry").click();
  await page.locator("#ops-contact-record-page").waitFor();

  // Hold the refresh to prove Back renders the cached schedule independently of HTTP.
  const schedules = "**/api/cadence/contact-workspace/v1/missions/*/schedule*";
  let releaseSchedule = () => {};
  const scheduleGate = new Promise((resolve) => {
    releaseSchedule = () => resolve(undefined);
  });
  await page.route(schedules, async (route) => {
    await scheduleGate;
    await route.continue();
  });
  await page.goBack();
  await page.locator("#ops-contact-schedule-page").waitFor();
  assert.equal(await shell.getAttribute("data-navigation-probe"), "preserved");
  await page.locator("#search-start").fill("2099-09-10T12:00");
  const refreshed = page.waitForResponse(
    (response) => response.url().includes("/schedule?") && response.ok(),
  );
  releaseSchedule();
  await refreshed;
  await page.unroute(schedules);
  assert.equal(await page.locator("#search-start").inputValue(), "2099-09-10T12:00");
  await page.screenshot({ path: `${output}/contact-workspace-schedule.png`, fullPage: true });
  await page
    .locator('#contact-scheduled-ledger a[href*="/contact-workspace/records/"]')
    .first()
    .click();
  await page.locator("#ops-contact-record-page").waitFor();
  await page.reload();
  await page.locator("#ops-contact-record-page").waitFor();
  assert.equal(await page.evaluate(() => "liveSocket" in window), false);
  await page.screenshot({ path: `${output}/contact-workspace-record.png`, fullPage: true });
  await page.goBack();
  await page.locator("#ops-contact-schedule-page").waitFor();
  await page.locator('[id^="cancel-review-"]').first().click();
  await page.locator("#contact-cancel-confirm").click();
  const canceled = page.locator("[data-operation-id]").filter({ hasText: "cancel" }).first();
  await canceled.getByRole("link", { name: "Reservation", exact: true }).waitFor();
  const cancelId = await canceled.getAttribute("data-operation-id");
  assert.ok(cancelId && cancelId !== reserveId);
  await page.goto(native);
  await page.locator(`[data-operation-id="${cancelId}"]`).waitFor();
  await completed(cancelId);
  assert.match(await page.locator("#contact-reservations").innerText(), /canceled/);
  assert.deepEqual(errors, []);
  await page.screenshot({ path: `${output}/contact-schedule-recovered.png`, fullPage: true });
  await writeFile(
    `${output}/contact-workspace-result.json`,
    JSON.stringify(
      {
        navigationMs,
        responseHeldUntilRouteRendered: true,
        shellPreserved: true,
        cachedBackRenderedBeforeRefresh: true,
        deepLinkReloaded: true,
        sharedDurableOperations: true,
      },
      null,
      2,
    ),
  );
  process.stdout.write(`CONTACT_WORKSPACE_ROUTE_VISIBLE_WITH_RESPONSE_HELD_MS=${navigationMs}\n`);
  process.stdout.write("CONTACT_SCHEDULE_BROWSER_OK\n");
} catch (error) {
  await page.screenshot({ path: `${output}/contact-schedule-failure.png`, fullPage: true });
  throw error;
} finally {
  await browser.close();
}
