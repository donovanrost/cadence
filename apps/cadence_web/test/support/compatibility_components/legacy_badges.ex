defmodule CadenceWeb.Components.Badges do
  @moduledoc """
  Status pills.

  `status_badge/1` uses the shared readiness vocabulary
  (`:ready/:attention/:blocked/:info`).
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
end
