<script lang="ts">
import { defineComponent, h, type DefineComponent, type PropType, type VNode } from "vue";
import type { PresentationNode } from "../presentation_types";

const CadencePresentationNode: DefineComponent<{ node: PresentationNode }> = defineComponent({
  name: "CadencePresentationNode",
  props: {
    node: { type: Object as PropType<PresentationNode>, required: true },
  },
  setup(componentProps): () => VNode {
    return (): VNode =>
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
