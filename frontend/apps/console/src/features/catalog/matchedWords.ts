import { isKnown } from "@/api/index.ts";
import { formatShort } from "@/ui";
import type { MatchedRevision, RunMatch } from "./matchedRevision.ts";

/**
 * ux U99 (#119) words: an import whose content matched a revision that already exists. The words
 * key on `status`; `decision` only supplies who, when and why (U29: neither when it's null).
 * Names are display names only, never ids (U25); the model revision id is Technical details.
 */

type Tone = "info" | "caution";
export type MatchVerdict = Readonly<{ tone: Tone; text: string; rollout: boolean }>;

const when = (iso: string) => formatShort(new Date(iso));
// Unnumbered (U65): "this catalog revision".
const rev = (m: MatchedRevision) =>
  m.revision ? `rev ${m.revision.number}` : "this catalog revision";
const Rev = (m: MatchedRevision) =>
  m.revision ? `Rev ${m.revision.number}` : "This catalog revision";

function opening(m: MatchedRevision): string {
  return m.revision
    ? `This file matches catalog rev ${m.revision.number}, so no new revision was created.`
    : "This file matches a catalog revision that already exists, so no new revision was created.";
}

/** " by Ana R. at 11-15 09:12Z" / " at 11-15 09:12Z" / "" (no decision recorded). */
function byAt(m: MatchedRevision): string {
  if (!m.decision) return "";
  const by = m.decision.by.name ? ` by ${m.decision.by.name}` : "";
  return `${by} at ${when(m.decision.at)}`;
}

/** The waiting line's added sentence, from the server's one answer; null when nothing bars. */
export function cannotApproveLine(m: MatchedRevision): string | null {
  const ca = m.cannot_approve;
  if (!ca) return null;
  const tail = `another org admin has to approve ${rev(m)}.`;
  if (ca.reason === "self") {
    if (!ca.via_service) return `Because you imported this content, ${tail}`;
    return ca.via_service.name
      ? `Because ${ca.via_service.name}, a service identity you're accountable for, imported this content, ${tail}`
      : `Because a service identity you're accountable for imported this content, ${tail}`;
  }
  if (ca.reason === "authors_unknown") {
    const record = "An org admin records who's accountable in People › Service identities.";
    if (!ca.service)
      return `${Rev(m)} can't be approved: Cadence can't tell who imported it, so it can't check that you weren't one of them. Reject it; a corrected catalog imported again becomes a new revision.`;
    return ca.service.name
      ? `${Rev(m)} can't be approved yet: ${ca.service.name} has no one recorded as accountable for it. ${record}`
      : `${Rev(m)} can't be approved yet: the service identity that imported it has no one recorded as accountable for it. ${record}`;
  }
  return `You can't approve ${rev(m)}, so another org admin has to.`;
}

/** The verdict callout in place of "Parsed and validated" (U99 § Where). */
export function matchVerdict(m: MatchedRevision): MatchVerdict {
  const status = m.status;
  if (status === "approved")
    return {
      tone: "info",
      text: `${opening(m)} ${Rev(m)} was approved${byAt(m)}.`,
      rollout: true,
    };
  if (status === "candidate") {
    const why = cannotApproveLine(m);
    const waiting = `${Rev(m)} is waiting for approval in Setup › Catalog.`;
    return {
      tone: "caution",
      text: [opening(m), waiting, why].filter(Boolean).join(" "),
      rollout: false,
    };
  }
  if (status === "rejected") {
    const reason = m.decision?.reason?.trim();
    const quote = reason ? `: “${reason}”` : "";
    // U99: a quoted reason ends the sentence at its closing quote; without one, a full stop.
    const end = quote || ".";
    const which = m.revision
      ? `This file matches catalog rev ${m.revision.number}, which was rejected${byAt(m)}${end}`
      : `This file matches a catalog revision that already exists. It was rejected${byAt(m)}${end}`;
    return {
      tone: "caution",
      text: `${which} No new revision was created. To try again, correct the catalog and import the corrected file. It becomes a new revision.`,
      rollout: false,
    };
  }
  // retired, or a status this console doesn't know: the first sentence only, never a known case.
  return { tone: "info", text: opening(m), rollout: false };
}

