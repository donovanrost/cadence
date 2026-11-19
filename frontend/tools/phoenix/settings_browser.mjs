import assert from "node:assert/strict";
import { chromium } from "playwright";
import { createInterface } from "node:readline";
import { fixtureRecord, fixtureString } from "../../test-support/json-fixture.ts";
import { signInThroughConsole } from "./console_sign_in.mjs";
const [base, mission, requester, reviewer, first, second, out, phase] = process.argv.slice(2);
assert.ok(base && mission && requester && reviewer && first && second && out);
// Spacecraft activation under scoped settings, in two phases. §11c moved the settings pages to
// the console, so the driver sets them through the domain API the console uses: before "mission"
// the mission applies changes without approval (one operator activates directly); before
// "enforced" the organization requires independent approval with no mission override (submit,
// then a teammate approves).
assert.ok(phase === "mission" || phase === "enforced", "phase must be mission or enforced");
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
/** @param {import("playwright").Page} current @param {string | undefined} email @param {string} path */
async function login(current, email, path) {
  await signInThroughConsole(current, {
    // A function declaration doesn't see the argv assertion's narrowing.
    base: fixtureString(base),
    email: fixtureString(email),
    password: fixtureString(fixtureRecord(secret).password),
    path,
  });
}
const firstPath = `/missions/${mission}/spacecraft/${first}?section=changes`;
const secondPath = `/missions/${mission}/spacecraft/${second}?section=changes`;
try {
  if (phase === "mission") await missionPhase();
  else await enforcedPhase();
  assert.deepEqual(errors, []);
  process.stdout.write(
    phase === "mission" ? "SETTINGS_MISSION_PHASE_OK\n" : "SETTINGS_BROWSER_OK\n",
  );
} catch (error) {
  await page.screenshot({ path: `${out}/failure-${phase}.png`, animations: "disabled" });
  process.stderr.write(
    `${String(error)}\n${(await page.locator("body").innerText()).slice(0, 10000)}\n${errors.join("\n")}\n`,
  );
  process.exitCode = 1;
} finally {
  await browser.close();
}

async function missionPhase() {
  // The driver set this mission to "Applies without approval" (one authorized operator), so the
  // requester activates directly.
  await login(page, requester, firstPath);
  await page.locator("#spacecraft-activate").click();
  await page.getByText("Configuration activated", { exact: true }).waitFor();
  assert.equal(await page.locator("#spacecraft-activate").count(), 0);
  assert.equal(await page.locator("h1").count(), 1);
}

async function enforcedPhase() {
  // The driver then required independent approval organization-wide (no mission override), so
  // the same requester can only submit for review and a teammate approves.
  await login(page, requester, secondPath);
  await login(teammate, reviewer, secondPath);
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
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: `${out}/spacecraft-mobile.png`, animations: "disabled" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
}
