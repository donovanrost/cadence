import type { Locator, Page } from "@playwright/test";
import { expectAccessible } from "./support/accessibility.ts";
import { jsonProblem, missionApi, missionPath, openConsole } from "./support/console.ts";
import { DEMO } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";
import { refuseLiveSocket, routeDegradedNow, type Degradation } from "./support/fleet.ts";

// J1 · Now (fe-ops, 7cd1e7a4). Spec: docs/apogee/ux/screens/Now.md; data: /fleet (ops.md).
const screen = missionPath("now");

/** A bad shift: plane 7 overheating, 312 undervolt, plane 5 gone quiet, two GOs waiting. */
const badShift: Degradation = {
  critical: {
    312: { point: "VBAT", value: 23.1, raw: "red_low" },
    152: { point: "TBATT", value: 61, raw: "red_high" },
    153: { point: "TBATT", value: 62, raw: "red_high" },
    154: { point: "TBATT", value: 61.5, raw: "red_high" },
  },
  caution: { 401: { point: "TPANEL", value: 48, raw: "yellow_high" } },
  stale: [101, 102, 103, 104],
  neverHeard: [499, 500],
  awaitingViewer: 2,
};

const allNominal: Degradation = {};

/** Before the first AOS: nothing ever received, no ground limits (the bare seed). */
const nothingYet: Degradation = {
  neverHeard: Array.from({ length: DEMO.spacecraftCount }, (_, i) => i + 1),
  limitsConfigured: false,
};

function statTile(page: Page, label: string): Locator {
  return (
    page
      .getByRole("region", { name: "Fleet status" })
      // A tile is a link to the list behind its number since b2792cd90, so any direct child.
      .locator(":scope > *")
      .filter({ has: page.getByText(label, { exact: true }) })
  );
}

function queue(page: Page): Locator {
  return page
    .locator("section, div")
    .filter({ has: page.getByRole("heading", { name: "Action queue" }) })
    .last()
    .getByRole("listitem");
}

