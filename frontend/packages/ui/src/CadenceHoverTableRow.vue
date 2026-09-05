<script lang="ts">
import { Fragment, defineComponent, h, isVNode, type VNodeChild } from "vue";

const rowClass = "border-l-2 border-l-transparent transition-colors hover:border-l-primary/60";

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children);
    }

    return [child];
  });

export default defineComponent({
  name: "CadenceHoverTableRow",
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () =>
      h(
        "tr",
        { ...attrs, class: [rowClass, attrs.class] },
        flattenSlotChildren(slots.default?.() ?? []),
      );
  },
});
</script>
