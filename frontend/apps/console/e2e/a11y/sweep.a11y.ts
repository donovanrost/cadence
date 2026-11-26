import AxeBuilder from "@axe-core/playwright";
import { a11yPersona } from "../support/a11y-projects.ts";
import { missionPath, openConsole } from "../support/console.ts";
import { DEMO } from "../support/env.ts";
import { expect, test } from "../support/fixtures.ts";
import { DEV_ONLY, expectKeyboardPass, waitForScreen } from "../support/keyboard.ts";
import { guardReadOnly } from "../support/read-only.ts";

// #189 inventory: every console screen gets axe (WCAG 2.1 A/AA) and the run-2 keyboard pass, at
// 1440 and 390, as an organization admin (the role that sees the most controls) and as a member
// (an operator: admin-only screens show their 403 state, which must pass too). Each screen
// prints one `A11Y-SWEEP {json}` line, so a CI log can be grouped by cause, then fails softly with
// its findings. Read-only: it loads and Tabs, never acts.
test.beforeEach(({ page }) => guardReadOnly(page));

const org = (rest: string) => `/console/${DEMO.organizationSlug}/${rest}`;
const SPACECRAFT = "spacecraft-earendil-001";
const PROFILE = "profile-earendil-block-1";

const screens: readonly (readonly [string, string])[] = [
  // Ops
  ["Now", missionPath("now")],
  ["Fleet", missionPath("fleet")],
  ["Investigate", missionPath("fleet/1")],
  ["Spacecraft telemetry", missionPath("fleet/1/telemetry")],
  ["Spacecraft uplink", missionPath("fleet/1/uplink")],
  ["Spacecraft passes", missionPath("fleet/1/passes")],
  ["Spacecraft configuration", missionPath("fleet/1/configuration")],
  ["Spacecraft history", missionPath("fleet/1/history")],
  ["Alarms", missionPath("alarms")],
  ["Commands", missionPath("commands")],
  ["Compose", missionPath("commands/new")],
  ["Contacts", missionPath("contacts")],
  ["Contact history", missionPath("contacts/history")],
  ["Contact plan", missionPath("contacts/plan")],
  ["Re-plan", missionPath("contacts/replan")],
  ["Pass review", missionPath("contacts/review")],
  ["Telemetry", missionPath("telemetry")],
  ["Dashboards", missionPath("telemetry/dashboards")],
  ["Dashboard library", missionPath("telemetry/dashboards/library")],
  ["Playlists", missionPath("telemetry/dashboards/playlists")],
  ["New dashboard", missionPath("telemetry/dashboards/new")],
  ["Timeline", missionPath("timeline")],
  // Mission setup
  ["Readiness", missionPath("setup")],
  ["Setup spacecraft", missionPath("setup/spacecraft")],
  ["Spacecraft detail", missionPath(`setup/spacecraft/${SPACECRAFT}`)],
  ["Spacecraft configuration (setup)", missionPath(`setup/spacecraft/${SPACECRAFT}/configuration`)],
  ["New spacecraft", missionPath("setup/spacecraft/new")],
  ["Profiles", missionPath("setup/profiles")],
  ["Profile", missionPath(`setup/profiles/${PROFILE}`)],
  ["Profile history", missionPath(`setup/profiles/${PROFILE}/history`)],
  ["New profile", missionPath("setup/profiles/new")],
  ["Catalog", missionPath("setup/catalog")],
  ["Catalog import", missionPath("setup/catalog/import")],
  ["Changes", missionPath("setup/changes")],
  ["Revisions", missionPath("setup/revisions")],
  ["Comms", missionPath("setup/comms")],
  ["Transports", missionPath("setup/comms/transports")],
  ["Stations", missionPath("setup/stations")],
  ["Station providers", missionPath("setup/stations/providers")],
  ["Contact planning", missionPath("setup/contact-planning")],
  ["Contact planning policy", missionPath("setup/contact-planning/policy")],
  ["Data sources", missionPath("setup/data-sources")],
  ["Apps", missionPath("setup/apps")],
  ["Mission settings", missionPath("setup/settings")],
  // Organization and account
  ["Organization home", org("")],
  ["Missions", org("org/missions")],
  ["New mission", org("org/missions/new")],
  ["People", org("org/people")],
  ["Invite", org("org/people/invite")],
  ["Service identities", org("org/people/services")],
  ["New service identity", org("org/people/services/new")],
  ["Provider accounts", org("org/provider-accounts")],
  ["Organization settings", org("org/settings")],
  ["Organization audit", org("org/audit")],
  ["Account", "/console/account"],
];

interface AxeFinding {
  readonly rule: string;
  readonly impact: string | null;
  readonly nodes: number;
  readonly targets: readonly string[];
}

test.describe("Console sweep · a11y", () => {
  for (const [name, path] of screens) {
    test(name, async ({ page }, info) => {
      await openConsole(page, path);
      await waitForScreen(page);

      let builder = new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]);
      for (const selector of DEV_ONLY) builder = builder.exclude(selector);
      const { violations } = await builder.analyze();
      const axe: AxeFinding[] = violations.map((v) => ({
        rule: v.id,
        impact: v.impact ?? null,
        nodes: v.nodes.length,
        targets: v.nodes.slice(0, 5).map((node) => node.target.join(" ")),
      }));

      let keyboard: string | null = null;
      try {
        await expectKeyboardPass(page);
      } catch (error) {
        keyboard = plain(error instanceof Error ? error.message : String(error));
      }

      const persona = a11yPersona(info);
      const line = { screen: name, path, project: info.project.name, persona, axe, keyboard };
      console.log(`A11Y-SWEEP ${JSON.stringify(line)}`);
      expect.soft(axe, "axe WCAG A/AA violations").toEqual([]);
      expect.soft(keyboard, "keyboard pass").toBeNull();
    });
  }
});

const COLOUR = new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*m`, "g");

/** The assertion message without colour codes, trimmed for one log line. */
function plain(message: string): string {
  return message.replace(COLOUR, "").slice(0, 2000);
}
