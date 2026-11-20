/**
 * a11y B6 (#276, ux): the live role of a callout that shows the outcome of the person's own act.
 * The role follows what happened, not the kit's tone default: a success (nominal, info) is read
 * politely, and anything that went wrong (caution, crit) is an alert. Not for standing cautions
 * or first loads, which keep ApCallout's default.
 */
export function outcomeRole(tone: string): "alert" | "status" {
  return tone === "caution" || tone === "crit" ? "alert" : "status";
}
