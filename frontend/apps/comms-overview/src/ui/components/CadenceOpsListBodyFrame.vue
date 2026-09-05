<script lang="ts">
import {Fragment, cloneVNode, defineComponent, h, isVNode, type VNodeChild} from "vue"

const frameClass = "mx-auto max-w-[100rem] space-y-4 p-5 lg:p-7"

const flattenSlotChildren = (
  children: VNodeChild[],
  inheritedKey: string | number | symbol | null = null,
  keyPath: number[] = [],
): VNodeChild[] =>
  children.flatMap((child, index) => {
    if (Array.isArray(child)) {
      return flattenSlotChildren(child, inheritedKey, [...keyPath, index])
    }

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      const fragmentKey = child.key ?? inheritedKey
      return flattenSlotChildren(
        child.children,
        fragmentKey,
        child.key === null ? [...keyPath, index] : [],
      )
    }

    if (inheritedKey !== null && isVNode(child) && child.key === null) {
      return [
        cloneVNode(child, {
          key: `${String(inheritedKey)}:${[...keyPath, index].join(".")}`,
        }),
      ]
    }

    return [child]
  })

export default defineComponent({
  name: "CadenceOpsListBodyFrame",
  inheritAttrs: false,
  setup(_, {attrs, slots}) {
    return () =>
      h(
        "div",
        {...attrs, class: [frameClass, attrs.class]},
        flattenSlotChildren(slots.default?.() ?? []),
      )
  },
})
</script>
