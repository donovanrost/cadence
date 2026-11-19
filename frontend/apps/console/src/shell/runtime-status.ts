import { computed, inject, provide, type InjectionKey, type Ref } from "vue";
import type { RuntimeStatus } from "./counts.ts";

/**
 * The mission runtime status from the shell's one /counts read, for features (Setup's top-bar
 * CONVERGING / RUNTIME DEGRADED, Changes outcomes) without a second poll. Same semantics as the
 * U38 banner: undefined = no read yet (or it failed: keep what's shown), null = nothing to say.
 */
type Status = Readonly<Ref<RuntimeStatus | null | undefined>>;
const key: InjectionKey<Status> = Symbol("apogee.runtime-status");

export function provideRuntimeStatus(status: Status) {
  provide(key, status);
}

export function useRuntimeStatus(): Status {
  return inject(
    key,
    computed(() => undefined),
  );
}
