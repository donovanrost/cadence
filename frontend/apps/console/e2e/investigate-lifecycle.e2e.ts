import { expectAccessible } from "./support/accessibility.ts";
import { routeAlarms } from "./support/alarms.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { routeEpisodes } from "./support/episodes.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// Decision 6 · minimal alarm lifecycle on Investigate (fe-ops 77f93bad): acknowledge, assign,
// outcome messages. Episodes are a stateful fixture (no limits in the seed); people are real.
const screen = missionPath("fleet/1/investigate");
const alarm = {
  scid: 1,
  point: { id: "EPS.sa1_current", name: "sa1_current", subsystem: "EPS" },
  severity: "critical",
  condition: "red_low",
  value: -6.1,
  thresholds: { red_low: -5.5, yellow_low: -5, yellow_high: 5, red_high: 6 },
  firstCrossedAt: "2026-11-08T22:55:20Z",
  receivedAt: "2026-11-08T22:55:57Z",
} as const;

test.describe("Alarm lifecycle on Investigate (decision 6)", () => {
  test("Acknowledge records who and when, and B2 logs it", async ({ page }) => {
    await routeAlarms(page, [alarm]);
    const server = await routeEpisodes(page);
    await openConsole(page, screen);
    const ack = page.getByRole("button", { name: "Acknowledge" });
    await expect(ack).toBeVisible();
    await expectAccessible(page);

    await ack.click();
    await expect.poll(() => server.commands.map((c) => c.command)).toEqual(["acknowledge"]);
    await expect(page.getByRole("button", { name: "Acknowledge" })).toHaveCount(0);
    await expect(page.getByText(/acknowledged/i).first()).toBeVisible();
    await expect(page.getByText(/Cadence Administrator/).first()).toBeVisible();
  });

  test("Assign picks a real member and sends their user id", async ({ page }) => {
    await routeAlarms(page, [alarm]);
    const server = await routeEpisodes(page);
    await openConsole(page, screen);
    await page.getByRole("button", { name: "Assign" }).click();
    const who = page.getByRole("combobox", { name: "Assign to" });
    await expect(who.locator("option", { hasText: "QA Operator" })).toHaveCount(1);
    await who.selectOption({ label: "QA Operator" });
    await page.getByRole("textbox", { name: "Note (optional)" }).fill("QA-E2E take this one");
    await page.getByRole("button", { name: "Assign" }).last().click();
    await expect.poll(() => server.commands.at(-1)?.command).toBe("assign");
    const body = server.commands.at(-1)?.body ?? {};
    expect(typeof body["user_id"]).toBe("string");
    expect(body["note"]).toBe("QA-E2E take this one");
  });

  test("without lifecycle permissions there are no Acknowledge / Assign controls", async ({
    page,
  }) => {
    await routeAlarms(page, [alarm]);
    await routeEpisodes(page, { permissions: [] });
    await openConsole(page, screen);
    await expect(page.getByText("EPS · below red limit", { exact: false })).toBeVisible();
    await expect(page.getByRole("button", { name: "Acknowledge" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Assign" })).toHaveCount(0);
  });

  test.describe("when the command fails", () => {
    test.use({
      allowedDiagnostics: allow(/acknowledge -> (?:409|500)/, /status of (?:409|500)/),
    });

    test("a 4xx says nothing changed", async ({ page }) => {
      await routeAlarms(page, [alarm]);
      const server = await routeEpisodes(page);
      server.failNext(409, "episode_cleared");
      await openConsole(page, screen);
      await page.getByRole("button", { name: "Acknowledge" }).click();
      await expect(page.getByRole("status").filter({ hasText: /Nothing changed:/ })).toBeVisible();
      await expect(page.getByRole("button", { name: "Acknowledge" })).toBeVisible();
    });

    test("a 5xx says it's unclear and offers Check now, not Retry", async ({ page }) => {
      await routeAlarms(page, [alarm]);
      const server = await routeEpisodes(page);
      server.failNext(500, "internal_error");
      await openConsole(page, screen);
      await page.getByRole("button", { name: "Acknowledge" }).click();
      await expect(page.getByText(/It's unclear whether that went through/)).toBeVisible();
      await expect(page.getByRole("button", { name: "Check now" })).toBeVisible();
      await expect(page.getByRole("button", { name: "Retry" })).toHaveCount(0);
    });
  });
});
