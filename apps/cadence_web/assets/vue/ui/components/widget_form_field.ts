export type Attributes = Record<string, string>

export type TextPresentation = {
  class: string
  text: string
}

export type OptionPresentation = {
  key: string
  text: string
  attrs: Attributes
}

export type FieldPresentation = {
  key: string
  type: "checkbox" | "search" | "select" | "text"
  wrapper_class: string
  label: TextPresentation | null
  control: {
    class: string
    attrs: Attributes
    options: OptionPresentation[]
  }
  hidden_control: {attrs: Attributes} | null
  description: TextPresentation | null
  errors: TextPresentation[]
}
