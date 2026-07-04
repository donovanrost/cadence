defmodule CadenceWeb.OpsDashboardShowLive.ContextScopePolicy do
  @moduledoc """
  Resolution policy for context-bound dashboard widgets.

  Context widgets should render once the engine has resolved the current
  operational scope to a concrete selector. This policy intentionally recognizes
  the broader dashboard scope model instead of assuming every context is
  spacecraft-bound.
  """

  alias Cadence.Dashboards.{Frame, PlacementFrames, ScopeContext}

  @scope_kinds [
    :mission,
    :spacecraft,
    :contact,
    :ground_station,
    :source_endpoint,
    :transport,
    :link
  ]

  @all_modes [:all, "all"]

  @spec resolved?(PlacementFrames.t() | Frame.t() | map() | nil) :: boolean()
  def resolved?(%PlacementFrames{primary: [%Frame{} = frame | _rest]}), do: resolved?(frame)
  def resolved?(%PlacementFrames{}), do: false
  def resolved?(%Frame{scope: scope}), do: resolved_scope?(scope)
  def resolved?(scope) when is_map(scope), do: resolved_scope?(scope)
  def resolved?(_scope), do: false

  defp resolved_scope?(scope) when is_map(scope) do
    context = ScopeContext.from_map(scope)

    typed_scope_id?(context) or primary_selector_resolved?(context)
  end

  defp resolved_scope?(_scope), do: false

  defp primary_selector_resolved?(context) do
    primary_kind = ScopeContext.primary_kind(context)

    primary_ids_resolved?(context, primary_kind) or
      all_mode_selector?(context, primary_kind)
  end

  defp primary_ids_resolved?(context, primary_kind) do
    ScopeContext.primary_ids(context) != [] and
      (is_nil(primary_kind) or primary_kind_supported?(primary_kind))
  end

  defp all_mode_selector?(context, primary_kind) do
    primary = context.primary || %{}

    primary_kind_supported?(primary_kind) and Map.get(primary, :mode) in @all_modes
  end

  defp typed_scope_id?(context) do
    Enum.any?(@scope_kinds, fn kind ->
      context
      |> ScopeContext.scope_id(kind)
      |> concrete_id?()
    end)
  end

  defp concrete_id?(id), do: is_binary(id) and id != ""

  defp primary_kind_supported?(kind) when kind in @scope_kinds, do: true

  defp primary_kind_supported?(kind) when is_binary(kind) do
    Enum.any?(@scope_kinds, &(Atom.to_string(&1) == kind))
  end

  defp primary_kind_supported?(_kind), do: false
end
