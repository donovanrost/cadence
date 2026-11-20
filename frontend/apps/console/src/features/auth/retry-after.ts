import { computed, nextTick, onScopeDispose, ref } from "vue";
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

/**
 * The 429 said once (a11y B6, ux #276): the wait in plain words, for the alert when the limit is
 * hit. The m:ss countdown stays on screen but isn't live, so it doesn't interrupt every second.
 */
export function waitSentence(seconds: number): string {
  const s = Math.max(1, Math.ceil(seconds));
  if (s < 60) return `Too many attempts. Try again in ${s} second${s === 1 ? "" : "s"}.`;
  const m = Math.ceil(s / 60);
  return `Too many attempts. Try again in ${m} minute${m === 1 ? "" : "s"}.`;
}

/** Said politely once, when the wait is over and the form works again (ux #276). */
export const RETRY_OPEN = "You can try again now.";

export function useRetryAfter(now: () => number = Date.now) {
  const until = ref<number | null>(null);
  const tick = ref(now());
  /**
   * For the two always-present live regions (RetryAfterNotice): the alert when the limit is hit,
   * the polite line when it's over. Cleared first, so the same words said twice are said twice.
   */
  const said = ref<{ alert: string; status: string }>({ alert: "", status: "" });
  async function say(next: { alert: string; status: string }) {
    said.value = { alert: "", status: "" };
    await nextTick();
    said.value = next;
  }
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
    void say({ alert: waitSentence(retryAfterSeconds), status: "" });
    timer = setInterval(() => {
      tick.value = now();
      if (until.value !== null && tick.value >= until.value) {
        until.value = null;
        stop();
        void say({ alert: "", status: RETRY_OPEN });
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
    /** The callout and the disabled primary's reason; null when the form works. Not live. */
    text: computed(() => (secondsLeft.value > 0 ? retryText(secondsLeft.value) : null)),
    /** What the live regions say: once when the limit is hit, once when it's over. */
    said: computed(() => said.value),
  };
}

/** The server's wait for a 429 `too_many_attempts` (details.retry_after), else null. */
export function retryAfterOf(error: ApiError): number | null {
  if (!isError(error, "too_many_attempts")) return null;
  const wait = detailsOf(error, retryAfter)?.retry_after;
  return typeof wait === "number" && wait >= 0 ? wait : 60;
}
