<script lang="ts">
import { defineComponent, h } from "vue";

const CadenceField = defineComponent({
  name: "CadenceField",
  props: {
    controlId: { type: String, required: false },
    wrapperClass: { type: String, default: "fieldset mb-3" },
    label: { type: String, required: true },
    labelClass: { type: String, default: "hud-label block mb-1.5" },
  },
  setup(props, { slots }) {
    return () =>
      h("div", { class: props.wrapperClass }, [
        h("label", props.controlId ? { for: props.controlId } : {}, [
          h("span", { class: props.labelClass }, props.label),
          ...(slots.default?.() ?? []),
        ]),
        ...(slots.help?.() ?? []),
        ...(slots.errors?.() ?? []),
      ]);
  },
});

export default CadenceField;
</script>
