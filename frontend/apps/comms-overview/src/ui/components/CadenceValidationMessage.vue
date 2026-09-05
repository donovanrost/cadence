<script lang="ts">
import {Fragment, defineComponent, h, isVNode, type VNodeChild} from "vue"

const validationMessageClass = "mt-1.5 text-sm text-error"

const flattenDefaultSlot = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenDefaultSlot(child)

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenDefaultSlot(child.children)
    }

    return [child]
  })

export default defineComponent({
  name: "CadenceValidationMessage",
  inheritAttrs: false,
  setup(_, {attrs, slots}) {
    return () =>
      h(
        "p",
        {...attrs, class: [validationMessageClass, attrs.class]},
        flattenDefaultSlot(slots.default?.() ?? []),
      )
  },
})
</script>
