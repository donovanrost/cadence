import { decoders as d, type Decoded } from "@/api";
import { formatHourMinute } from "@/ui";

/**
 * A pass's predicted geometry (#892, #895): contacts, Book a pass offers and a plan's alternatives
 * carry it (contacts.md § Elevation, scheduling.md S4). The console only shows it: no flight
 * dynamics in the browser.
 */
export const elevationSources = ["provider", "predicted"] as const;

/** On a contact: the provider's elevation when it reports one, else the matched predicted pass's. */
export const passGeometry = {
  max_elevation_deg: d.nullable(d.number),
  // null exactly when max_elevation_deg is.
  elevation_source: d.nullable(d.known(elevationSources)),
  predicted_pass_id: d.nullable(d.token),
};

/**
 * On an offer or an alternative, also the predicted TCA and whether prediction says no pass backs
 * the window: true (covered, none matches), false (one matches) or null (prediction can't say).
 */
export const offerGeometry = {
  ...passGeometry,
  tca: d.nullable(d.timestamp),
  no_predicted_pass: d.nullable(d.boolean),
};

const passGeometryReader = d.object(passGeometry);
export type PassGeometry = Decoded<typeof passGeometryReader>;
const offerGeometryReader = d.object(offerGeometry);
export type OfferGeometry = Decoded<typeof offerGeometryReader>;

/**
 * `41.7°`, or `41.7° predicted` when it comes from Cadence's prediction rather than the provider
 * (#895: a predicted elevation is marked as one). null when neither knows it. An unknown source
 * shows the number alone (U20: say what's known).
 */
export function elevationWords(g: PassGeometry): string | null {
  if (g.max_elevation_deg === null) return null;
  const deg = `${g.max_elevation_deg.toFixed(1)}°`;
  return g.elevation_source === "predicted" ? `${deg} predicted` : deg;
}

/** A pass's "Max el" fact for D2, or none when the elevation isn't known. */
export function elevationFact(
  g: PassGeometry,
): readonly Readonly<{ key: string; label: string; value: string; mono: boolean }>[] {
  const value = elevationWords(g);
  return value === null ? [] : [{ key: "el", label: "Max el", value, mono: true }];
}

/** An offer's or alternative's line: `Max el 41.7° predicted · TCA 00:46Z`, or null. */
export function geometryLine(g: OfferGeometry): string | null {
  const el = elevationWords(g);
  const tca = g.tca === null ? null : `TCA ${formatHourMinute(new Date(g.tca))}`;
  const parts = [el === null ? null : `Max el ${el}`, tca].filter((p) => p !== null);
  return parts.length > 0 ? parts.join(" · ") : null;
}

/** #895: said as a caution only when prediction covers the window and no pass matches it. */
export const NO_PREDICTED_PASS = "No predicted pass backs this window";

export const noPredictedPass = (g: OfferGeometry): boolean => g.no_predicted_pass === true;
