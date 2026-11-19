import { expect, type Locator, type Page, type Request } from "@playwright/test";

interface SheetCheck {
  /** The control that opens the sheet. It's focused and pressed with Enter, as from the keyboard. */
  readonly opener: Locator;
  /**
   * A menu item, when the opener is a menu button (the viewer's More menu, a row's Actions): the
   * opener is pressed, then this item. A5 still expects focus back on the opener.
   */
  readonly via?: Locator;
  /** The sheet's title: its accessible name (A2). */
  readonly name: string | RegExp;
  /** Where focus must land on open (A1): the first field, or the safe button of a danger sheet. */
  readonly initialFocus?: Locator;
  /**
   * The non-modal side sheet (A3's exception: Dashboards edit's Widget sheet): Tab may leave it,
   * and it must not be aria-modal. Default false: Tab and Shift+Tab stay inside.
   */
  readonly nonModal?: boolean;
  /** The safe button's name (`Cancel`, `Keep contact`): also checks A5 after it, not only after Esc. */
  readonly cancel?: string | RegExp;
}

/**
 * The a11y checklist's A1–A5 for one sheet or dialog, read-only: it opens the sheet, Tabs, and
 * closes it with Esc (and the safe button, when given), never the action. Fails if anything other
 * than a read (GET/HEAD) leaves the page meanwhile, which would mean closing acted (A4).
 *   A1 focus starts inside (on `initialFocus` when given) · A2 named by its title ·
 *   A3 Tab and Shift+Tab stay inside · A4 Esc closes without acting · A5 focus returns to the opener.
 */
export async function expectSheetChecks(page: Page, check: SheetCheck): Promise<void> {
  const writes: string[] = [];
  const onRequest = (request: Request) => {
    if (!["GET", "HEAD", "OPTIONS"].includes(request.method()))
      writes.push(`${request.method()} ${request.url()}`);
  };
  page.on("request", onRequest);
  try {
    const sheet = await open(page, check);
    await expectTrapped(page, sheet, check.nonModal === true);
    await page.keyboard.press("Escape");
    await expect(sheet, "A4: Esc closes it").toBeHidden();
    await expect(check.opener, "A5: focus returns to the opener after Esc").toBeFocused();

    if (check.cancel !== undefined) {
      const again = await open(page, check);
      await again.getByRole("button", { name: check.cancel }).click();
      await expect(again, "the safe button closes it").toBeHidden();
      await expect(
        check.opener,
        "A5: focus returns to the opener after the safe button",
      ).toBeFocused();
    }
  } finally {
    page.off("request", onRequest);
  }
  expect(writes, "A4: closing the sheet sent no writes").toEqual([]);
}

async function open(page: Page, check: SheetCheck): Promise<Locator> {
  await check.opener.focus();
  await page.keyboard.press("Enter");
  if (check.via) {
    await expect(check.via, "the menu shows the item").toBeVisible();
    await check.via.focus();
    await page.keyboard.press("Enter");
  }
  const sheet = page.getByRole("dialog", {
    name: check.name,
    exact: typeof check.name === "string",
  });
  await expect(sheet, "A2: a dialog named by its title").toBeVisible();
  const inside = () => sheet.evaluate((d) => d.contains(document.activeElement));
  await expect.poll(inside, { message: "A1: focus starts inside the sheet" }).toBe(true);
  if (check.initialFocus) await expect(check.initialFocus, "A1: focus starts here").toBeFocused();
  return sheet;
}

/** A3: as many Tabs (then Shift+Tabs) as the sheet has stops, plus two; focus never leaves. */
async function expectTrapped(page: Page, sheet: Locator, nonModal: boolean): Promise<void> {
  if (nonModal) {
    await expect(sheet, "A3 exception: a non-modal sheet isn't aria-modal").not.toHaveAttribute(
      "aria-modal",
      "true",
    );
    return;
  }
  const stops = await sheet.evaluate(
    (d) =>
      d.querySelectorAll(
        'a[href], button:not([disabled]), input:not([disabled]):not([type=hidden]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      ).length,
  );
  // A native showModal() dialog lets Tab pass from its last control to the browser's own UI,
  // where the page sees <body> focused; that isn't the page behind, so it passes. Only a native
  // modal <dialog> gets that pass: <body> focused from a custom role=dialog means focus was lost
  // (an A5 failure, fe-ops #433). Focus on any element outside the sheet fails.
  for (const key of ["Tab", "Shift+Tab"]) {
    for (let i = 0; i < stops + 2; i++) {
      await page.keyboard.press(key);
      const where = await sheet.evaluate((d) => {
        const active = document.activeElement;
        if (active === null || active === document.body)
          return d instanceof HTMLDialogElement && d.matches(":modal") ? "browser" : "<body> (lost)";
        return d.contains(active)
          ? "inside"
          : `${active.tagName.toLowerCase()} "${(active.textContent ?? "").trim().slice(0, 40)}"`;
      });
      expect(
        ["inside", "browser"],
        `A3: ${key} ×${i + 1} reached ${where} behind the sheet`,
      ).toContain(where);
    }
  }
}
