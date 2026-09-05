<script lang="ts">
import {
  Fragment,
  defineComponent,
  h,
  isVNode,
  mergeProps,
  type PropType,
  type VNodeChild,
} from "vue";

type FrameAttrs = Record<string, unknown>;

const rootAttrs = {
  class: "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
};
const titleAttrs = { class: "hud-label" };
const descriptionAttrs = {
  class: "mx-auto mt-2 max-w-md text-sm text-base-content/70",
};
const actionContainerAttrs = { class: "mt-5" };

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children);
    }

    return [child];
  });

export default defineComponent({
  name: "CadenceEmptyStateFrame",
  inheritAttrs: false,
  props: {
    rootAttrs: Object as PropType<FrameAttrs>,
    titleAttrs: Object as PropType<FrameAttrs>,
    descriptionAttrs: Object as PropType<FrameAttrs>,
    actionContainerAttrs: Object as PropType<FrameAttrs>,
  },
  setup(props, { attrs, slots }) {
    return () =>
      h("div", mergeProps(props.rootAttrs ?? rootAttrs, attrs), [
        h("p", props.titleAttrs ?? titleAttrs, flattenSlotChildren(slots.title?.() ?? [])),
        h(
          "p",
          props.descriptionAttrs ?? descriptionAttrs,
          flattenSlotChildren(slots.description?.() ?? []),
        ),
        h(
          "div",
          props.actionContainerAttrs ?? actionContainerAttrs,
          flattenSlotChildren(slots.action?.() ?? []),
        ),
      ]);
  },
});
</script>
