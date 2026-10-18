import {
  defineComponent,
  h,
  onBeforeUnmount,
  onMounted,
  shallowRef,
  Teleport,
  type Component,
} from "vue";

/** Keep each LiveVue page's transport and component instance stable while the shell updates. */
export function inApplicationShell(component: Component): Component {
  return defineComponent({
    name: "HostPagePortal",
    inheritAttrs: false,
    setup(_props, { attrs, slots }) {
      const target = shallowRef<HTMLElement | null>(null);
      let observer: MutationObserver | undefined;
      onMounted(() => {
        const updateTarget = () => {
          target.value = document.getElementById("application-content");
        };
        updateTarget();
        observer = new MutationObserver(updateTarget);
        observer.observe(document.body, { childList: true, subtree: true });
      });
      onBeforeUnmount(() => observer?.disconnect());
      return () =>
        target.value ? h(Teleport, { to: target.value }, h(component, attrs, slots)) : null;
    },
  });
}
