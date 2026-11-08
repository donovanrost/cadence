import { formatCount, plural } from "@/ui";
import type { ClashReport } from "./batch.ts";
import type { ProfileSummary } from "@/features/profiles/index.ts";

export type CheckVerdict = "pass" | "note" | "nogo";
export type BatchCheck = Readonly<{
  key: string;
  label: string;
  sentence: string;
  verdict: CheckVerdict;
}>;

/**
 * Review checks computed in the browser from the directory. The server repeats identity and
 * profile checks when the batch is created (batch:validate), so these never authorize anything.
 */
export function batchChecks(
  report: ClashReport,
  profile: ProfileSummary | null,
): readonly BatchCheck[] {
  const rows = report.rows;
  const n = rows.length;
  const problemRows = rows.filter((r) => r.problems.length > 0).length;
  const planes = [...new Set(rows.flatMap((r) => (r.plane === null ? [] : [r.plane])))].sort(
    (a, b) => a - b,
  );
  const checks: BatchCheck[] = [
    problemRows === 0
      ? {
          key: "identity",
          label: "Identity",
          verdict: "pass",
          sentence: `${plural(n, "name")} and SCIDs are unique in this mission`,
        }
      : {
          key: "identity",
          label: "Identity",
          verdict: "nogo",
          sentence: `${plural(problemRows, "row")} ${problemRows === 1 ? "clashes or has" : "clash or have"} invalid values`,
        },
    profile
      ? {
          key: "profile",
          label: "Profile",
          verdict: "pass",
          sentence: `All rows pin ${profile.name} v${profile.version}`,
        }
      : { key: "profile", label: "Profile", verdict: "nogo", sentence: "No profile chosen" },
  ];
  if (report.missingScid > 0)
    checks.push({
      key: "scid",
      label: "SCID",
      verdict: "nogo",
      sentence: `${plural(report.missingScid, "row")} ${report.missingScid === 1 ? "has" : "have"} no SCID`,
    });
  checks.push(
    planes.length > 0
      ? {
          key: "orbit",
          label: "Orbit",
          verdict: "pass",
          sentence: `Planes ${planes[0]}${planes.length > 1 ? `–${planes.at(-1)}` : ""} will appear on the constellation view`,
        }
      : {
          key: "orbit",
          label: "Orbit",
          verdict: "note",
          sentence: "No planes set. The fleet matrix orders these by SCID until you add them.",
        },
  );
  if (report.missingNorad > 0)
    checks.push({
      key: "norad",
      label: "NORAD id",
      verdict: "note",
      sentence: `${formatCount(report.missingNorad)} of ${formatCount(n)} have no NORAD id yet. Optional now, needed for pass prediction from TLEs.`,
    });
  return checks;
}

export function checksMeta(checks: readonly BatchCheck[]): string {
  const count = (v: CheckVerdict) => checks.filter((c) => c.verdict === v).length;
  return [
    `${count("pass")} passed`,
    count("note") > 0 ? plural(count("note"), "note") : null,
    count("nogo") > 0 ? `${count("nogo")} NO-GO` : null,
  ]
    .filter((p): p is string => p !== null)
    .join(" · ");
}
