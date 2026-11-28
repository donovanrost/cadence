import type { BrowserContext } from "@playwright/test";
import { missionPath } from "../support/console.ts";
import { expect, test } from "../support/fixtures.ts";
import {
  heapMb,
  installScaleProbes,
  longTasks,
  pushTimes,
  readyAt,
  serveScaledFleet,
} from "../support/scale.ts";
import { median } from "../support/scale-fleet.ts";
import { costOf, recordRequests, type RequestCost } from "../support/requests.ts";
import { addRequestRow, writeRequestTable } from "../support/request-table.ts";

// #176: the console at fleet scale. Each screen loads three times with a 500- and a
// 1,000-spacecraft fleet (the seeded demo's 500, then clones; GET /fleet and the live push both
// scaled), and the median of the three must meet console's budgets. Each screen prints one
// `SCALE {json}` line with its budgets beside the numbers, so a CI log shows them even when a
// budget holds.
//
// The fleet and the passes are scaled (`scaled: ["fleet", "passes"]` in each line; #909: each
// clone gets its seeded craft's passes, served in cursor pages of 500 as the server does). Other
// per-spacecraft reads (Alarms' episodes) still serve the seeded 500, so "Alarms · 1000" means
// the fleet at 1,000, not every read.

/** Console's budgets on a CI runner (#176). 500 is the floor, so meeting them at 1,000 covers it. */
const BUDGET = {
  readyMs: 2_000,
  longestTaskMs: 200,
  pushMs: 100,
  heapMb: 150,
} as const;
const LOADS = 3;
/** A common phone (#868): Fleet's row list, not the table. */
const PHONE = { width: 390, height: 844 } as const;
const SIZES = [500, 1_000] as const;

/** What this spec scales; every SCALE line says so. */
const SCALED = ["fleet", "passes"] as const;

/**
 * `live`: the screen subscribes to the `fleet` push (useFleet without `live: false`), so it gets
 * the scaled snapshot and one full-fleet push is timed. A screen without it has no push cost.
 */
const SCREENS: readonly Readonly<{
  name: string;
  path: string;
  live: boolean;
  /** Only where the screen lays out differently at that width; else the project's desktop. */
  viewport?: Readonly<{ width: number; height: number }>;
}>[] = [
  { name: "Fleet", path: missionPath("fleet"), live: true },
  // #868: below 768px Fleet mounts its phone row list instead of the virtual table (#867).
  { name: "Fleet (phone)", path: missionPath("fleet"), live: true, viewport: PHONE },
  { name: "Now", path: missionPath("now"), live: true },
  { name: "Alarms", path: missionPath("alarms"), live: true },
  { name: "Contacts", path: missionPath("contacts"), live: true },
  // The target picker: Targets · live query (C1), one Add spacecraft option per craft.
  { name: "Compose", path: missionPath("commands/new"), live: true },
];

/** Budget misses known today, each with its follow-up issue (`Screen · size` → issue). */
const KNOWN_MISSES: Readonly<Record<string, string>> = {};

interface Load {
  readonly readyMs: number;
  readonly longestTaskMs: number;
  readonly tasksOver50: number;
  /** null when the screen doesn't subscribe to the live fleet push. */
  readonly pushMs: number | null;
  readonly heapMb: number;
  /** #1037: what the load asked of the server before it was usable. */
  readonly cost: RequestCost;
}

/** Runs in the page (Playwright serialises it), so it can't call anything defined here. */
const pushCount = () => window.__scale?.pushes.length ?? 0;

