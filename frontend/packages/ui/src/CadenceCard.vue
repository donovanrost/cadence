<script lang="ts">
import { defineComponent, h } from "vue";

export default defineComponent({
  name: "CadenceCard",
  inheritAttrs: false,
  props: {
    bodyClass: { type: String, default: "card-body" },
  },
  setup(props, { attrs, slots }) {
    return () =>
      h("section", { ...attrs, class: attrs.class ?? "card" }, [
        h("div", { class: props.bodyClass }, [...(slots.default?.() ?? [])]),
      ]);
  },
});
</script>
