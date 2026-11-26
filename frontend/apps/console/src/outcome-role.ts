/**
 * a11y B6 (#276, ux): the live role of a callout that shows the outcome of the person's own act.
 * The role follows what happened, not the kit's tone default: a success (nominal, info) is read
 * politely, and anything that went wrong (caution, crit) is an alert. Not for standing cautions
 * or first loads, which keep ApCallout's default.
 */
/** The tones an outcome takes (lead and ux on #601: typed, so a stray tone is a type error). */
export type OutcomeTone = "nominal" | "info" | "caution" | "crit";

export function outcomeRole(tone: OutcomeTone): "alert" | "status" {
  return tone === "caution" || tone === "crit" ? "alert" : "status";
}
