import { guardReadOnly } from "../support/read-only.ts";
import { expectAccessible } from "../support/accessibility.ts";
import { missionPath, openConsole } from "../support/console.ts";
import { DEMO } from "../support/env.ts";
import { expect, test } from "../support/fixtures.ts";
import { DEV_ONLY, expectKeyboardPass, waitForScreen } from "../support/keyboard.ts";

// qa's :4011 condition: only reads reach the server (support/read-only.ts).
test.beforeEach(({ page }) => guardReadOnly(page));

// #928: while a change set is in review, Setup shows the staged-changes bar (a named region) with
// its Open review link. The CI seed applies its set, so the sweep never sees that state on its
// own: here GET …/config answers with the real state plus a set held in review, client-side only,
// so no other spec's staging is frozen. Every Setup screen must still pass axe and the keyboard
// pass (B1), with the bar a landmark of its own.
const SETUP_SCREENS: readonly (readonly [string, string])[] = [
  ["Readiness", missionPath("setup")],
  ["Setup spacecraft", missionPath("setup/spacecraft")],
  ["Profiles", missionPath("setup/profiles")],
  ["Catalog", missionPath("setup/catalog")],
  ["Revisions", missionPath("setup/revisions")],
  ["Comms", missionPath("setup/comms")],
  ["Stations", missionPath("setup/stations")],
  ["Contact planning", missionPath("setup/contact-planning")],
];

const person = { id: "user_review_check", kind: "user", name: "QA Org Admin" };
/** A seeded spacecraft (dev/reflect_orbital_demo.exs), as the sweep uses. */
const SPACECRAFT = "spacecraft-earendil-001";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** One staged rename, sent for review by someone else, so the viewer may review it. */
function inReview(spacecraftId: string) {
  const at = new Date().toISOString();
  return {
    applied_revision: null,
    approval_required: true,
    authors: [person],
    base_revision: 1,
    changes: [
      {
        author: person,
        id: "config_change_review_check",
        ops: [
          {
            action: "update",
            entity_id: spacecraftId,
            id: "config_op_review_check",
            kind: "spacecraft",
            paths: ["display_name"],
            payload: { changes: [{ path: "display_name", value: "EARENDIL-REVIEW" }] },
          },
        ],
        source: {},
        staged_at: at,
        state: "staged",
        summary: "Rename for the review check",
      },
    ],
    failure: null,
    id: "change_set_review_check",
    legacy_conversion: null,
    opened_at: at,
    opened_by: person,
    reason: "Held in review for the a11y check (#928)",
    reviews: [],
    staged_count: 1,
    state: "in_review",
    submitted_at: at,
    submitted_by: person,
    version: 2,
    viewer: { can_review: true, review_blocked_reason: null },
    withdrawn: [],
  };
}

test.describe("Setup with a change set in review · a11y", () => {
  test.beforeEach(async ({ page }) => {
    await page.route(new RegExp(`/api/v1/missions/${DEMO.missionId}/config$`), async (route) => {
      if (route.request().method() !== "GET") return route.fallback();
      const body: unknown = await (await route.fetch()).json();
      const data = isRecord(body) && isRecord(body["data"]) ? body["data"] : {};
      await route.fulfill({ json: { data: { ...data, change_set: inReview(SPACECRAFT) } } });
    });
  });

  for (const [name, path] of SETUP_SCREENS) {
    test(`${name}: the staged-changes bar is a named landmark; axe and the keyboard pass`, async ({
      page,
    }) => {
      await openConsole(page, path);
      await waitForScreen(page);
      const bar = page.getByRole("region", { name: "Staged changes" });
      await expect(bar).toBeVisible();
      await expectAccessible(page, { exclude: DEV_ONLY });
      // The pass walks at most 120 stops, so on a long list it can end before the bar; the bar's
      // name is checked above, and a revisit of an unnamed run would fail the pass (#928).
      await expectKeyboardPass(page);
    });
  }
});
