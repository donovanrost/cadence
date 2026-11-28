import type { MissionId } from "@/api/index.ts";
import {
  computed,
  effectScope,
  onScopeDispose,
  type ComputedRef,
  type EffectScope,
  type ShallowRef,
} from "vue";
import { useRemoteQuery, type RemoteState } from "@/api";
import { useMissionInvalidation } from "@/live";
import { fetchConfigState } from "./api.ts";
import type { ConfigState } from "./shapes.ts";

type Shared = {
  scope: EffectScope;
  users: number;
  state: Readonly<ShallowRef<RemoteState<ConfigState>>>;
  refetch: () => void;
};
const shared = new Map<string, Shared>();

/**
 * The mission's config state (head revision + open change set), fetched once per mission and
 * shared by the top-bar status, the staged bar and the Changes screen. The query lives in a
 * detached scope that is disposed when its last user unmounts.
 */
export function useConfigState(missionId: MissionId) {
  let entry = shared.get(missionId);
  if (!entry) {
    const scope = effectScope(true);
    const created = scope.run(() => {
      const query = useRemoteQuery(() => missionId, fetchConfigState);
      useMissionInvalidation(
        computed(() => missionId),
        ["configuration"],
        query.refetch,
      );
      return query;
    });
    if (!created) throw new Error("config state scope did not run");
    entry = { scope, users: 0, state: created.state, refetch: created.refetch };
    shared.set(missionId, entry);
  }
  const current = entry;
  current.users += 1;
  onScopeDispose(() => {
    current.users -= 1;
    if (current.users === 0) {
      current.scope.stop();
      shared.delete(missionId);
    }
  });
  return { state: current.state, refetch: current.refetch };
}

/** After a write on the Changes page, refresh the shared state the top bar and staged bar show. */
export function refreshConfigState(missionId: MissionId): void {
  shared.get(missionId)?.refetch();
}

/**
 * #1160 row 1: may this viewer stage configuration changes? The server's `config.stage`, from the
 * check staging makes (`Configuration.Access` `:stage`, operate_mission). Staging changes nothing
 * until a reviewed change set applies it. False until the config state is read.
 */
export function useCanStage(missionId: MissionId): ComputedRef<boolean> {
  const { state } = useConfigState(missionId);
  return computed(
    () => state.value.status === "ready" && state.value.value.permissions.has("config.stage"),
  );
}
