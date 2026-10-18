<script lang="ts">
import { defineComponent, h } from "vue";

export default defineComponent({
  name: "CadenceDataRow",
  inheritAttrs: false,
  props: {
    rowId: { type: String, default: undefined },
    rowClass: { type: String, required: true },
    labelClass: { type: String, required: true },
    label: { type: String, required: true },
  },
  setup(props, { slots }) {
    return () =>
      h("div", { id: props.rowId, class: props.rowClass }, [
        h("span", { class: props.labelClass }, props.label),
        ...(slots.default?.() ?? []),
      ]);
  },
});
</script>
