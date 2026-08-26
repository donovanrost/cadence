import {
  cloneVNode,
  Comment,
  createVNode,
  defineComponent,
  Fragment,
  isVNode,
  mergeProps,
  Text,
} from "vue"

const normalizeChild = (child) => {
  if (isVNode(child)) return child
  if (Array.isArray(child)) return createVNode(Fragment, null, child)
  if (child === null || child === undefined || typeof child === "boolean") {
    return createVNode(Comment)
  }

  return createVNode(Text, null, String(child))
}

const normalizeFragmentChildren = (children) =>
  children.flatMap((rawChild) => {
    const child = normalizeChild(rawChild)
    if (child.type !== Fragment) return [child]

    const fragmentChildren = Array.isArray(child.children)
      ? child.children
      : [child.children]
    return normalizeFragmentChildren(fragmentChildren)
  })

const rootCandidate = (child) =>
  typeof child.type === "string" ||
  typeof child.type === "function" ||
  (typeof child.type === "object" && child.type !== null)

const describeRoot = (child) =>
  typeof child.type === "string" ? `<${child.type}>` : "a component"

export const CadencePrimitiveChild = defineComponent({
  name: "CadencePrimitiveChild",
  inheritAttrs: false,
  props: {
    contractName: {
      type: String,
      default: "CadencePrimitiveChild",
    },
    enforceAttrs: {
      type: Array,
      required: true,
    },
    requiredTag: {
      type: String,
      default: undefined,
    },
  },
  setup(props, {attrs, slots}) {
    return () => {
      const children = normalizeFragmentChildren(slots.default?.() ?? [])
      const candidateIndexes = children.reduce(
        (indexes, child, index) => (rootCandidate(child) ? [...indexes, index] : indexes),
        [],
      )
      if (candidateIndexes.length !== 1) {
        throw new Error(
          `${props.contractName} requires exactly one element or component child; ` +
            `received ${candidateIndexes.length}`,
        )
      }

      const childIndex = candidateIndexes[0]
      const child = children[childIndex]
      if (props.requiredTag && child.type !== props.requiredTag) {
        throw new Error(
          `${props.contractName} requires a native <${props.requiredTag}> child; ` +
            `received ${describeRoot(child)}`,
        )
      }

      const enforcedAttrs = Object.fromEntries(
        props.enforceAttrs.map((name) => [name, attrs[name]]),
      )
      const mergedProps = mergeProps(attrs, child.props ?? {}, enforcedAttrs)
      children[childIndex] = cloneVNode({...child, props: {}}, mergedProps)

      return children
    }
  },
})
