import { fileURLToPath } from "node:url";
import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { expect, test } from "./support/fixtures.ts";

// S3 · Catalog import (fe-setup). The real upload creates a catalog revision, so it's opt-in.
const screen = missionPath("setup/catalog/import");
const seedYaml = fileURLToPath(
  new URL("../../../../dev/catalogs/demo_spacecraft.yaml", import.meta.url),
);
const fileInput = (page: import("@playwright/test").Page) => page.locator('input[type="file"]');
const upload = (page: import("@playwright/test").Page) =>
  page.getByRole("button", { name: /upload and validate/i });

test.describe("Catalog import", () => {
  test("the form shows the server's importers and limit; upload waits for a file", async ({
    page,
  }) => {
    await openConsole(page, screen);
    await expect(page.getByText("Cadence YAML Database")).toBeVisible();
    await expect(page.getByText("XTCE 1.3")).toBeVisible();
    await expect(page.getByText(/up to 50 MiB/i)).toBeVisible();
    await expect(fileInput(page)).toHaveAttribute("accept", /\.yaml.*\.xtce|\.xtce.*\.yaml/);
    await expect(upload(page)).toHaveAttribute("aria-disabled", "true");
    await expectAccessible(page);
  });

  test("rejects a file type no importer accepts, before uploading", async ({ page }) => {
    let posted = false;
    page.on("request", (r) => {
      if (r.method() === "POST" && r.url().includes("/catalog/")) posted = true;
    });
    await openConsole(page, screen);
    await fileInput(page).setInputFiles({
      name: "notes.txt",
      mimeType: "text/plain",
      buffer: Buffer.from("not a catalog"),
    });
    await expect(
      // A refusal of the person's pick is an alert (a11y B6, #276).
      page.getByRole("alert").filter({ hasText: "Cadence can't import notes.txt" }),
    ).toBeVisible();
    await expect(upload(page)).toHaveAttribute("aria-disabled", "true");
    await expect(upload(page)).toHaveAccessibleDescription(
      /can't import notes\.txt\. Accepted: \.yaml/,
    );
    await upload(page).click({ force: true });
    expect(posted, "no upload request for a rejected file").toBe(false);
  });

  test("the file picker shows keyboard focus", async ({ page }) => {
    await openConsole(page, screen);
    await expect(page.getByText("XTCE 1.3")).toBeVisible();
    const label = fileInput(page).locator("xpath=ancestor::label[1]");
    const look = () =>
      label.evaluate((el) => {
        const s = getComputedStyle(el);
        return `${s.outlineStyle} ${s.outlineColor} ${s.borderColor} ${s.boxShadow}`;
      });
    const idle = await look();
    await fileInput(page).focus();
    expect(await look(), "focused picker looks different from idle").not.toBe(idle);
  });

  test("uploading the seed YAML creates an import run and shows its validation", async ({
    page,
  }) => {
    test.skip(
      process.env["E2E_MUTATE"] !== "1",
      "creates a catalog revision; run with E2E_MUTATE=1",
    );
    await openConsole(page, screen);
    await fileInput(page).setInputFiles(seedYaml);
    await page.getByRole("textbox", { name: "Revision label" }).fill("QA-E2E re-import");
    await upload(page).click();
    await expect(page).toHaveURL(/\/setup\/catalog\/import\/[^/]+$/);
    await expect(
      page.getByText(/parsed and validated|warnings?|parsing and validating/i).first(),
    ).toBeVisible();
    await expect(page.getByText("Declarations")).toBeVisible({ timeout: 60_000 });
  });
});
