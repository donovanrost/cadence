<script lang="ts">
import { Fragment, defineComponent, h, isVNode, type VNodeChild } from "vue";

const frameClass =
  "flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-2";

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children);
    }

    return [child];
  });

export default defineComponent({
  name: "CadenceListToolbarFrame",
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () =>
      h(
        "div",
        { ...attrs, class: [frameClass, attrs.class] },
        flattenSlotChildren(slots.default?.() ?? []),
      );
  },
});
</script>
