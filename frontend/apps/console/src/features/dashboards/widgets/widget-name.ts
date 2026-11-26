import { computed, inject, type ComputedRef, type InjectionKey, type Ref } from "vue";
import type { WorkspacePlacement } from "../model/snapshot.ts";
import { widgetTitle } from "../model/widget-data.ts";

/**
 * B7: the name the widget's panel shows ("Untitled widget 3" when it has no title). WidgetBody
 * provides it from its panel (viewer or edit mode), so the widget's scroll region and caption say
 * the same name as its heading. Undefined when the body was given no name.
 */
export const WIDGET_NAME: InjectionKey<Readonly<Ref<string | undefined>>> = Symbol("widget name");

/** The provided panel name, else the widget's own title (a widget mounted outside a panel). */
export function useWidgetName(placement: () => WorkspacePlacement): ComputedRef<string> {
  const provided = inject(WIDGET_NAME, null);
  return computed(() => provided?.value ?? widgetTitle(placement()));
}
