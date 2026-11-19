import { computed, onScopeDispose, ref } from "vue";
import { decoders as d, detailsOf, isError, type ApiError } from "@/api";

const retryAfter = d.object({ retry_after: d.optional(d.nullable(d.number)) });

/**
 * The 429 attempt-limit state every password field shares (Auth.md, api-ops 2ba5cd57): a live
 * m:ss countdown from the server's `retry_after`; at zero the form works again. Never "locked",
 * never which part was wrong.
 */
export function retryText(seconds: number): string {
  const s = Math.max(0, Math.ceil(seconds));
  return `Too many attempts. Try again in ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}.`;
}

export function useRetryAfter(now: () => number = Date.now) {
  const until = ref<number | null>(null);
  const tick = ref(now());
  let timer: ReturnType<typeof setInterval> | null = null;
  const stop = () => {
    if (timer !== null) clearInterval(timer);
    timer = null;
  };
  /** Start (or restart) the wait from the server's `retry_after` seconds. */
  function block(retryAfterSeconds: number) {
    until.value = now() + Math.max(0, retryAfterSeconds) * 1000;
    tick.value = now();
    stop();
    timer = setInterval(() => {
      tick.value = now();
      if (until.value !== null && tick.value >= until.value) {
        until.value = null;
        stop();
      }
    }, 250);
  }
  onScopeDispose(stop);
  const secondsLeft = computed(() =>
    until.value === null ? 0 : Math.max(0, (until.value - tick.value) / 1000),
  );
  return {
    block,
    blocked: computed(() => secondsLeft.value > 0),
    /** The callout and the disabled primary's reason; null when the form works. */
    text: computed(() => (secondsLeft.value > 0 ? retryText(secondsLeft.value) : null)),
  };
}

/** The server's wait for a 429 `too_many_attempts` (details.retry_after), else null. */
export function retryAfterOf(error: ApiError): number | null {
  if (!isError(error, "too_many_attempts")) return null;
  const wait = detailsOf(error, retryAfter)?.retry_after;
  return typeof wait === "number" && wait >= 0 ? wait : 60;
}
