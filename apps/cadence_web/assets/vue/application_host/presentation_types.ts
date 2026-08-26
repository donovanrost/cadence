export type StatusTone = "ready" | "attention" | "blocked" | "info"
export type DiagnosticSeverity = "error" | "warning" | "info"

export type NavigationItem = {
  id: string
  surface_id: string
  label: string
  href: string
  current: boolean
}

export type Navigation = {
  id: string
  label: string
  items: NavigationItem[]
}

export type Stat = {
  id: string
  stat_id: string
  label: string
  value: string
  tone: StatusTone
  tone_label: string
}

export type DiagnosticItem = {
  id: string
  diagnostic_id: string
  code: string
  severity: DiagnosticSeverity
  title: string
  detail: string
  value: string | null
}

export type Diagnostics = {
  id: string
  items_id: string
  role: "alert" | "status"
  severity: DiagnosticSeverity
  count: number
  total_count: number
  count_label: string
  label: string
  title: string
  description: string | null
  items: DiagnosticItem[]
}