/** "Open rev 4" / "Open the revision" (U65's unnumbered case). */
export const openLabel = (m: MatchedRevision) =>
  m.revision ? `Open rev ${m.revision.number}` : "Open the revision";

/** Technical details: the run's result as sent, e.g. "matched existing · rejected". */
export const resultText = (m: MatchedRevision) =>
  `matched existing · ${isKnown(m.status) ? m.status : m.status.unrecognized}`;

/** The runs table's Status tag (U99): never "Succeeded" for a match. */
// U99's "(info)" tags use the tag grammar's neutral state, as U65's APPROVED does.
export function matchTag(m: RunMatch): Readonly<{ label: string; state: "neutral" | "caution" }> {
  const n = m.number === null ? "" : ` rev ${m.number}`;
  return m.status === "rejected"
    ? { label: n ? `Matches rejected${n}` : "Matches a rejected revision", state: "caution" }
    : { label: n ? `Matches${n}` : "Matches an existing revision", state: "neutral" };
}

type DatabaseRef = Readonly<{ id: string; name: string | null }> | null | undefined;
/** " of Bus catalog" / " in another catalog of this mission" (no name: never the id). */
const ofDatabase = (db: DatabaseRef) =>
  db?.name ? ` of ${db.name}` : " in another catalog of this mission";

/** U99 · the same content in another catalog database: this run made its own revision. */
export function otherDatabaseVerdict(
  own: Readonly<{ number: number; database?: DatabaseRef }>,
  m: MatchedRevision,
): MatchVerdict {
  const ownName = `catalog rev ${own.number}${own.database?.name ? ` of ${own.database.name}` : ""}`;
  const other = m.revision
    ? `catalog rev ${m.revision.number}${ofDatabase(m.revision.database)}`
    : `a catalog revision${ofDatabase(null)}`;
  const opening = `Imported as ${ownName}. Its content is the same as ${other}`;
  if (m.status === "approved")
    return {
      tone: "info",
      text: `${opening}, approved${byAt(m)}, so rev ${own.number} is approved too.`,
      rollout: true,
    };
  if (m.status === "candidate") {
    const why = cannotApproveLine(m);
    const text = `${opening}, which is waiting for approval. One approval covers both.`;
    return { tone: "caution", text: [text, why].filter(Boolean).join(" "), rollout: false };
  }
  if (m.status === "rejected") {
    const reason = m.decision?.reason?.trim();
    const quote = reason ? `: “${reason}”` : "";
    return {
      tone: "caution",
      text: `${opening}, which was rejected${byAt(m)}${quote || "."} So rev ${own.number} is rejected too, and spacecraft can't move to it. To try again, correct the catalog and import the corrected file.`,
      rollout: false,
    };
  }
  return { tone: "info", text: `${opening}.`, rollout: false };
}

/** "Open rev 4 of Bus catalog" beside the other-database verdict. */
export const openOtherLabel = (m: MatchedRevision) =>
  m.revision
    ? `Open rev ${m.revision.number}${ofDatabase(m.revision.database)}`
    : "Open the revision";

type Tag = Readonly<{ label: string; state: "neutral" | "caution" }>;
/**
 * The runs table's extra tag (mms-ux 11-19), kept apart from the two numbers: a run with no
 * revision of its own and a match is a same-database match (`matchTag`, in place of the status);
 * a run that made its own revision and matched is the other-database case ("Same as …").
 */
export function sameAsTag(match: RunMatch): Tag | null {
  if (!match.first) return null;
  const name = match.first.database.name;
  return {
    label: name
      ? `Same as ${name} rev ${match.first.number}`
      : "Same as a revision in another catalog",
    state: "neutral",
  };
}

/** U99 · the source-file page when its content matched: in place of "No revisions yet". */
export function noOwnRevision(match: RunMatch): Readonly<{ headline: string; sentence: string }> {
  return {
    headline: "This file made no revision of its own",
    sentence:
      match.number === null
        ? "Its content matches a catalog revision that already exists."
        : `Its content matches catalog rev ${match.number}.`,
  };
}

export const openMatchLabel = (match: RunMatch) =>
  match.number === null ? "Open the revision" : `Open rev ${match.number}`;
