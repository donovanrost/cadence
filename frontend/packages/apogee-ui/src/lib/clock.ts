import { onScopeDispose, readonly, ref, type Ref } from "vue";

/**
 * One shared 1 Hz clock so every clock on screen ticks together (design-language ApClock).
 * The interval runs only while at least one component scope uses it.
 */
const now = ref(new Date());
let users = 0;
let timer: ReturnType<typeof setInterval> | null = null;

function start() {
  now.value = new Date();
  // Align ticks to the wall-clock second.
  const delay = 1000 - (Date.now() % 1000);
  timer = setTimeout(() => {
    now.value = new Date();
    timer = setInterval(() => {
      now.value = new Date();
    }, 1000);
  }, delay);
}

function stop() {
  if (timer !== null) {
    clearTimeout(timer);
    clearInterval(timer);
    timer = null;
  }
}

export function useNow(): Readonly<Ref<Date>> {
  users += 1;
  if (users === 1) start();
  onScopeDispose(() => {
    users -= 1;
    if (users === 0) stop();
  });
  return readonly(now) as Readonly<Ref<Date>>;
}