/** One cold load of `path` with `size` spacecraft, in its own page so routes don't stack. */
async function load(
  context: BrowserContext,
  screen: (typeof SCREENS)[number],
  size: number,
  round: number,
) {
  const page = await context.newPage();
  try {
    if (screen.viewport) await page.setViewportSize(screen.viewport);
    await installScaleProbes(page);
    const recorder = recordRequests(page);
    const fleet = await serveScaledFleet(page, size, (topic) => recorder.join(topic));
    await page.goto(screen.path);
    const readyMs = await readyAt(page);
    const origin = await page.evaluate(() => performance.timeOrigin);
    // A live screen gets the scaled full snapshot first (missing it fails the load: the fixture
    // or the subscription broke); then one push changes every row.
    let pushMs: number | null = null;
    if (screen.live) {
      await page.waitForFunction(() => (window.__scale?.pushes.length ?? 0) > 0, undefined, {
        timeout: 15_000,
      });
      const before = await page.evaluate(pushCount);
      await fleet.pushAll(round + 1);
      await page.waitForFunction((n) => (window.__scale?.pushes.length ?? 0) > n, before);
      pushMs = (await pushTimes(page)).at(-1) ?? null;
    }
    // Let a task the push started finish before reading the totals.
    await page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 500)));
    const tasks = await longTasks(page);
    await recorder.settle();
    const result: Load = {
      cost: costOf(recorder, origin + readyMs),
      readyMs,
      longestTaskMs: Math.max(0, ...tasks),
      tasksOver50: tasks.filter((t) => t > 50).length,
      pushMs,
      heapMb: await heapMb(page),
    };
    return result;
  } finally {
    await page.close();
  }
}

const round1 = (n: number | null) => (n === null ? null : Math.round(n * 10) / 10);
/** A load's numbers to one decimal, for the log line. */
const rounded = (l: Load) => ({
  readyMs: round1(l.readyMs),
  longestTaskMs: round1(l.longestTaskMs),
  tasksOver50: l.tasksOver50,
  pushMs: round1(l.pushMs),
  heapMb: round1(l.heapMb),
  requests: l.cost.requests,
  joins: l.cost.joins,
  serialDepth: l.cost.serialDepth,
  bytes: l.cost.bytes,
});

test.describe("Console at fleet scale", () => {
  test.afterAll(() => writeRequestTable());
  for (const size of SIZES) {
    for (const screen of SCREENS) {
      const label = `${screen.name} · ${size}`;
      test(label, async ({ context }) => {
        test.setTimeout(180_000);
        const issue = KNOWN_MISSES[label];
        if (issue) test.fail(true, `misses a #176 budget today; follow-up ${issue}`);

        const loads: Load[] = [];
        for (let round = 0; round < LOADS; round++)
          loads.push(await load(context, screen, size, round));
        const pushes = loads.flatMap((l) => (l.pushMs === null ? [] : [l.pushMs]));
        // The request shape is the first load's (a cold cache); the counts are the medians.
        const first = loads[0]?.cost;
        if (!first) throw new Error("no load ran");
        const result: Load = {
          cost: {
            ...first,
            requests: median(loads.map((l) => l.cost.requests)),
            joins: median(loads.map((l) => l.cost.joins)),
            serialDepth: median(loads.map((l) => l.cost.serialDepth)),
            bytes: median(loads.map((l) => l.cost.bytes)),
          },
          readyMs: median(loads.map((l) => l.readyMs)),
          longestTaskMs: median(loads.map((l) => l.longestTaskMs)),
          tasksOver50: median(loads.map((l) => l.tasksOver50)),
          pushMs: pushes.length ? median(pushes) : null,
          heapMb: median(loads.map((l) => l.heapMb)),
        };
        console.log(
          `SCALE ${JSON.stringify({
            screen: screen.name,
            size,
            scaled: SCALED,
            ...rounded(result),
            budget: BUDGET,
            loads: loads.map(rounded),
            chain: first.chain,
            repeated: first.repeated,
          })}`,
        );
        addRequestRow({ screen: screen.name, size, readyMs: result.readyMs, cost: result.cost });

        expect
          .soft(result.readyMs, "screen ready (ms, median)")
          .toBeLessThanOrEqual(BUDGET.readyMs);
        expect
          .soft(result.longestTaskMs, "longest task (ms, median)")
          .toBeLessThanOrEqual(BUDGET.longestTaskMs);
        if (result.pushMs !== null)
          expect
            .soft(result.pushMs, "full-fleet push applied (ms, median)")
            .toBeLessThanOrEqual(BUDGET.pushMs);
        expect
          .soft(result.heapMb, "JS heap after GC (MB, median)")
          .toBeLessThanOrEqual(BUDGET.heapMb);
      });
    }
  }
});
