export type Attrs = Record<string, string>

export type ElementPresentation = {
  attrs: Attrs
}

export type TextPresentation = ElementPresentation & {
  text: string
}

export type BreadcrumbItem = {
  key: string
  separator: TextPresentation | null
  link: TextPresentation | null
  current: TextPresentation | null
}

export type BreadcrumbsPresentation = ElementPresentation & {
  items: BreadcrumbItem[]
}

export type PageHeaderAction = TextPresentation & {
  icon?: ElementPresentation | null
}

export type PageHeaderPresentation = ElementPresentation & {
  body: ElementPresentation
  content: ElementPresentation
  breadcrumbs: BreadcrumbsPresentation
  title: TextPresentation & {
    suffix: TextPresentation
  }
  subtitle: TextPresentation
  actions: ElementPresentation
}

export type CompactPageHeaderPresentation = Omit<
  PageHeaderPresentation,
  "title" | "subtitle"
> & {
  title: TextPresentation & {
    suffix?: null
  }
  subtitle?: null
}

export type EmptyStatePresentation = ElementPresentation & {
  title: TextPresentation
  description: TextPresentation
  action_container: ElementPresentation
  action: TextPresentation & {
    icon: ElementPresentation
  }
}
