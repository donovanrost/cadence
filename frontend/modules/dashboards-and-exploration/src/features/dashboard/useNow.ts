import { onBeforeUnmount, onMounted, ref } from "vue";

/** A wall clock for relative times and live windows; stops with its owner. */
export function useNow(intervalMs = 1000) {
  const now = ref(Date.now());
  let timer: ReturnType<typeof setInterval> | undefined;
  onMounted(() => {
    timer = setInterval(() => (now.value = Date.now()), intervalMs);
  });
  onBeforeUnmount(() => clearInterval(timer));
  return now;
}

export function ago(ms: number): string {
  const seconds = Math.max(0, Math.round(ms / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  return minutes < 60 ? `${minutes}m ago` : `${Math.round(minutes / 60)}h ago`;
}
