import type { Page } from "@playwright/test";
import { expectAccessible } from "./support/accessibility.ts";
import { jsonData, jsonProblem, missionApi, missionPath, openConsole } from "./support/console.ts";
import { DEMO, storageStateFor } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// S1 · Readiness (fe-setup, 46f6c31c). Contract: docs/apogee/plans/setup-shapes.md §R.
// The endpoint isn't built yet, so the real server returns 404; the layout is checked with fixtures.
const screen = missionPath("setup");
const readiness = missionApi("readiness");

const area = (key: string, status: string, count: number | null, unit: string, detail: string) => ({
  key,
  status,
  count,
  unit,
  secondary_count: null,
  secondary_unit: null,
  detail,
});

const finding = (
  id: string,
  severity: string,
  title: string,
  affected: number,
  fix: { kind: string; id: string | null; label: string | null } | null,
) => ({
  id,
  severity,
  cause: id,
  title,
  body: `${title}. QA fixture body.`,
  affected_count: affected,
  fix,
});

// Findings deliberately out of order: the screen must sort blockers first.
const withBlockers = {
  evaluated_at: "2026-11-08T22:00:00Z",
  verdict: { blocker: 2, caution: 1, stale: 1, not_set_up: 1, optional: 1 },
  areas: [
    {
      ...area("fleet", "ready", 500, "spacecraft", "Every spacecraft has a SCID and a profile"),
      secondary_count: 1,
      secondary_unit: "profiles",
    },
    area("catalog", "caution", 1, "catalog", "One revision has warnings"),
    area("comms", "blocker", 12, "spacecraft without a rule", "12 spacecraft can't be contacted"),
    area("stations", "stale", 10, "sites", "Inventory last synced 3 days ago"),
    area("data_sources", "not_set_up", 0, "sources", "No archive configured"),
    area("apps", "unknown", null, "apps", "App status couldn't be read"),
  ],
  findings: [
    finding("apps.optional", "optional", "Install the pass-report app", 1, {
      kind: "app",
      id: "pass-report",
      label: null,
    }),
    finding("catalog.warnings", "caution", "Catalog revision has 3 warnings", 3, {
      kind: "catalog",
      id: null,
      label: null,
    }),
    finding("routing.missing", "blocker", "12 spacecraft have no routing rule", 12, {
      kind: "profile",
      id: "type_qa",
      label: null,
    }),
    finding("stations.stale", "stale", "Station inventory is stale", 10, null),
    finding("sources.none", "not_set_up", "No data source", 1, {
      kind: "data_source",
      id: "source_qa",
      label: "Add a source",
    }),
    finding("fleet.no_scid", "blocker", "3 spacecraft have no SCID", 3, {
      kind: "spacecraft_list",
      id: null,
      label: null,
    }),
  ],
  recent_changes: null,
  permissions: ["catalog.import"],
};

const allReady = {
  evaluated_at: "2026-11-08T22:00:00Z",
  verdict: { blocker: 0, caution: 0, stale: 0, not_set_up: 0, optional: 0 },
  areas: ["fleet", "catalog", "comms", "stations", "data_sources", "apps"].map((key) =>
    area(key, "ready", 1, "item", "Ready"),
  ),
  findings: [],
  recent_changes: [
    {
      at: "2026-11-08T21:00:00Z",
      kind: "profile",
      version_label: "v4",
      summary: "Edited Earendil Block 1",
      actor: { name: "QA Org Admin" },
    },
  ],
  permissions: ["catalog.import"],
};

async function withReadiness(page: Page, data: unknown) {
  await page.route(readiness, (route) => route.fulfill(jsonData(data)));
  await openConsole(page, screen);
}

const areas = (page: Page) => page.getByRole("region", { name: "Readiness areas" });
const findings = (page: Page) =>
  page
    .locator("ul")
    .filter({ has: page.getByRole("listitem") })
    .last();

