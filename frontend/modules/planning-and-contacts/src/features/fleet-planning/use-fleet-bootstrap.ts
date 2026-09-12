import { shallowRef, watch } from "vue";

/** Re-admitting an unchanged host snapshot must not cancel a feature's pending work. */
export function useFleetBootstrap<T>(input: () => T) {
  const model = shallowRef(input());
  const signature = (value: T) =>
    JSON.stringify(value, (_key, item) =>
      item && typeof item === "object" && !Array.isArray(item)
        ? Object.fromEntries(
            Object.keys(item)
              .sort()
              .map((key) => [key, item[key]]),
          )
        : item,
    );
  watch(input, (next) => {
    if (signature(next) !== signature(model.value)) model.value = next;
  });
  return model;
}
