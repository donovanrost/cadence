<script lang="ts">
import {defineComponent, h} from "vue"

export default defineComponent({
  name: "CadenceCard",
  inheritAttrs: false,
  props: {
    bodyClass: {type: String, required: true},
  },
  setup(props, {attrs, slots}) {
    return () =>
      h("section", attrs, [
        h("div", {class: props.bodyClass}, [...(slots.default?.() ?? [])]),
      ])
  },
})
</script>
