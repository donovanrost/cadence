import type heroicons from "../vendor/heroicons.json";

/** Every icon in the vendored Heroicons set; a typo is a type error, not a blank square. */
export type IconName = `hero-${Extract<keyof typeof heroicons, string>}`;
