<script lang="ts">
import {Fragment, cloneVNode, defineComponent, h, isVNode, type VNodeChild} from "vue"

const panelClass = "border border-base-300/70 bg-base-100/40 p-4"
const headingClass = "hud-label"
const definitionListClass =
  "mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs"

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
      return [cloneVNode(child, {key: `${String(inheritedKey)}:${[...keyPath, index].join(".")}`})]
    }

    return [child]
  })

export default defineComponent({
  name: "CadenceDefinitionListPanel",
  inheritAttrs: false,
  setup(_, {attrs, slots}) {
    return () =>
      h("section", {...attrs, class: [panelClass, attrs.class]}, [
        h("h2", {class: headingClass}, flattenSlotChildren(slots.heading?.() ?? [])),
        h("dl", {class: definitionListClass}, flattenSlotChildren(slots.default?.() ?? [])),
      ])
  },
})
</script>
