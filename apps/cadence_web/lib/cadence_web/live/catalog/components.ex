defmodule CadenceWeb.Catalog.Components do
  @moduledoc false
  use CadenceWeb, :html

  @doc "Colored badge for a catalog family atom (`:telemetry | :command | :combined`)."
  attr :family, :atom, required: true

  def catalog_family_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      family_badge_class(@family)
    ]}>
      {family_label(@family)}
    </span>
    """
  end

  defp family_badge_class(:telemetry), do: "badge-info"
  defp family_badge_class(:command), do: "badge-warning"
  defp family_badge_class(:combined), do: "badge-primary"
  defp family_badge_class(_), do: "badge-ghost"

  defp family_label(:telemetry), do: "Telemetry"
  defp family_label(:command), do: "Command"
  defp family_label(:combined), do: "Combined"

  defp family_label(other) when is_atom(other),
    do: other |> Atom.to_string() |> String.capitalize()

  @doc "Colored badge for an import run status."
  attr :status, :atom, required: true

  def import_run_status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      status_badge_class(@status)
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  defp status_badge_class(:running), do: "badge-info"
  defp status_badge_class(:completed), do: "badge-success"
  defp status_badge_class(:failed), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

  defp status_label(:running), do: "Running"
  defp status_label(:completed), do: "Completed"
  defp status_label(:failed), do: "Failed"
  defp status_label(other), do: other |> to_string() |> String.capitalize()

  @doc "Grouped diagnostic list for an import run."
  attr :diagnostics, :list, required: true

  def diagnostic_list(assigns) do
    assigns = assign(assigns, :groups, group_diagnostics(assigns.diagnostics))

    ~H"""
    <div :if={@diagnostics != []} class="space-y-3">
      <div :for={{severity, items} <- @groups} class="card bg-base-200">
        <div class="card-body p-4">
          <p class="hud-label mb-2">{severity_heading(severity)} ({length(items)})</p>
          <ul class="space-y-2">
            <li :for={diagnostic <- items} class="text-sm">
              <span class="font-mono text-xs text-base-content/60">{diagnostic.code}</span>
              <span class="ml-2">{diagnostic.message}</span>
              <p :if={diagnostic.path != []} class="text-xs text-base-content/50 font-mono mt-1">
                {Enum.join(diagnostic.path, " / ")}
              </p>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp group_diagnostics(diagnostics) do
    [:error, :warning, :info]
    |> Enum.map(fn severity ->
      {severity, Enum.filter(diagnostics, &(&1.severity == severity))}
    end)
    |> Enum.reject(fn {_, items} -> items == [] end)
  end

  defp severity_heading(:error), do: "Errors"
  defp severity_heading(:warning), do: "Warnings"
  defp severity_heading(:info), do: "Info"

  @doc "Summary count card for a snapshot (telemetry or command)."
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :counts, :list, required: true, doc: "Keyword list of {label, integer}."
  attr :navigate, :string, default: nil

  def snapshot_summary_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <div class="flex items-center gap-2 mb-3">
          <span class={[@icon, "h-4 w-4"]}></span>
          <p class="hud-label">{@title}</p>
        </div>
        <dl class="grid grid-cols-2 gap-2 text-sm">
          <div :for={{label, count} <- @counts} class="contents">
            <dt class="text-base-content/60">{label}</dt>
            <dd class="font-mono text-base-content text-right">{count}</dd>
          </div>
        </dl>
        <div :if={@navigate} class="card-actions justify-end mt-3">
          <.link navigate={@navigate} class="btn btn-ghost btn-xs">
            View details <span class="hero-arrow-right h-3 w-3 ml-1"></span>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
