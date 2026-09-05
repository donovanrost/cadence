<script lang="ts">
import {defineComponent, h} from "vue"

const CadenceFormActions = defineComponent({
  name: "CadenceFormActions",
  props: {
    wrapperClass: {type: String, required: true}
  },
  setup(props, {slots}) {
    return () => h("div", {class: props.wrapperClass}, slots.default?.())
  }
})

export default CadenceFormActions
</script>
