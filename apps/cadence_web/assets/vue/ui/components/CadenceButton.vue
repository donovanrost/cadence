<script>
import {h} from "vue"

export default {
  inheritAttrs: true,
  setup(_props, {slots}) {
    return () => h("button", null, slots.default?.())
  }
}
</script>
