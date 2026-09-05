<script lang="ts">
import { Fragment, defineComponent, h, isVNode, type VNodeChild } from "vue";

const tileClass = "border border-base-300 bg-base-200 px-3 py-2";
const labelClass = "hud-label";

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children);
    }

    return [child];
  });

export default defineComponent({
  name: "CadenceStatTile",
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () =>
      h("div", { ...attrs, class: [tileClass, attrs.class] }, [
        h("p", { class: labelClass }, flattenSlotChildren(slots.label?.() ?? [])),
        ...flattenSlotChildren(slots.default?.() ?? []),
      ]);
  },
});
</script>
