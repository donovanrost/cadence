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
  let fail: ((reason: unknown) => void) | undefined;
  const promise = new Promise<T>((resolve, reject) => {
    settle = resolve;
    fail = reject;
  });
  return { promise, resolve: required(settle), reject: required(fail) };
}

export function emittedPolicy<A extends keyof OpsFleetPlanningPolicyEmits>(
  wrapper: Pick<VueWrapper, "emitted">,
  action: A,
  index = 0,
): OpsFleetPlanningPolicyEmits[A][0] {
  return required(wrapper.emitted<OpsFleetPlanningPolicyEmits[A]>(action)?.[index])[0];
}
