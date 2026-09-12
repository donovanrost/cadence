import { onBeforeUnmount, onErrorCaptured, ref, shallowRef, watch, type Component } from "vue";
import {
  isHostContext,
  type FullPageSurfaceProps,
  type HostActionReceipt,
  type MissionHostContext,
} from "@cadence/plugin-sdk";

type Contribution = {
  applicationKey: string;
  surfaceId: string;
  query: { id: string; version: number };
  component: Component;
  saveAction?: string;
};
type Port<Input> = {
  read: () => Promise<unknown>;
  save: (input: Input, key: string) => Promise<HostActionReceipt<unknown>>;
  navigate: (href: string) => void;
};

/** Delivery lifecycle only; each contributed feature still admits its own DTO. */
export function useMissionContribution<Input>(
  props: FullPageSurfaceProps,
  contributions: readonly Contribution[],
  unavailable: string,
) {
  const document = shallowRef<unknown>();
  const loading = ref(true);
  const error = ref("");
  const session = shallowRef<{
    key: number;
    component: Component;
    context: MissionHostContext;
    port: Port<Input>;
  }>();
  let alive = true;
  let generation = 0;

  async function load() {
    if (!alive) return;
    const current = ++generation;
    session.value = undefined;
    document.value = undefined;
    loading.value = true;
    error.value = "";
    try {
      const surface = props.surface;
      const contribution = contributions.find((entry) => entry.surfaceId === surface?.surfaceId);
      const application = props.application;
      if (
        !contribution ||
        !isHostContext(props.context) ||
        props.context.scope !== "mission" ||
        application?.applicationKey !== contribution.applicationKey ||
        application.applicationVersion !== 1 ||
        application.surface?.surfaceId !== surface.surfaceId ||
        application.surface.version !== surface.version ||
        surface.version !== 1 ||
        surface.scope !== "mission" ||
        surface.dataContract?.id !== contribution.query.id ||
        surface.dataContract.version !== contribution.query.version ||
        !Array.isArray(surface.actions) ||
        (contribution.saveAction && !surface.actions.includes(contribution.saveAction))
      )
        throw Error("Unsupported mission contribution");

      const context: MissionHostContext = Object.freeze({
        scope: "mission",
        organizationId: props.context.organizationId,
        missionId: props.context.missionId,
        missionName: props.context.missionName,
        spacecraftId: null,
        spacecraftName: null,
        actor: Object.freeze({
          displayName: props.context.actor.displayName,
          permissions: Object.freeze([...props.context.actor.permissions]),
        }),
      });
      const bridge = props.bridge;
      const query = bridge.query.bind(bridge);
      const execute = bridge.execute.bind(bridge);
      const navigate = bridge.navigate;
      function assertCurrent() {
        if (!alive || current !== generation) throw Error("Contribution context retired");
      }
      const port: Port<Input> = {
        async read() {
          assertCurrent();
          const value = await query<Record<string, unknown>>({
            queryId: contribution.query.id,
            version: contribution.query.version,
            context,
          });
          assertCurrent();
          return value.trusted_surface;
        },
        async save(input, idempotencyKey) {
          assertCurrent();
          if (!contribution.saveAction) throw Error("This contribution has no save action");
          const receipt = await execute({
            applicationKey: contribution.applicationKey,
            applicationVersion: 1,
            surfaceId: contribution.surfaceId,
            surfaceVersion: 1,
            actionId: contribution.saveAction,
            context,
            input,
            idempotencyKey,
          });
          assertCurrent();
          return receipt;
        },
        navigate(href) {
          assertCurrent();
          (navigate ?? ((target) => window.location.assign(target)))(href);
        },
      };
      const value = await port.read();
      assertCurrent();
      document.value = value;
      session.value = { key: current, component: contribution.component, context, port };
    } catch {
      if (alive && current === generation) error.value = unavailable;
    } finally {
      if (alive && current === generation) loading.value = false;
    }
  }
  watch(
    () => [props.application, props.surface, props.context, props.bridge],
    () => void load(),
    { immediate: true, deep: true, flush: "sync" },
  );
  onBeforeUnmount(() => {
    alive = false;
    generation++;
  });
  onErrorCaptured(() => {
    generation++;
    session.value = undefined;
    document.value = undefined;
    loading.value = false;
    error.value = unavailable;
    return false;
  });
  return { document, loading, error, session, load };
}
