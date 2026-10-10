/** One button recipe for buttons and link buttons, so they cannot drift apart. */
export type ButtonVariant = "primary" | "secondary" | "quiet" | "danger" | "outline";
export type ButtonSize = "xs" | "sm" | "md" | "lg";

const variants: Record<ButtonVariant, string> = {
  primary: "btn-primary",
  secondary: "",
  quiet: "btn-ghost",
  danger: "btn-error",
  outline: "btn-outline",
};
const sizes: Record<ButtonSize, string> = { xs: "btn-xs", sm: "btn-sm", md: "", lg: "btn-lg" };

export const buttonClasses = (variant: ButtonVariant, size: ButtonSize) => [
  "btn",
  variants[variant],
  sizes[size],
];
