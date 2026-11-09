import { expectAccessible } from "./support/accessibility.ts";
import { routeAlarms, type AlarmSpec } from "./support/alarms.ts";
import { jsonProblem, missionApi, missionPath, openConsole } from "./support/console.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// J2 · Investigate (fe-ops, 2d7f0aaa). History is real (QuestDB has EARENDIL-001…010 samples);
// alarms are fixtures because the seed configures no limits.
const screen = (scid: number) => missionPath(`fleet/${scid}/investigate`);

const sa1 = { id: "EPS.sa1_current", name: "sa1_current", subsystem: "EPS" } as const;
const thresholds = { red_low: -5.5, yellow_low: -5, yellow_high: 5, red_high: 6 } as const;
const critical = (scid: number): AlarmSpec => ({
  scid,
  point: sa1,
  severity: "critical",
  condition: "red_low",
  value: -6.1,
  thresholds,
  firstCrossedAt: "2026-11-08T22:55:20Z",
  receivedAt: "2026-11-08T22:55:57Z",
});

test.describe("Investigate (J2), alarm on EARENDIL-001 with a sister on 002", () => {
  test.beforeEach(async ({ page }) => {
    await routeAlarms(page, [critical(1), critical(2)]);
    await openConsole(page, screen(1));
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("EARENDIL-001");
  });

  test("B1 states the alarm in words, values and a chart", async ({ page }) => {
    await expect(page.getByText(/critical/i).first()).toBeVisible();
    await expect(page.getByText("EPS · below red limit", { exact: false })).toBeVisible();
    const readouts = page.getByRole("region", { name: "Readouts" });
    await expect(readouts).toContainText(/[−-]6\.1/);
    await expect(readouts).toContainText("Red limit");
    await expect(readouts).toContainText(/[−-]5\.5/);
    await expect(page.getByText(/first crossed 2026-11-08 22:55:20Z/i)).toBeVisible();
    // The chart carries a text equivalent.
    await expect(page.getByRole("img", { name: /sa1_current over/i })).toBeVisible();
    await expect(page.getByRole("radio", { name: "6H" })).toBeChecked();
  });

  test("B4 lists the sister with the same point out of limits", async ({ page }) => {
    await expect(page.getByRole("link", { name: "EARENDIL-002", exact: true })).toBeVisible();
  });

  test("B2 lists the spacecraft's events from the timeline", async ({ page }) => {
    await expect(page.getByRole("heading", { name: "Event log" })).toBeVisible();
    await expect(page.getByText(/event log not available/i)).toHaveCount(0);
    await expect(page.getByRole("link", { name: /full timeline/i })).toBeVisible();
  });

  test("[ and ] step through the plane; the buttons name their target", async ({ page }) => {
    await expect(page.getByRole("link", { name: /next spacecraft.*EARENDIL-002/i })).toBeVisible();
    await page.keyboard.press("]");
    await expect(page).toHaveURL(/\/fleet\/2\/investigate$/);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("EARENDIL-002");
    await page.keyboard.press("[");
    await expect(page).toHaveURL(/\/fleet\/1\/investigate$/);
  });

  test("is accessible", async ({ page }) => {
    await expect(page.getByRole("region", { name: "Readouts" })).toBeVisible();
    await expectAccessible(page);
  });
});

test.describe("Investigate (J2), honest states", () => {
  test("no limits configured: doesn't reassure with a green 'no alarm'", async ({ page }) => {
    await openConsole(page, screen(1));
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("EARENDIL-001");
    await expect(page.getByText(/limits (?:aren't|are not|not) configured/i)).toBeVisible();
  });

  test.describe("history store down", () => {
    test.use({ allowedDiagnostics: allow(/\/history\?.* -> 503/, /status of 503/) });

    test("the chart says history is unavailable; the alarm is still shown", async ({ page }) => {
      await routeAlarms(page, [critical(1)]);
      await page.route(`${missionApi("telemetry/points/*/history")}**`, (route) =>
        route.fulfill(jsonProblem(503, "history_unavailable")),
      );
      await openConsole(page, screen(1));
      await expect(page.getByText("History not available")).toBeVisible();
      await expect(page.getByRole("region", { name: "Readouts" })).toContainText(/[−-]6\.1/);
    });
  });
});
