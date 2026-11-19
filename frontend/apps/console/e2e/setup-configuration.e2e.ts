import type { Page, TestInfo } from "@playwright/test";
import { snapshotWire } from "./support/configuration.ts";
import { expectAccessible } from "./support/accessibility.ts";
import { jsonData, jsonProblem, missionPath, openConsole } from "./support/console.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// (B) Setup › Spacecraft › Configuration (fe-ops; MM&S owns the workspace, ux U94/U98/U101).
// Screens for ux's review: each state is attached to the HTML report at desktop and 390 wide.
// The workspace read is answered from the feature's wire fixtures, so every state is
// deterministic; nothing is written. qa runs it against :4011 in a slot, never during a pass
// cluster (docs/apogee/qa/runbook.md); #242 brings these specs into CI.

const CRAFT = "spacecraft-earendil-001";
// The read and anything under it (the packets route too; the read side never calls it).
const WORKSPACE = `**/spacecraft/${CRAFT}/configuration/workspace**`;
const screenPath = (section: string) =>
  missionPath(`setup/spacecraft/${CRAFT}/configuration/${section}`);
const craft = { spacecraft_id: CRAFT, name: "EARENDIL-001", scid: 1 };

/** Full-page screenshots at desktop and phone width, attached for ux (U94 review). */
async function attachScreens(page: Page, testInfo: TestInfo, name: string) {
  for (const [label, width, height] of [
    ["desktop", 1440, 900],
    ["390", 390, 844],
  ] as const) {
    await page.setViewportSize({ width, height });
    await testInfo.attach(`${name}-${label}`, {
      body: await page.screenshot({ fullPage: true }),
      contentType: "image/png",
    });
  }
}

async function answerWorkspace(page: Page, over: Record<string, unknown> = {}) {
  await page.route(WORKSPACE, (route) =>
    route.fulfill(jsonData(snapshotWire({ ...craft, fleet: [], fleet_total: 1, ...over }))),
  );
}

test.describe("Setup spacecraft configuration (B)", () => {
  test("overview: settings and the switches, set by a change set and never set", async ({
    page,
  }, testInfo) => {
    await answerWorkspace(page);
    await openConsole(page, screenPath("overview"));
    await expect(page.getByText("On · set by r7.")).toBeVisible();
    await expect(
      page.getByText(/^Off · no change set has turned it on yet\. Turn it on in EARENDIL-001's/),
    ).toBeVisible();
    await expectAccessible(page);
    await attachScreens(page, testInfo, "overview");
  });

  test("a switch set through Setup › Changes, with no revision", async ({ page }, testInfo) => {
    await answerWorkspace(page, {
      switches: {
        telemetry_enabled: { value: true, set: true, revision: null },
        commanding_enabled: { value: true, set: true, revision: null },
      },
    });
    await openConsole(page, screenPath("overview"));
    await expect(page.getByText("On · set through Setup › Changes.").first()).toBeVisible();
    await attachScreens(page, testInfo, "switches-through-changes");
  });

  test("Changes: what differs from the active version", async ({ page }, testInfo) => {
    await answerWorkspace(page, { section: "changes" });
    await openConsole(page, screenPath("changes"));
    await expect(page.getByRole("table")).toBeVisible();
    await expectAccessible(page);
    await attachScreens(page, testInfo, "changes");
  });

  test("not set up: nothing is active yet, with the steps", async ({ page }, testInfo) => {
    await answerWorkspace(page, { active: null, saved_version: null, review: null });
    await openConsole(page, screenPath("overview"));
    await expect(
      page.getByText(/^Nothing runs for EARENDIL-001 until its configuration is activated/),
    ).toBeVisible();
    await attachScreens(page, testInfo, "not-set-up");
  });

  // The read's own intended refusals, and nothing else (qa's 11-19 run: the diagnostics fixture
  // flags every 4xx unless the test allows it).
  test.describe("the read refused", () => {
    test.use({
      allowedDiagnostics: allow(/configuration\/workspace\S* -> 40[34]/, /status of 40[34]/),
    });

    test("a craft that isn't on this mission (404) says so, as a state", async ({
      page,
    }, testInfo) => {
      await page.route(WORKSPACE, (route) =>
        route.fulfill(jsonProblem(404, "spacecraft_not_found")),
      );
      await openConsole(page, screenPath("overview"));
      await expect(page.getByText("This spacecraft isn't on this mission.")).toBeVisible();
      await attachScreens(page, testInfo, "not-on-mission");
    });

    test("can't view: a 403 on the read says so, with who grants access (U98)", async ({
      page,
    }, testInfo) => {
      await page.route(WORKSPACE, (route) => route.fulfill(jsonProblem(403, "forbidden")));
      await openConsole(page, screenPath("overview"));
      await expect(
        page.getByText(
          "You can't view this spacecraft's configuration. Ask a mission admin or an org admin for access.",
        ),
      ).toBeVisible();
      await expect(page.getByRole("button", { name: /retry/i })).toHaveCount(0);
      await expectAccessible(page);
      await attachScreens(page, testInfo, "cant-view");
    });
  });
});
