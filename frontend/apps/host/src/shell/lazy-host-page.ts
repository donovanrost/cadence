import { defineComponent, h, onErrorCaptured, shallowRef, type Component } from "vue";
import { useLazyPage } from "./module-pages/lazy-pages";
import { reportFrontendFailure } from "./frontend-diagnostics";

/** Keep shell/history ownership synchronous; load page implementations when they are selected. */
export function lazyHostPage(
  name: string,
  loader: () => Promise<{ default: Component }>,
): Component {
  let cached: Component | undefined;
  const source = {
    peek: () => cached,
    async load() {
      cached = (await loader()).default;
      return cached;
    },
  };
  return defineComponent({
    name: `Lazy${name}`,
    inheritAttrs: false,
    setup(_props, { attrs, slots }) {
      const reference = shallowRef<string>();
      const page = useLazyPage(
        () => name,
        source,
        (cause) => {
          reference.value = reportFrontendFailure(
            { boundary: "host.page", contributionId: name },
            "load",
            cause,
          ).id;
        },
      );
      onErrorCaptured((cause) => {
        if (page.state.value.kind !== "failed") {
          page.state.value = { kind: "failed" };
          reference.value = reportFrontendFailure(
            { boundary: "host.page", contributionId: name },
            "render",
            cause,
          ).id;
        }
        return false;
      });
      return () => {
        const state = page.state.value;
        if (state.kind === "ready") return h(state.value, attrs, slots);
        if (state.kind === "loading")
          return h(
            "div",
            { role: "status", class: "p-6", "data-host-page-loading": name },
            "Loading page…",
          );
        return h("section", { role: "alert", class: "p-6", "data-host-page-load-failed": name }, [
          h("p", "This page could not be loaded."),
          h("p", { class: "mt-2 text-xs" }, `Reference: ${reference.value ?? ""}`),
          h("button", { type: "button", class: "btn btn-sm mt-4", onClick: page.reload }, "Retry"),
        ]);
      };
    },
  });
}
