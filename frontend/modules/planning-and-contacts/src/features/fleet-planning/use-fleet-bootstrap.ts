import { shallowRef, watch, type ShallowRef } from "vue";

const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);

/** Re-admitting an unchanged host snapshot must not cancel a feature's pending work. */
export function useFleetBootstrap<T>(input: () => T) {
  const model: ShallowRef<T> = shallowRef(input());
  const signature = (value: T) =>
    JSON.stringify(value, (_key, item: unknown) =>
      record(item)
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
