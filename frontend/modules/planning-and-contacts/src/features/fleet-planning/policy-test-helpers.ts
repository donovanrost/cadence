export type MutableFixture<T> = T extends object
  ? { -readonly [K in keyof T]: MutableFixture<T[K]> }
  : T;
import type { VueWrapper } from "@vue/test-utils";
import type { OpsFleetPlanningPolicyEmits } from "./OpsFleetPlanningPolicy.contracts";

export function required<T>(value: T | null | undefined): T {
  if (value == null) throw Error("Missing required fixture value");
  return value;
}

export function deferred<T>() {
  let settle: ((value: T) => void) | undefined;
  const promise = new Promise<T>((resolve) => {
    settle = resolve;
  });
  return { promise, resolve: required(settle) };
}

export function emittedPolicy<A extends keyof OpsFleetPlanningPolicyEmits>(
  wrapper: Pick<VueWrapper, "emitted">,
  action: A,
  index = 0,
): OpsFleetPlanningPolicyEmits[A][0] {
  return required(wrapper.emitted<OpsFleetPlanningPolicyEmits[A]>(action)?.[index])[0];
}
