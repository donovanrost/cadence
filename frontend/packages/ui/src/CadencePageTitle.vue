<script lang="ts">
import { Fragment, defineComponent, h, isVNode, type VNodeChild } from "vue";

const pageTitleClass = "cd-page-title";

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children);
    }

    return [child];
  });

export default defineComponent({
  name: "CadencePageTitle",
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () =>
      h(
        "h1",
        { ...attrs, class: [pageTitleClass, attrs.class] },
        flattenSlotChildren(slots.default?.() ?? []),
      );
  },
});
</script>
