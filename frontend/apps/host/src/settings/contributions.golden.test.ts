import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import { settingsSections } from "./contributions";

/**
 * The host half of the settings-sections guard: the host's contributions are exactly the golden's
 * `host: true` sections, with the server's owner and scopes. The server and console half is
 * apps/cadence_web/test/cadence_web/settings_sections_golden_test.exs. §11c C deletes
 * SettingsPage.vue: drop these contributions, this test, and the golden's `host` flags together.
 */
type GoldenSection = { key: string; owner: string; scopes: string[]; host: boolean };

const golden = (
  JSON.parse(
    readFileSync(
      resolve(
        dirname(fileURLToPath(import.meta.url)),
        "../../../../../apps/cadence_web/test/support/golden/settings_sections.json",
      ),
      "utf8",
    ),
  ) as { sections: GoldenSection[] }
).sections.filter((section) => section.host);

test("the host's settings contributions are the golden's host sections", () => {
  expect([...settingsSections.ids].sort()).toEqual(golden.map((section) => section.key).sort());
});

test.each(golden)("$key matches the golden's owner and scopes", async (section) => {
  const contribution = await settingsSections.load(section.key);
  expect(contribution.scopes).toEqual(section.scopes);
  expect(contribution.owner.kind === "host" ? "cadence" : contribution.owner.applicationKey).toBe(
    section.owner,
  );
});