test.describe("setup readiness", () => {
  test.describe("against the real server", () => {
    test.use({ allowedDiagnostics: allow(/\/readiness -> 404/, /status of 404/) });

    test("shows the server's verdict, or says readiness is unavailable; never invents one", async ({
      page,
    }) => {
      const api = await page.request.get(`/api/v1/missions/${DEMO.missionId}/readiness`);
      await openConsole(page, screen);
      const h1 = page.getByRole("heading", { level: 1 });
      if (api.status() === 404) {
        await expect(h1).toHaveText(/readiness not available/i);
        await expect(page.getByText("Readiness checks not available yet")).toBeVisible();
        await expect(page.getByRole("button", { name: "Check again" })).toBeVisible();
      } else {
        expect(api.status(), "readiness endpoint").toBe(200);
        // qa #6: the served verdict must decode; a decode failure also shows "not available".
        await expect(h1).not.toHaveText(/not available|loading/i);
        await expect(
          page.getByRole("region", { name: "Readiness areas" }).getByRole("link"),
        ).toHaveCount(6);
      }
      await expectAccessible(page);
    });
  });

  test("blockers: verdict, six areas in contract order, findings sorted blocker-first", async ({
    page,
  }) => {
    await withReadiness(page, withBlockers);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/2 blockers/i);
    await expect(page.getByText("1 caution, 1 stale, 1 not set up, 1 suggestion")).toBeVisible();
    await expect(page.getByText("2 blockers stop commanding or contacts.")).toBeVisible();

    await expect(areas(page).getByRole("link")).toHaveText([
      /fleet/i,
      /catalog/i,
      /comms & routing/i,
      /ground stations/i,
      /data sources/i,
      /apps/i,
    ]);
    // Status is carried by words, not only color; "unknown" never reads as ready.
    for (const word of ["Ready", "Caution", "Blocker", "Stale", "Not set up", "Unknown"]) {
      await expect(areas(page).getByText(word, { exact: true })).toBeVisible();
    }
    await expect(areas(page).getByText("Ready", { exact: true })).toHaveCount(1);

    const titles = await findings(page).getByRole("listitem").allInnerTexts();
    const order = [
      "no routing rule",
      "no SCID",
      "3 warnings",
      "inventory is stale",
      "No data source",
      "pass-report",
    ];
    order.forEach((fragment, index) =>
      expect(titles[index], `finding ${index}`).toContain(fragment),
    );
    await expect(findings(page).getByText(/^Optional · /)).toHaveCount(1);

    // Each finding offers at most one fix; server labels override the default verb.
    await expect(page.getByRole("link", { name: "Open profile" })).toHaveCount(1);
    await expect(page.getByRole("link", { name: "Add a source" })).toHaveCount(1);
    // R2 reads real configuration revisions (d03eea14), not the readiness fixture.
    await expect(page.getByText("Recent changes").first()).toBeVisible();

    await expectAccessible(page);
  });

  test("all ready: says so plainly and shows recent changes when the server has them", async ({
    page,
  }) => {
    await withReadiness(page, allReady);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/ready for operations/i);
    await expect(page.getByText(/No blockers\..*No suggestions either\./)).toBeVisible();
    await expect(page.getByText("Recent changes")).toBeVisible();
    await expect(
      page.getByRole("listitem").filter({ hasText: "Edited Earendil Block 1" }),
    ).toBeVisible();
    await expectAccessible(page);
  });

  test("area names navigate to their setup page", async ({ page }) => {
    await withReadiness(page, withBlockers);
    await areas(page).getByRole("link", { name: /fleet/i }).click();
    await expect(page).toHaveURL(/\/setup\/spacecraft$/);
  });

  test.describe("when the readiness read fails", () => {
    test.use({ allowedDiagnostics: allow(/\/readiness -> 500/, /status of 500/) });

    test("shows a retryable error, not a verdict", async ({ page }) => {
      await page.route(readiness, (route) => route.fulfill(jsonProblem(500, "internal_error")));
      await openConsole(page, screen);
      await expect(page.getByRole("button", { name: "Retry" })).toBeVisible();
      await expect(page.getByText(/ready for operations/i)).toHaveCount(0);
    });
  });
});

test.describe("setup readiness, organization member", () => {
  test.use({ storageState: storageStateFor("operator") });

  // #1160: both are any mission operator's (staging is reviewed; an import needs an admin's approval).
  test("is offered Add spacecraft and Import catalog, from the server's own checks", async ({
    page,
  }) => {
    await openConsole(page, screen);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByRole("link", { name: "Add spacecraft" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Import catalog" })).toBeVisible();
  });
});
