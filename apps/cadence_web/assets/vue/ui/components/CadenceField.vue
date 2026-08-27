<script lang="ts">
import {defineComponent, h} from "vue"

const CadenceField = defineComponent({
  name: "CadenceField",
  props: {
    controlId: {type: String, required: true},
    wrapperClass: {type: String, required: true},
    label: {type: String, required: true},
    labelClass: {type: String, required: true}
  },
  setup(props, {slots}) {
    return () =>
      h("div", {class: props.wrapperClass}, [
        h("label", {for: props.controlId}, [
          h("span", {class: props.labelClass}, props.label),
          ...(slots.default?.() ?? [])
        ]),
        ...(slots.help?.() ?? []),
        ...(slots.errors?.() ?? [])
      ])
  }
})

export default CadenceField
</script>
