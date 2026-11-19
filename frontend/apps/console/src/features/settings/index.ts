/** Public API of settings (fe-setup): ST1 reads other screens depend on. */
export { fetchSettings, type Settings } from "./api.ts";
import type { Settings } from "./api.ts";

/**
 * DECISIONS #45: `profile_framing_generations` defaults on; a mission can turn it off in ST1, and
 * then profile framing doesn't reach ingress. True only when the mission's value is explicitly off.
 */
export const profileFramingOff = (s: Settings): boolean =>
  s.sections
    // compared-as-text: a settings section key, an open set from the server's settings registry
    .find((x) => x.key === "cadence.configuration")
    // compared-as-text: a settings field path, an open set from the section's schema
    ?.fields.find((f) => f.path === "profile_framing_generations")?.value === false;
