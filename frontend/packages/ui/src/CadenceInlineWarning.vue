<script lang="ts">
import { Fragment, defineComponent, h, isVNode, type VNodeChild } from "vue";

const inlineWarningClass = "border-l-2 border-warning px-3 text-xs text-warning";

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children);
    }

    return [child];
  });

export default defineComponent({
  name: "CadenceInlineWarning",
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () =>
      h(
        "p",
        { ...attrs, class: [attrs.class, inlineWarningClass] },
        flattenSlotChildren(slots.default?.() ?? []),
      );
  },
});
</script>
