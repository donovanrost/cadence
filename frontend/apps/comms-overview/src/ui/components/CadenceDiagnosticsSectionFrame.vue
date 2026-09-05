<script lang="ts">
import { Fragment, defineComponent, h, isVNode, type VNodeChild } from "vue";

const rootClass = "overflow-hidden border border-base-300/80 bg-base-200/30";
const headerClass =
  "grid gap-4 border-b border-base-300/70 px-4 py-3 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center";

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children);
    }

    return [child];
  });

export default defineComponent({
  name: "CadenceDiagnosticsSectionFrame",
  inheritAttrs: false,
  setup(_props, { attrs, slots }) {
    return () =>
      h("section", { ...attrs, class: rootClass }, [
        h("header", { class: headerClass }, flattenSlotChildren(slots.header?.() ?? [])),
        ...flattenSlotChildren(slots.default?.() ?? []),
      ]);
  },
});
</script>
