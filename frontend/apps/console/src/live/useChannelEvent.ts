import { onScopeDispose, watch, type Ref } from "vue";
import { decode, type Reader } from "@/api/decode.ts";
import { acquireChannel, onReconnect } from "./socket.ts";

/**
 * Listens to `event` on `topic` while the owner's scope lives; follows topic changes
 * (null = not subscribed). Payloads are decoded with `read`; malformed payloads are dropped
 * and reported to `onMalformed`. `onResync` runs after a reconnect so the owner can refetch.
 */
export function useChannelEvent<T>(
  topic: Readonly<Ref<string | null>>,
  event: string,
  read: Reader<T>,
  handlers: Readonly<{
    onEvent: (payload: T) => void;
    onResync?: () => void;
    onMalformed?: (message: string) => void;
  }>,
) {
  let cleanup: (() => void) | null = null;

  const stopTopic = watch(
    topic,
    (current) => {
      cleanup?.();
      cleanup = null;
      if (current === null) return;
      const { channel, release } = acquireChannel(current);
      const ref = channel.on(event, (payload: unknown) => {
        const result = decode(read, payload);
        if (result.ok) handlers.onEvent(result.value);
        else handlers.onMalformed?.(result.error.message);
      });
      const stopResync = handlers.onResync ? onReconnect(handlers.onResync) : () => undefined;
      cleanup = () => {
        channel.off(event, ref);
        stopResync();
        release();
      };
    },
    { immediate: true },
  );

  onScopeDispose(() => {
    stopTopic();
    cleanup?.();
    cleanup = null;
  });
}
