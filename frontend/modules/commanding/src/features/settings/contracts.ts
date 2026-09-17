export type WorkspaceDefault = Readonly<{ shelf: "expanded" | "minimized" }>;
export function readWorkspaceDefault(value: unknown): WorkspaceDefault {
  if (
    value === null ||
    typeof value !== "object" ||
    !("shelf" in value) ||
    (value.shelf !== "expanded" && value.shelf !== "minimized")
  )
    throw new Error("Invalid Commanding workspace default.");
  return { shelf: value.shelf };
}
