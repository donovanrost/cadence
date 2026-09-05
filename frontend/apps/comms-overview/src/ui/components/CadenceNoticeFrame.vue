<script lang="ts">
import {Fragment, defineComponent, h, isVNode, type PropType, type VNodeChild} from "vue"

type Tone = "info" | "warning"

const toneClasses: Record<Tone, string> = {
  info: "border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70",
  warning: "border-l-2 border-warning/60 bg-warning/10 px-4 py-3 text-sm text-base-content/70",
}

const flattenSlotChildren = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenSlotChildren(child)

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenSlotChildren(child.children)
    }

    return [child]
  })

export default defineComponent({
  name: "CadenceNoticeFrame",
  inheritAttrs: false,
  props: {
    tone: {
      type: String as PropType<Tone>,
      required: true,
      validator: (value: string) => value === "info" || value === "warning",
    },
  },
  setup(props, {attrs, slots}) {
    return () =>
      h(
        "div",
        {...attrs, class: [toneClasses[props.tone], attrs.class]},
        flattenSlotChildren(slots.default?.() ?? []),
      )
  },
})
</script>
