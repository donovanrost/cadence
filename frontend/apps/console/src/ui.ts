/**
 * The console's UI import surface: the Apogee package plus app-specific view helpers.
 * Features import UI, formatting and the shared clock from "@/ui".
 */
export * from "@cadence/apogee-ui";
export { default as ApRemote } from "./api/ApRemote.vue";
export { useInPlaceSwap } from "./in-place-swap.ts";
export { focusAfterRemove } from "./list-focus.ts";
