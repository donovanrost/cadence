import assert from "node:assert/strict";
import { chromium } from "playwright";
import { createInterface } from "node:readline";
import { writeFile } from "node:fs/promises";
import { fixtureRecord, fixtureString } from "../../test-support/json-fixture.ts";

const [base, mission, user, command, out, safeCommand] = process.argv.slice(2);
assert.ok(
  base && mission && user && command && out && safeCommand,
  "Expected endpoint, mission, user, command and artifact directory",
);
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
/** @type {string[]} */
const errors = [];
const context = await browser.newContext({ viewport: { width: 1512, height: 1000 } });
const page = await context.newPage();
page.setDefaultTimeout(15000);
page.on("pageerror", (error) => errors.push(error.message));
page.on("response", (response) => {
  if (
    response.status() >= 400 &&
    ["script", "stylesheet"].includes(response.request().resourceType())
  )
    errors.push(`Asset ${response.status()}: ${new URL(response.url()).pathname}`);
});
const prefix = `${base}/missions/${mission}/ops`;
try {
  await page.goto(prefix);
  await page.waitForURL(`${base}/sign-in`);
  await page.locator("#user_email").fill(user);
  await page.locator("#user_password").fill(fixtureString(fixtureRecord(secret).password));
  await page.locator("#sign-in-form").evaluate((form) => {
    if (!(form instanceof HTMLFormElement)) throw Error("Expected sign-in form");
    form.requestSubmit();
  });
  await page.waitForURL((url) => url.pathname !== "/sign-in");
  await page.goto(prefix);
  await page.locator("[data-phx-main].phx-connected").waitFor();
  const shell = await page.locator("#application-shell").elementHandle();
  assert.ok(shell);
  try {
    await page
      .locator(`#ops-nav-rail a[href="/missions/${mission}/ops/commands/workspace"]`)
      .click();
    await page.waitForURL(`${prefix}/commands/workspace`);
    await page.locator("#command-workspace").waitFor();
    assert.equal(await page.locator("h1").count(), 1, "One host-owned page heading");
    assert.equal(await page.locator(".cadence-workspace-layout__toolbar").count(), 0);
    assert.equal(await page.locator("#workspace-refresh").count(), 0);
    const contextObserver = await context.newPage();
    contextObserver.on("pageerror", (error) => errors.push(error.message));
    await contextObserver.goto(`${prefix}/commands`);
    await contextObserver.locator('[data-ops-context-collapsed-section="commands"]').click();
    const queuedCount = contextObserver
      .locator('[data-ops-context-section="commands"]')
      .getByText("Queued", { exact: true })
      .locator("..");
    await queuedCount.getByText("0", { exact: true }).waitFor();
    await page.setViewportSize({ width: 1280, height: 720 });
    await page
      .getByRole("button", { name: "Select KESTREL-01 · Primary OBC", exact: true })
      .click();
    await page
      .getByRole("button", { name: "Select KESTREL-02 · Secondary OBC", exact: true })
      .click();
    await page.locator(`[data-workspace-command="${safeCommand}"]`).click();
    await page.locator("#workspace-shared-argument-0").fill("2");
    await page.getByRole("radio", { name: "Per spacecraft", exact: true }).check();
    await page
      .getByRole("region", { name: "Settings for Secondary OBC" })
      .locator('input[id$="-argument-0"]')
      .fill("7");
    await page.locator("#workspace-enqueue:not([disabled])").waitFor();
    await page.getByRole("button", { name: "Enqueue 2 commands", exact: true }).waitFor();
    assert.equal(await page.locator("#workspace-save-targets").count(), 0);
    await page.locator("#workspace-enqueue").scrollIntoViewIfNeeded();
    await page.screenshot({ path: `${out}/enqueue-preview-laptop.png` });
    await page.locator("#workspace-enqueue").click();
    await page.getByText("2 commands queued.", { exact: true }).waitFor();
    await page.locator("#workspace-enqueue[disabled]").waitFor();
    await page
      .locator(
        '[data-ops-context-collapsed-section="commands"][data-ops-context-section-count="2"]',
      )
      .waitFor({ timeout: 5000 });
    await queuedCount.getByText("2", { exact: true }).waitFor({ timeout: 5000 });
    await contextObserver.screenshot({ path: `${out}/command-context-live.png` });
    await contextObserver.locator("#command-monitor-refresh").click();
    await contextObserver.locator("[data-command-review]").nth(1).waitFor();
    const directlyQueued = await contextObserver
      .locator("[data-command-review]")
      .evaluateAll((links) => links.map((link) => link.getAttribute("href")));
    await contextObserver.close();
    assert.equal(
      await page.getByRole("button", { name: "Expand command shelf", exact: true }).isVisible(),
      true,
    );
    assert.equal(await page.locator("[data-workspace-request]").count(), 0);
    await page.screenshot({ path: `${out}/enqueued-laptop.png` });
    await page.getByRole("button", { name: "Expand command shelf", exact: true }).click();
    assert.equal(
      await page.getByRole("button", { name: "Choose a stage", exact: true }).isVisible(),
      true,
    );
    await page.locator("#workspace-close-preparation").click();
    await page.getByRole("button", { name: "Clear", exact: true }).click();
    await page.getByRole("button", { name: "Minimize command shelf", exact: true }).click();
    await page.setViewportSize({ width: 1512, height: 1000 });
    await page.getByRole("button", { name: "Expand command shelf", exact: true }).click();
    await page.getByRole("button", { name: "Choose a stage", exact: true }).click();
    await page.getByRole("button", { name: "+ New stage", exact: true }).click();
    await page.locator("#workspace-stage-name").fill("Fleet browser preparation");
    await page.locator("#workspace-create-stage-submit").click();
    await page.getByRole("button", { name: "Fleet browser preparation", exact: true }).waitFor();
    await page
      .getByRole("button", { name: "Select KESTREL-01 · Primary OBC", exact: true })
      .click();
    await page
      .getByRole("button", { name: "Select KESTREL-02 · Secondary OBC", exact: true })
      .click();
    await page.locator(`[data-workspace-command="${command}"]`).click();
    await page.locator("#workspace-shared-argument-0").fill("2");
    assert.equal(
      await page.locator("#commanding-inspector").getAttribute("data-panel-size"),
      "36.0",
    );
    assert.equal(await page.locator("#commanding-dock").getAttribute("data-panel-size"), "34.0");
    for (const { name, panelId, horizontal } of [
      {
        name: "Resize spacecraft and command catalog",
        panelId: "#commanding-primary",
        horizontal: true,
      },
      {
        name: "Resize preparation and command shelf",
        panelId: "#commanding-dock",
        horizontal: false,
      },
    ]) {
      const handle = page.getByRole("separator", { name });
      const panel = page.locator(panelId);
      const initialSize = await panel.getAttribute("data-panel-size");
      const bounds = await handle.boundingBox();
      assert.ok(bounds);
      const x = bounds.x + bounds.width / 2;
      const y = bounds.y + bounds.height / 2;
      await page.mouse.move(x, y);
      await page.mouse.down();
      await page.mouse.move(x + (horizontal ? 40 : 0), y - (horizontal ? 0 : 40), { steps: 4 });
      assert.equal(await handle.getAttribute("data-state"), "drag", name);
      await page.mouse.up();
      assert.notEqual(await handle.getAttribute("data-state"), "drag", name);
      const releasedSize = await panel.getAttribute("data-panel-size");
      assert.notEqual(releasedSize, initialSize, `Dragging resizes ${panelId}`);
      await page.mouse.move(x + (horizontal ? 100 : 0), y - (horizontal ? 0 : 100), { steps: 4 });
      const releasedBounds = await handle.boundingBox();
      assert.ok(releasedBounds);
      const releasedX = releasedBounds.x + releasedBounds.width / 2;
      const releasedY = releasedBounds.y + releasedBounds.height / 2;
      await page.mouse.move(releasedX, releasedY);
      await page.mouse.move(releasedX + (horizontal ? 2 : 0), releasedY + (horizontal ? 0 : 2));
      assert.equal(
        await panel.getAttribute("data-panel-size"),
        releasedSize,
        `Pointer movement after release does not resize ${panelId}`,
      );
    }
    await page.getByRole("radio", { name: "Per spacecraft", exact: true }).check();
    const override = page.getByRole("region", { name: "Settings for Secondary OBC" });
    await override.locator('input[id$="-argument-0"]').fill("7");
    await page.locator("#workspace-enqueue:not([disabled])").waitFor();
    await page.locator("#workspace-save-targets").waitFor();
    assert.equal(await page.locator("#command-workspace-fleet-title").isVisible(), true);
    assert.equal(await page.locator("#command-workspace-catalog-title").isVisible(), true);
    await page.locator("#workspace-target-search").fill("Secondary");
    await page.waitForFunction(
      () => document.querySelectorAll("[data-workspace-target]").length === 1,
    );
    assert.equal(
      await page
        .getByRole("button", { name: "Select KESTREL-02 · Secondary OBC", exact: true })
        .getAttribute("aria-pressed"),
      "true",
    );
    await page.locator("#workspace-command-search").fill("COMMAND_2");
    await page.waitForFunction(() => {
      const commands = document.querySelectorAll("[data-workspace-command]");
      return commands.length === 1 && commands[0]?.textContent?.includes("COMMAND_2");
    });
    assert.equal(await override.locator('input[id$="-argument-0"]').inputValue(), "7");
    assert.equal(
      await page.locator("#workspace-save-targets").isEnabled(),
      true,
      "Searching preserves the prepared preview",
    );
    await page.locator("#workspace-target-search").fill("");
    await page.waitForFunction(
      () => document.querySelectorAll("[data-workspace-target]").length === 2,
    );
    await page.locator("#workspace-save-targets").click();
    await page.waitForFunction(() =>
      document.querySelector("#workspace-write-result")?.textContent?.includes("2 drafts saved"),
    );
    await page.getByRole("radio", { name: "All spacecraft", exact: true }).check();
    const rows = page.locator('.cw-table input[type="checkbox"]');
    await rows.nth(1).waitFor();
    assert.equal(await rows.count(), 2);
    for (const row of await rows.all()) await row.check();
    await page.locator("#workspace-review-stage").click();
    await page.locator("#stage-batch-confirm").waitFor();
    await page.locator("#stage-batch-confirm").scrollIntoViewIfNeeded();
    await page.screenshot({ path: `${out}/review-desktop.png` });
    await page.locator("#stage-batch-confirm").check();
    await page.locator("#workspace-shared-argument-0").fill("unfinished");
    await page.getByRole("button", { name: "Fleet browser preparation", exact: true }).click();
    const stageId = await page
      .locator('[data-workspace-stage][aria-pressed="true"]')
      .getAttribute("data-workspace-stage");
    assert.ok(stageId);
    const peer = await context.newPage();
    peer.on("pageerror", (error) => errors.push(error.message));
    try {
      await peer.goto(`${prefix}/commands/workspace?stage=${stageId}`);
      await peer.getByRole("button", { name: "Fleet browser preparation", exact: true }).click();
      await peer.getByRole("button", { name: "+ New stage", exact: true }).click();
      await peer.locator("#workspace-stage-name").fill("Concurrent preparation");
      await peer.locator("#workspace-create-stage-submit").click();
      await peer.getByRole("button", { name: "Concurrent preparation", exact: true }).waitFor();
      await page
        .locator("[data-workspace-stage]")
        .filter({ hasText: "Concurrent preparation" })
        .waitFor({ timeout: 5000 });
      assert.equal(
        await page.locator("#stage-batch-confirm").isChecked(),
        true,
        "An unrelated committed change preserves the confirmed review",
      );
      assert.equal(await page.locator("#workspace-shared-argument-0").inputValue(), "unfinished");
      await page.keyboard.press("Escape");
      await peer.getByRole("button", { name: "Concurrent preparation", exact: true }).click();
      await peer.locator(`[data-workspace-stage="${stageId}"]`).click();
      const changedId = await peer
        .locator("[data-workspace-item]")
        .first()
        .getAttribute("data-workspace-item");
      assert.ok(changedId);
      await peer.locator("[data-workspace-item] .cw-text-button").first().click();
      await peer.locator("#workspace-draft-order").fill("5");
      await peer.getByRole("button", { name: "Save order", exact: true }).click();
      await page.waitForFunction(
        (id) =>
          document
            .querySelector(`[data-workspace-item="${id}"] td:nth-child(2)`)
            ?.textContent?.trim() === "5",
        changedId,
        { timeout: 5000 },
      );
      assert.equal(
        await page.locator("#stage-batch-submit").count(),
        0,
        "A changed selected draft requires a fresh review",
      );
      assert.equal(await page.locator("#workspace-shared-argument-0").inputValue(), "unfinished");
      for (const row of await rows.all()) await row.check();
      await page.locator("#workspace-review-stage").click();
      await page.locator("#stage-batch-confirm").waitFor();
      assert.equal(await page.locator("#stage-batch-confirm").isChecked(), false);
      await page.locator("#stage-batch-confirm").check();
      await page.locator("#stage-batch-submit").click();
      await page.locator("[data-workspace-request]").nth(1).waitFor();
      const expectedRequests = await page
        .locator("[data-workspace-request]")
        .evaluateAll((links) => links.map((link) => link.getAttribute("href")));
      await peer.locator("[data-workspace-item] a").nth(1).waitFor({ timeout: 5000 });
      assert.deepEqual(
        new Set(
          await peer
            .locator("[data-workspace-item] a")
            .evaluateAll((links) => links.map((link) => link.getAttribute("href"))),
        ),
        new Set(expectedRequests),
        "Submission updates the other stage reader",
      );
      await peer.goto(`${prefix}/commands`);
      await peer.locator("[data-command-review]").nth(3).waitFor();
      assert.deepEqual(
        new Set(
          await peer
            .locator("[data-command-review]")
            .evaluateAll((links) => links.map((link) => link.getAttribute("href"))),
        ),
        new Set([...expectedRequests, ...directlyQueued]),
        "The command monitor includes both staged and directly queued requests",
      );
    } finally {
      await peer.close();
    }
    await page.waitForFunction(() =>
      document
        .querySelector("#workspace-write-result")
        ?.textContent?.includes("2 formal requests created"),
    );
    assert.equal(await page.locator("[data-workspace-request]").count(), 2);
    assert.equal(
      await page.evaluate(
        (previous) => previous === document.querySelector("#application-shell"),
        shell,
      ),
      true,
      "Workspace actions retain the host shell",
    );
    await page.getByRole("button", { name: "Close command preparation", exact: true }).click();
    await page.waitForFunction(
      () => !document.querySelector("#command-workspace-preparation-title"),
    );
    await page.screenshot({ path: `${out}/staged-desktop.png` });
    const dockSize = await page.locator("#commanding-dock").getAttribute("data-panel-size");
    await page.getByRole("button", { name: "Minimize command shelf", exact: true }).click();
    const expandShelf = page.getByRole("button", { name: "Expand command shelf", exact: true });
    await expandShelf.waitFor();
    assert.equal(await page.locator(".cadence-workspace-layout__status").count(), 0);
    assert.equal(await page.locator("#workspace-open-shelf").count(), 0);
    await page.screenshot({ path: `${out}/minimized-desktop.png` });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: `${out}/minimized-mobile.png` });
    const minimizedBounds = await expandShelf.boundingBox();
    assert.ok(minimizedBounds && minimizedBounds.y + minimizedBounds.height <= 844);
    await expandShelf.click();
    await page.waitForFunction(() => {
      const bounds = document.querySelector("#commanding-dock")?.getBoundingClientRect();
      return bounds && bounds.top >= 0 && bounds.bottom <= innerHeight + 1;
    });
    assert.equal(await page.locator("#commanding-dock").getAttribute("data-panel-size"), dockSize);
    const picker = await page
      .getByRole("button", { name: "Fleet browser preparation", exact: true })
      .boundingBox();
    assert.ok(picker);
    const minimize = await page
      .getByRole("button", { name: "Minimize command shelf", exact: true })
      .boundingBox();
    assert.ok(minimize);
    assert.equal(
      Math.max(picker.x, minimize.x) <
        Math.min(picker.x + picker.width, minimize.x + minimize.width) &&
        Math.max(picker.y, minimize.y) <
          Math.min(picker.y + picker.height, minimize.y + minimize.height),
      false,
      "The stage picker does not overlap the minimize button on narrow screens",
    );
    await page.screenshot({ path: `${out}/staged-mobile.png` });
    assert.equal(
      await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      true,
      "No page-level horizontal overflow",
    );
    assert.deepEqual(errors, []);
    await writeFile(
      `${out}/results.json`,
      JSON.stringify(
        {
          stage: "Fleet browser preparation",
          endpoints: 2,
          drafts: 2,
          requests: 2,
          directlyQueued: 2,
          liveSessions: 2,
          liveReviewPreserved: true,
          changedReviewInvalidated: true,
          errors,
        },
        null,
        2,
      ),
    );
    console.log(`COMMAND_WORKSPACE_BROWSER_OK ${out}`);
  } finally {
    await shell.dispose();
  }
} catch (error) {
  await page.screenshot({ path: `${out}/failure.png` });
  await writeFile(
    `${out}/failure.txt`,
    `${String(error)}\n${errors.join("\n")}\n${await page.locator("body").innerText()}`,
  );
  throw error;
} finally {
  await browser.close();
}
