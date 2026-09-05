<script lang="ts">
import { defineComponent, h, type PropType } from "vue";
import type { PresentationNode } from "../presentation_types";

const CadencePresentationNode = defineComponent({
  name: "CadencePresentationNode",
  props: {
    node: { type: Object as PropType<PresentationNode>, required: true },
  },
  setup(componentProps) {
    return () =>
      h(
        componentProps.node.tag,
        { ...componentProps.node.attrs, key: componentProps.node.key },
        componentProps.node.children.map((child) =>
          typeof child === "string"
            ? child
            : h(CadencePresentationNode, { key: child.key, node: child }),
        ),
      );
  },
});

export default CadencePresentationNode;
</script>
