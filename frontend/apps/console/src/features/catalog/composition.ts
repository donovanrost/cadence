import { actorKinds } from "@/api/entities.ts";
import { decoders as d, knownText, orNull, type Decoded } from "@/api";

/**
 * D2 (#543, #581): the composition behind a revision or a pin, and U109's words for it (#538,
 * readers first). Until D4 every composition has one catalog, and every screen reads exactly as
 * today: the composed forms show only when `imported_layers` has more than one entry.
 */
export const compositionActor = d.object({
  kind: orNull(knownText(actorKinds)),
  id: orNull(d.string),
  name: orNull(d.string),
  /** A system actor's runner (#513), by the member rule; null when not a member. */
  run_by: d.optional(d.nullable(d.object({ id: orNull(d.string), name: orNull(d.string) }))),
});
export type CompositionActor = Decoded<typeof compositionActor>;

const layer = d.object({
  layer_id: d.token,
  mount: d.string,
  /**
   * D4 (#545): the layer's content digest, for the composed header (name, mount, digest). Readers
   * first: absent until mission-model's composition_views change (12-05), then always sent.
   */
  content_sha256: d.optional(d.string),
  catalog_revision: d.nullable(
    d.object({
      id: d.token,
      number: d.integer,
      database: d.object({ id: d.token, name: d.nullable(d.string) }),
    }),
  ),
});
export type CompositionLayer = Decoded<typeof layer>;

export const compositionReader = d.object({
  composition_id: d.token,
  number: d.nullable(d.integer),
  imported_layers: d.array(layer, 64),
  created_by: d.nullable(compositionActor),
  created_at: d.timestamp,
});
export type Composition = Decoded<typeof compositionReader>;

/** The optional key every D2 read carries: absent on a server before D2, null when none names it. */
export const compositionKey = d.optional(d.nullable(compositionReader));

/** More than one catalog: only then does a screen say "composition" (U109). */
export const isComposed = (c: Composition | null | undefined): c is Composition =>
  (c?.imported_layers.length ?? 0) > 1;

/** "composition 3" in a sentence; "this composition" with no number (U109; never an id). */
export const compositionInSentence = (c: Composition) =>
  c.number === null ? "this composition" : `composition ${c.number}`;
/** `Composition 3` where it stands alone, or null with no number (then Made of stands alone). */
export const compositionTitle = (c: Composition) =>
  c.number === null ? null : `Composition ${c.number}`;

const MADE_OF_SHOWN = 3;
const placeOf = (mount: string) => mount.split("/").filter(Boolean).at(-1) ?? "";

/**
 * Made of (U109): each catalog by its database's name and revision, in the server's order. The
 * place (the mount's last part) is added only when the name doesn't tell two apart, or there's no
 * name; the catalog at '/' never gets one. A catalog the server can't name: "an imported catalog".
 * Up to three, then "and N more" (the caller offers Show all).
 */
export function madeOfParts(c: Composition): readonly string[] {
  const names = c.imported_layers.map((l) => l.catalog_revision?.database.name ?? null);
  return c.imported_layers.map((l, i) => {
    const name = names[i];
    const shared = name !== null && names.filter((n) => n === name).length > 1;
    // compared-as-text: a mount is a path (an open set); '/' is the root, which never gets a place
    const place = l.mount !== "/" && (name === null || shared) ? ` (${placeOf(l.mount)})` : "";
    if (!l.catalog_revision) return `an imported catalog${place}`;
    const lead = name ? `${name} catalog rev` : "catalog rev";
    return `${lead} ${l.catalog_revision.number}${place}`;
  });
}

export function madeOfLine(c: Composition, all = false): string {
  const parts = madeOfParts(c);
  const shown = all ? parts : parts.slice(0, MADE_OF_SHOWN);
  const more = parts.length - shown.length;
  return `Made of: ${shown.join(" · ")}${more > 0 ? ` and ${more} more` : ""}`;
}

/**
 * U103's actor forms in a sentence: a person by name; a service with "(a service identity)";
 * the system as "Cadence, run by Mira K." ("Cadence, run by a person" when the runner isn't
 * named; plain "Cadence" when nobody ran it). Null for a person with no name (the clause drops).
 */
export function actorInSentence(a: CompositionActor | null): string | null {
  if (!a) return null;
  if (a.kind === "service") return a.name ? `${a.name} (a service identity)` : "a service identity";
  if (a.kind === "system") {
    if (a.run_by === undefined || a.run_by === null) return "Cadence";
    return `Cadence, run by ${a.run_by.name ?? "a person"}`;
  }
  return a.name;
}