test.describe("Now (J1)", () => {
  // routeDegradedNow refuses the live socket so the fleet fixture isn't overwritten by pushes.
  test.use({ allowedDiagnostics: allow(/\/socket\/websocket/) });

  test.describe("nothing received yet", () => {
    test.beforeEach(async ({ page }) => {
      await routeDegradedNow(page, nothingYet);
    });

    test("is honest: no telemetry yet, unknowns shown as unknown", async ({ page }) => {
      await openConsole(page, screen);
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(/no telemetry yet/i);
      await expect(
        page.getByText(`TLM fresh 0/${DEMO.spacecraftCount}`, { exact: false }),
      ).toBeVisible();

      await expect(statTile(page, "Nominal")).toContainText(
        `+${DEMO.spacecraftCount} awaiting first contact`,
      );
      for (const label of ["Caution", "Critical", "Stale"]) {
        // A zero we couldn't have observed is unknown (ux U13), never a reassuring 0.
        await expect(statTile(page, label)).toContainText("unknown");
        await expect(statTile(page, label)).toContainText(/no telemetry yet|limits not configured/);
      }
      // In contact comes from passes, not telemetry: a count when the server tracks passes.
      await expect(statTile(page, "In contact")).toContainText(
        /not tracked yet|\d+ pass(es)? next 2 h/,
      );

      await expect(queue(page)).toHaveCount(2);
      await expect(queue(page).nth(1)).toContainText(
        `${DEMO.spacecraftCount} spacecraft not heard from yet`,
      );
      await expect(page.getByText(/all \d+ nominal/i)).toHaveCount(0);
    });

    test("constellation, matrix and passes render without inventing a pass schedule", async ({
      page,
    }) => {
      await openConsole(page, screen);
      await expect(page.getByRole("heading", { name: "Fleet matrix" })).toBeVisible();
      await expect(page.getByText(`${DEMO.spacecraftCount} spacecraft`).first()).toBeVisible();
      // A4 reads real passes (M7): either passes or an honest "no passes" line.
      await expect(page.getByRole("heading", { name: /passes · next 2 h/i })).toBeVisible();
    });
  });

  test.describe("a bad shift (fixture over the real fleet)", () => {
    test.beforeEach(async ({ page }) => {
      await routeDegradedNow(page, badShift);
      await openConsole(page, screen);
    });

    test("headline counts the spacecraft that need you", async ({ page }) => {
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(/4 spacecraft need you/i);
      await expect(statTile(page, "Critical")).toContainText("4");
      await expect(statTile(page, "Caution")).toContainText("1");
      await expect(statTile(page, "Stale")).toContainText("4");
      await expect(statTile(page, "Nominal")).toContainText(
        `${DEMO.spacecraftCount - 11}/${DEMO.spacecraftCount}`,
      );
      await expect(statTile(page, "Nominal")).toContainText("+2 awaiting first contact");
      await expect(statTile(page, "Uplinks queued")).toContainText("2 await your GO");
    });

    test("action queue is ranked P1→P3 and groups identical causes", async ({ page }) => {
      const rows = queue(page);
      await expect(rows.first()).toContainText("P1");
      const priorities = (await rows.allInnerTexts()).map((text) =>
        Number(/P([123])/.exec(text)?.[1]),
      );
      expect(priorities.length).toBeGreaterThanOrEqual(6);
      expect(priorities, "sorted by urgency").toEqual([...priorities].sort((a, b) => a - b));

      await expect(rows.first()).toContainText("P1");
      await expect(rows.filter({ hasText: "3 spacecraft · TBATT above red limit" })).toHaveCount(1);
      await expect(rows.filter({ hasText: "EARENDIL-312 · VBAT below red limit" })).toHaveCount(1);
      await expect(rows.filter({ hasText: "2 command requests await your GO" })).toHaveCount(1);
      await expect(rows.filter({ hasText: "4 in plane 5 stale" })).toHaveCount(1);
      await expect(rows.filter({ hasText: "2 spacecraft not heard from yet" })).toHaveCount(1);

      // Status is never color alone: every row carries a P-label and words.
      for (const text of await rows.allInnerTexts()) expect(text).toMatch(/P[123]/);
    });

    test("keyboard: reach the top P1 action and engage it", async ({ page }) => {
      const engage = page.getByRole("link", { name: "Engage" }).first();
      await engage.focus();
      await expect(engage).toBeFocused();
      await page.keyboard.press("Enter");
      await expect(page).toHaveURL(/\/fleet\/312\/investigate$/);
    });

    test("is accessible with alarms showing", async ({ page }) => {
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(/need you/i);
      await expectAccessible(page);
    });
  });

  test("all nominal says so plainly", async ({ page }) => {
    await routeDegradedNow(page, allNominal);
    await openConsole(page, screen);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      new RegExp(`all ${DEMO.spacecraftCount} nominal`, "i"),
    );
    await expect(page.getByText(/nothing needs you/i)).toBeVisible();
  });

  test.describe("when the fleet read fails", () => {
    test.use({
      allowedDiagnostics: allow(/\/fleet -> 500/, /status of 500/, /\/socket\/websocket/),
    });

    test("says the fleet status is unavailable and offers retry", async ({ page }) => {
      // The live fleet push would replace the failed read with real data ("No telemetry yet").
      await refuseLiveSocket(page);
      await page.route(missionApi("fleet"), (route) =>
        route.fulfill(jsonProblem(500, "internal_error")),
      );
      await openConsole(page, screen);
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(/fleet status unavailable/i);
      await expect(page.getByRole("button", { name: "Retry" })).toBeVisible();
      await expect(page.getByText(/need you|nominal/i)).toHaveCount(0);
    });

    // #646 (a11y B6, #603): a first load's failure is read politely; after the person's Retry
    // fails too, it's an alert.
    test("a failed first load is polite; a failed Retry is an alert", async ({ page }) => {
      // The live fleet push would replace the failed read with real data ("No telemetry yet").
      await refuseLiveSocket(page);
      await page.route(missionApi("fleet"), (route) =>
        route.fulfill(jsonProblem(500, "internal_error")),
      );
      await openConsole(page, screen);
      const retry = page.getByRole("button", { name: "Retry" });
      const roleOfFailure = () => retry.locator("xpath=ancestor::*[@role][1]").getAttribute("role");
      await expect(retry).toBeVisible();
      expect(await roleOfFailure()).toBe("status");
      await retry.click();
      await expect.poll(roleOfFailure).toBe("alert");
    });
  });

  test.describe("phone width", () => {
    test.use({ viewport: { width: 390, height: 844 } });

    test("no horizontal scroll; the action queue comes first", async ({ page }) => {
      await routeDegradedNow(page, badShift);
      await openConsole(page, screen);
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(/need you/i);
      const [scrollWidth, innerWidth] = await page.evaluate(() => [
        document.documentElement.scrollWidth,
        window.innerWidth,
      ]);
      expect(scrollWidth).toBeLessThanOrEqual(innerWidth);
      await expect(queue(page).first()).toBeInViewport();
    });
  });
});
