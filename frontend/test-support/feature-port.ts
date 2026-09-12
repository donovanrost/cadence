import { record } from "../packages/plugin-sdk/src/admission";

type FixtureFeaturePort = {
  read: () => unknown;
  save: (input: unknown, key: string) => unknown;
  navigate: (href: string) => unknown;
};

function isFeaturePort(value: unknown): value is FixtureFeaturePort {
  return (
    record(value) &&
    typeof value.read === "function" &&
    typeof value.save === "function" &&
    typeof value.navigate === "function"
  );
}

/** Inspect mounted feature capabilities while keeping their responses untrusted. */
export function fixtureFeaturePort(value: unknown): FixtureFeaturePort {
  if (!isFeaturePort(value)) throw Error("Expected a mounted feature port");
  return value;
}
