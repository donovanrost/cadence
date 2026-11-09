import { defineAsyncComponent, defineComponent, h, type Component } from "vue";
import { useSmallScreen } from "@/shell/viewport.ts";

type Loader = () => Promise<Component | { default: Component }>;

/**
 * One route, two layouts (Mobile.md: same routes; under 768px the on-call layout). Each side
 * loads lazily; switching the viewport swaps the screen.
 */
export function responsive(desktop: Loader, mobile: Loader): Component {
  const Desktop = defineAsyncComponent(desktop);
  const Mobile = defineAsyncComponent(mobile);
  return defineComponent({
    name: "ResponsiveScreen",
    setup() {
      const small = useSmallScreen();
      return () => h(small.value ? Mobile : Desktop);
    },
  });
}
