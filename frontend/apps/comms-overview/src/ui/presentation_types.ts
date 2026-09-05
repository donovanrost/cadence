export type PresentationNode = {
  key: string
  tag: string
  attrs: Record<string, string>
  children: Array<string | PresentationNode>
}
