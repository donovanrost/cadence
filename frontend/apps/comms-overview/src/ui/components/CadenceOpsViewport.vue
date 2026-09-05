<script lang="ts">
import {Fragment, defineComponent, h, isVNode, type VNodeChild} from "vue"

const opsViewportClass = "h-full overflow-y-auto bg-base-100"

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child)

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children)
    }

    return [child]
  })

export default defineComponent({
  name: "CadenceOpsViewport",
  inheritAttrs: false,
  setup(_, {attrs, slots}) {
    return () =>
      h(
        "section",
        {...attrs, class: [opsViewportClass, attrs.class]},
        flattenSlotChildren(slots.default?.() ?? []),
      )
  },
})
</script>
