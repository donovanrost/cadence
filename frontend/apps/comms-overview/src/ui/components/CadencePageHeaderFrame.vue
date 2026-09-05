<script lang="ts">
import { Fragment, defineComponent, h, isVNode, type PropType, type VNodeChild } from "vue";

type Variant = "compact" | "ops" | "ops-author";

const variantClasses: Record<Variant, string> = {
  compact: "border-b border-primary/20 pb-4",
  ops: "border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7",
  "ops-author": "border-b border-primary/20 bg-base-200/70 px-6 py-5 hud-grid",
};

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children);
    }

    return [child];
  });

export default defineComponent({
  name: "CadencePageHeaderFrame",
  inheritAttrs: false,
  props: {
    variant: {
      type: String as PropType<Variant>,
      required: true,
      validator: (value: string) =>
        value === "compact" || value === "ops" || value === "ops-author",
    },
  },
  setup(props, { attrs, slots }) {
    return () =>
      h(
        "header",
        { ...attrs, class: variantClasses[props.variant] },
        flattenSlotChildren(slots.default?.() ?? []),
      );
  },
});
</script>
