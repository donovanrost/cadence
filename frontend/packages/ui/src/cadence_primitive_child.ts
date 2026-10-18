import {
  cloneVNode,
  Comment,
  createVNode,
  defineComponent,
  Fragment,
  isVNode,
  mergeProps,
  Text,
  type VNode,
  type PropType,
} from "vue";

const normalizeChild = (child: unknown): VNode => {
  if (isVNode(child)) return child;
  if (Array.isArray(child)) return createVNode(Fragment, null, child.map(normalizeChild));
  if (child === null || child === undefined || typeof child === "boolean") {
    return createVNode(Comment);
  }

  if (typeof child === "string" || typeof child === "number" || typeof child === "bigint")
    return createVNode(Text, null, String(child));
  throw new Error("CadencePrimitiveChild received an unsupported slot value");
};

const normalizeFragmentChildren = (children: readonly unknown[]): VNode[] =>
  children.flatMap((rawChild) => {
    const child = normalizeChild(rawChild);
    if (child.type !== Fragment) return [child];

    const fragmentChildren = Array.isArray(child.children) ? child.children : [child.children];
    return normalizeFragmentChildren(fragmentChildren);
  });

const nativeElementRoot = (child: VNode): child is VNode & { type: string } =>
  typeof child.type === "string";

const componentRoot = (child: VNode) =>
  typeof child.type === "function" || (typeof child.type === "object" && child.type !== null);

const describeRoot = (child: VNode & { type: string }) => `<${child.type}>`;

export const CadencePrimitiveChild = defineComponent({
  name: "CadencePrimitiveChild",
  inheritAttrs: false,
  props: {
    contractName: {
      type: String,
      default: "CadencePrimitiveChild",
    },
    enforceAttrs: {
      type: Array as PropType<string[]>,
      required: true,
    },
    requiredTag: {
      type: String,
      default: undefined,
    },
  },
  setup(props, { attrs, slots }) {
    return () => {
      const children = normalizeFragmentChildren(slots.default?.() ?? []);
      if (children.some(componentRoot)) {
        throw new Error(
          `${props.contractName} requires a native element child; ` +
            "component children are not supported",
        );
      }

      const candidateIndexes = children.reduce<number[]>(
        (indexes, child, index) => (nativeElementRoot(child) ? [...indexes, index] : indexes),
        [],
      );
      if (candidateIndexes.length !== 1) {
        throw new Error(
          `${props.contractName} requires exactly one native element child; ` +
            `received ${candidateIndexes.length}`,
        );
      }

      const childIndex = candidateIndexes[0];
      const child = childIndex === undefined ? undefined : children[childIndex];
      if (childIndex === undefined || !child || !nativeElementRoot(child))
        throw new Error("Missing native child");
      if (props.requiredTag && child.type !== props.requiredTag) {
        throw new Error(
          `${props.contractName} requires a native <${props.requiredTag}> child; ` +
            `received ${describeRoot(child)}`,
        );
      }

      const enforcedAttrs = Object.fromEntries(
        props.enforceAttrs.map((name) => [name, attrs[name]]),
      );
      const childProps = { ...child.props };
      delete childProps.ref;
      const mergedProps = mergeProps(attrs, childProps, enforcedAttrs);
      children[childIndex] = cloneVNode({ ...child, props: {} }, mergedProps);

      return children;
    };
  },
});
