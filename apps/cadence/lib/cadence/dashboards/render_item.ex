defmodule Cadence.Dashboards.RenderItem do
  @moduledoc """
  Canonical placement render item for dashboard presentation.

  The item carries placement identity/layout plus a dashboard-domain widget
  presenter. It is the active UI boundary for current dashboard components.
  """

  alias Cadence.Dashboards.{Document, Placement, PlacementExpansion, RenderWidget}

  @type t :: %__MODULE__{
          placement: Placement.t(),
          placement_id: binary(),
          layout: map(),
          widget: RenderWidget.t()
        }

  defstruct [
    :placement,
    :placement_id,
    :layout,
    :widget
  ]

  @spec from_document(Document.t(), map() | struct() | nil) :: [t()]
  def from_document(%Document{} = document, scope_context \\ nil) do
    document
    |> PlacementExpansion.expand(scope_context)
    |> Enum.flat_map(&from_placement/1)
  end

  @spec from_placement(Placement.t()) :: [t()]
  def from_placement(%Placement{} = placement) do
    case RenderWidget.from_placement(placement) do
      {:ok, %RenderWidget{} = widget} ->
        [
          %__MODULE__{
            placement: placement,
            placement_id: placement.placement_id,
            layout: placement.layout,
            widget: widget
          }
        ]

      :error ->
        []
    end
  end
end
