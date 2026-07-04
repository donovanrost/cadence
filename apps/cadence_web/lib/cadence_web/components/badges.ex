defmodule CadenceWeb.Components.Badges do
  @moduledoc """
  Status and severity pills.

  `status_badge/1` is the one status pill — readiness vocabulary
  (`:ready/:attention/:blocked/:info`), shared with `status_dot/1` in
  `CadenceWeb.CoreComponents`. `severity_badge/1` is for diagnostic counts
  (`:critical/:warning/:info/:nominal`).
  """

  use Phoenix.Component

  @doc """
  Renders an inline status pill.

  ## Examples

      <.status_badge status={:ready} />
      <.status_badge status={:attention} label="Profile drift" />
  """
  attr :status, :atom, required: true
  attr :label, :string, default: nil
  attr :rest, :global

  def status_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide",
        status_class(@status)
      ]}
      {@rest}
    >
      {@label || status_label(@status)}
    </span>
    """
  end

  defp status_label(:ready), do: "Ready"
  defp status_label(:attention), do: "Needs Work"
  defp status_label(:blocked), do: "Missing"
  defp status_label(:info), do: "Setup"

  defp status_class(:ready), do: "bg-success/20 text-success"
  defp status_class(:attention), do: "bg-warning/20 text-warning"
  defp status_class(:blocked), do: "bg-error/20 text-error"
  defp status_class(:info), do: "bg-info/20 text-info"

  @doc """
  Renders an inline severity badge with a status dot, optional count, and label.

  ## Examples

      <.severity_badge severity={:critical} count={3} />
      <.severity_badge severity={:warning} count={12} />
      <.severity_badge severity={:info} />
  """
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
