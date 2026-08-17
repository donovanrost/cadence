defmodule Cadence.Dashboards.HydratedResolveRequest do
  @moduledoc """
  Typed input boundary for dashboard planning.

  A hydrated request has a normalized resolve request and a materialized widget
  definition for every library-backed placement. Constructing this value is a
  pure validation step; persistence-backed resolution belongs in
  `Cadence.Dashboards.ResolveRequestHydrator`.
  """

  alias Cadence.Dashboards.{DashboardResolveRequest, Document, Placement, WidgetDef}

  @enforce_keys [:request]
  defstruct [:request]

  @type hydration_error ::
          :document_required | {:unresolved_library_placements, [binary() | nil]}

  @type t :: %__MODULE__{request: DashboardResolveRequest.t()}

  @spec new(DashboardResolveRequest.t()) :: {:ok, t()} | {:error, hydration_error()}
  def new(%DashboardResolveRequest{} = request) do
    request = DashboardResolveRequest.normalize(request)

    case request.document do
      %Document{} = document ->
        case unresolved_library_placement_ids(document) do
          [] -> {:ok, %__MODULE__{request: request}}
          placement_ids -> {:error, {:unresolved_library_placements, placement_ids}}
        end

      _other ->
        {:error, :document_required}
    end
  end

  @spec new!(DashboardResolveRequest.t()) :: t()
  def new!(%DashboardResolveRequest{} = request) do
    case new(request) do
      {:ok, hydrated_request} ->
        hydrated_request

      {:error, reason} ->
        raise ArgumentError, "dashboard resolve request is not hydrated: #{inspect(reason)}"
    end
  end

  @spec unwrap(t()) :: DashboardResolveRequest.t()
  def unwrap(%__MODULE__{request: request}), do: request

  defp unresolved_library_placement_ids(%Document{} = document) do
    document.placements
    |> Enum.filter(&unresolved_library_placement?/1)
    |> Enum.map(& &1.placement_id)
  end

  defp unresolved_library_placement?(%Placement{content_kind: :library, widget_def: widget_def}),
    do: not match?(%WidgetDef{}, widget_def)

  defp unresolved_library_placement?(%Placement{}), do: false
end
