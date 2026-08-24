# Test-only compatibility renderer preserving the pre-LiveVue component contract.
defmodule CadenceWeb.TestSupport.BadgeComponents do
  @moduledoc false

  use Phoenix.Component

  attr :severity, :atom, required: true, values: [:critical, :warning, :info, :nominal]
  attr :count, :integer, default: nil
  attr :label, :string, default: nil
  attr :class, :string, default: nil

  def severity_badge(assigns) do
    assigns =
      assign_new(assigns, :resolved_label, fn ->
        assigns.label || severity_label(assigns.severity)
      end)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium",
      severity_badge_class(@severity),
      @class
    ]}>
      <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
      <span :if={@count} class="font-mono">{@count}</span>
      <span class="uppercase text-[0.65rem]">{@resolved_label}</span>
    </span>
    """
  end

  defp severity_badge_class(:critical), do: "bg-error/20 text-error"
  defp severity_badge_class(:warning), do: "bg-warning/20 text-warning"
  defp severity_badge_class(:info), do: "bg-info/20 text-info"
  defp severity_badge_class(:nominal), do: "bg-success/20 text-success"

  defp severity_label(:critical), do: "CRIT"
  defp severity_label(:warning), do: "WARN"
  defp severity_label(:info), do: "INFO"
  defp severity_label(:nominal), do: "NOM"
end
