import { onScopeDispose, watch, type Ref } from "vue";
import { acquireChannel, type ChannelHandle } from "./socket.ts";

export type SubscriptionMessages = Readonly<{
  /** The payload may be a getter (e.g. a dashboard view's range and scope): each (re)join sends its current value. */
  subscribe: readonly [event: string, payload: object | (() => object)];
  unsubscribe: readonly [event: string, payload: object];
  /** With a getter payload: the event pushed with the new payload when it changes while joined (e.g. `view:set`). */
  update?: string | undefined;
}>;

/**
 * Keeps an opt-in server subscription alive on a shared channel (e.g. `fleet:subscribe` on
 * `mission:<id>`): pushes `subscribe` after every successful (re)join, `unsubscribe` on topic
 * change or scope dispose. `resubscribe()` handles a sequence gap. Listen to the resulting events
 * with useChannelEvent. Two owners on one topic each subscribe; the server must treat it as
 * idempotent (api-ops' fleet push does). With a getter payload and `update`, a payload change
 * while joined pushes `update` with the new value instead of resubscribing.
 */
const isGetter = (p: object | (() => object)): p is () => object => typeof p === "function";

export function useChannelSubscription(
  topic: Readonly<Ref<string | null>>,
  messages: SubscriptionMessages,
): { resubscribe: () => void } {
  let current: { handle: ChannelHandle; stopJoin: () => void } | null = null;
  const payload = messages.subscribe[1];
  const getter = isGetter(payload) ? payload : null;
  const currentPayload = (): object => (getter ? getter() : payload);
  const subscribe = (handle: ChannelHandle) => {
    handle.channel.push(messages.subscribe[0], currentPayload());
  };
  const unsubscribe = (handle: ChannelHandle) => {
    if (handle.joined()) handle.channel.push(messages.unsubscribe[0], messages.unsubscribe[1]);
  };

  function stop() {
    if (!current) return;
    current.stopJoin();
    unsubscribe(current.handle);
    current.handle.release();
    current = null;
  }

  const stopTopic = watch(
    topic,
    (next) => {
      stop();
      if (next === null) return;
      const handle = acquireChannel(next);
      const stopJoin = handle.onJoin(() => subscribe(handle));
      if (handle.joined()) subscribe(handle);
      current = { handle, stopJoin };
    },
    { immediate: true },
  );

  const update = messages.update;
  const stopPayload =
    getter && update
      ? watch(
          currentPayload,
          (next) => {
            if (current?.handle.joined()) current.handle.channel.push(update, next);
          },
          { deep: true },
        )
      : null;

  onScopeDispose(() => {
    stopTopic();
    stopPayload?.();
    stop();
  });

  return {
    resubscribe: () => {
      if (!current || !current.handle.joined()) return;
      unsubscribe(current.handle);
      subscribe(current.handle);
    },
  };
}
