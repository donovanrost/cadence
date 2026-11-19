import { computed, inject, provide, type InjectionKey, type Ref } from "vue";
import type { FleetPostureCounts } from "./counts.ts";

/**
 * The fleet posture from the shell's one /counts read (api-ops 64b16a90e), for the top bar's
 * posture cluster without a second poll or the ~300 KB fleet read. Same semantics as the runtime
 * status: undefined = no read yet (render nothing, U20), null = the server couldn't say.
 */
type Posture = Readonly<Ref<FleetPostureCounts | null | undefined>>;
const key: InjectionKey<Posture> = Symbol("apogee.fleet-posture");

export function provideFleetPosture(posture: Posture) {
  provide(key, posture);
}

export function useFleetPosture(): Posture {
  return inject(
    key,
    computed(() => undefined),
  );
}
