import { computed, ref, watch } from "vue";

/**
 * a11y B6 (#654, ux on #276): a draft found superseded is read politely, but when the person's own
 * Submit was just refused because of it (409 plan_superseded), SupersededCallout is that refusal,
 * so it's an alert. `mark()` arms it for the plan on screen (`key`: plan and day); any other key
 * (another plan, another day, or none) disarms it, so the role never sticks.
 */
export function useSupersededRole(key: () => string | null) {
  const armed = ref<string | null>(null);
  watch(key, (now) => {
    if (now !== armed.value) armed.value = null;
  });
  return {
    mark(): void {
      armed.value = key();
    },
    role: computed(() =>
      armed.value !== null && armed.value === key() ? ("alert" as const) : undefined,
    ),
  };
}
