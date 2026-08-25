import {cloneVNode, Comment, defineComponent, Fragment, mergeProps} from "vue"

const flattenFragments = (children) =>
  children.flatMap((child) =>
    child.type === Fragment && Array.isArray(child.children)
      ? flattenFragments(child.children)
      : [child],
  )

export const CadencePrimitiveChild = defineComponent({
  name: "CadencePrimitiveChild",
  inheritAttrs: false,
  props: {
    enforceAttrs: {
      type: Array,
      required: true,
    },
  },
  setup(props, {attrs, slots}) {
    return () => {
      const children = flattenFragments(slots.default?.() ?? [])
      const childIndex = children.findIndex((child) => child.type !== Comment)
      if (childIndex === -1) return children

      const child = children[childIndex]
      const enforcedAttrs = Object.fromEntries(
        props.enforceAttrs.map((name) => [name, attrs[name]]),
      )
      const mergedProps = mergeProps(attrs, child.props ?? {}, enforcedAttrs)
      children[childIndex] = cloneVNode({...child, props: {}}, mergedProps)

      return children
    }
  },
})
