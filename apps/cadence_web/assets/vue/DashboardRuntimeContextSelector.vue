<script setup lang="ts">
import {defineComponent, h, type PropType} from "vue"

type PresentationNode = {
  key: string
  tag: string
  attrs: Record<string, string>
  children: Array<string | PresentationNode>
}

const props = defineProps<{presentation: PresentationNode}>()

const PresentationNodeRenderer = defineComponent({
  name: "PresentationNodeRenderer",
  props: {
    node: {type: Object as PropType<PresentationNode>, required: true}
  },
  setup(componentProps) {
    return () =>
      h(
        componentProps.node.tag,
        {...componentProps.node.attrs, key: componentProps.node.key},
        componentProps.node.children.map((child) =>
          typeof child === "string"
            ? child
            : h(PresentationNodeRenderer, {key: child.key, node: child})
        )
      )
  }
})
</script>

<template>
  <PresentationNodeRenderer :node="props.presentation" />
</template>
