<script lang="ts">
import {Fragment, defineComponent, h, isVNode, type VNodeChild} from "vue"

const flattenFragments = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenFragments(child)

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenFragments(child.children)
    }

    return [child]
  })

export default defineComponent({
  name: "CadencePanel",
  inheritAttrs: false,
  props: {
    headerClass: {type: String, required: true},
  },
  setup(props, {attrs, slots}) {
    return () =>
      h("section", attrs, [
        h("div", {class: props.headerClass}, flattenFragments(slots.header?.() ?? [])),
        ...flattenFragments(slots.default?.() ?? []),
      ])
  },
})
</script>
