import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { RequestCost } from "./requests.ts";

/**
 * #1037: the per-screen request table, written next to the run's other evidence
 * (`test-results/`, uploaded by console-e2e). The CTO's bar is reasonableness, not tuning: a
 * finding is a screen that reads per spacecraft (an endpoint repeated per row, or a request count
 * that grows from 500 to 1,000 craft other than by cursor pages) or one slower than about 1 s to
 * usable at 500. Serial depth over 2 and cursor-page walks are noted, not findings: pages grow with
 * the data a fleet-wide read returns, not one read per spacecraft.
 */
export type TableRow = Readonly<{
  screen: string;
  size: number;
  readyMs: number;
  cost: RequestCost;
}>;

const USABLE_MS = 1_000;

export function findingsOf(rows: readonly TableRow[]): string[] {
  const out: string[] = [];
  for (const r of rows.filter((x) => x.size === 500)) {
    for (const rep of r.cost.repeated)
      out.push(`${r.screen}: reads ${rep.endpoint} once per row (${rep.count} times at 500 craft)`);
    if (r.readyMs > USABLE_MS)
      out.push(`${r.screen}: ${Math.round(r.readyMs)} ms to usable at 500 craft (over ~1 s)`);
    const big = rows.find((x) => x.screen === r.screen && x.size === 1_000);
    const unpaged = (c: RequestCost) => c.requests - c.pages.reduce((n, p) => n + p.count, 0);
    if (big && unpaged(big.cost) > unpaged(r.cost))
      out.push(
        `${r.screen}: ${r.cost.requests} requests at 500 craft, ${big.cost.requests} at 1,000 (grows with the fleet)`,
      );
  }
  return out;
}

export function tableMarkdown(rows: readonly TableRow[]): string {
  const head = [
    "| Screen | Craft | Requests | Joins | Serial depth | Response KB | Ready (ms) |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
  ];
  const lines = rows.map(
    (r) =>
      `| ${r.screen} | ${r.size} | ${r.cost.requests} | ${r.cost.joins} | ${r.cost.serialDepth} | ${Math.round(r.cost.bytes / 1024)} | ${Math.round(r.readyMs)} |`,
  );
  const deep = rows
    .filter((r) => r.size === 500 && r.cost.serialDepth > 2)
    .map((r) => `- ${r.screen} (depth ${r.cost.serialDepth}): ${r.cost.chain.join(" → ")}`);
  const findings = findingsOf(rows).map((f) => `- ${f}`);
  const paged = rows.flatMap((r) =>
    r.cost.pages.map((p) => `- ${r.screen} at ${r.size}: ${p.endpoint}, ${p.count + 1} pages`),
  );
  return [
    ...head,
    ...lines,
    "",
    "Findings (per-spacecraft reads, or over ~1 s to usable at 500):",
    ...(findings.length ? findings : ["- none"]),
    "",
    "Noted, not findings (serial depth over 2 at 500):",
    ...(deep.length ? deep : ["- none"]),
    "",
    "Noted, not findings (cursor-paged fleet-wide reads, which grow with the data):",
    ...(paged.length ? paged : ["- none"]),
    "",
  ].join("\n");
}

const DIR = "test-results";
const ROWS = join(DIR, "scale-requests.jsonl");

/**
 * One row per finished screen, appended at once: a failed test restarts the worker, so rows kept
 * in memory would be lost before the table is written.
 */
export function addRequestRow(row: TableRow): void {
  mkdirSync(DIR, { recursive: true });
  appendFileSync(ROWS, `${JSON.stringify(row)}\n`);
}

/** The table from every row this run appended (`scale-requests.md`, beside the rows). */
export function writeRequestTable(): void {
  if (!existsSync(ROWS)) return;
  const rows = readFileSync(ROWS, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line): TableRow => JSON.parse(line) as TableRow);
  writeFileSync(join(DIR, "scale-requests.md"), tableMarkdown(rows));
}
