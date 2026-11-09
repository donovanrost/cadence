import { onScopeDispose, watch, type Ref } from "vue";
import { acquireChannel, type ChannelHandle } from "./socket.ts";

export type SubscriptionMessages = Readonly<{
  subscribe: readonly [event: string, payload: object];
  unsubscribe: readonly [event: string, payload: object];
}>;

/**
 * Keeps an opt-in server subscription alive on a shared channel (e.g. `fleet:subscribe` on
 * `mission:<id>`): pushes `subscribe` after every successful (re)join, `unsubscribe` on topic
 * change or scope dispose. `resubscribe()` handles a sequence gap. Listen to the resulting events
 * with useChannelEvent. Two owners on one topic each subscribe; the server must treat it as
 * idempotent (api-ops' fleet push does).
 */
export function useChannelSubscription(
  topic: Readonly<Ref<string | null>>,
  messages: SubscriptionMessages,
): { resubscribe: () => void } {
  let current: { handle: ChannelHandle; stopJoin: () => void } | null = null;
  const subscribe = (handle: ChannelHandle) => {
    handle.channel.push(messages.subscribe[0], messages.subscribe[1]);
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

  onScopeDispose(() => {
    stopTopic();
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
