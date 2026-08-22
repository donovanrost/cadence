defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDataRequest do
  @moduledoc false

  alias Cadence.Dashboards.{DashboardResolveRequest, Document}
  alias CadenceWeb.OpsDashboardShowLive.RuntimeAssigns

  @fields [
    :organization_id,
    :mission_id,
    :dashboard_id,
    :document,
    :document_mode,
    :resolve_mode,
    :scope_context,
    :time_context,
    :data_context,
    :limit_context
  ]

  defstruct @fields

  @type t :: %__MODULE__{
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          dashboard_id: binary() | nil,
          document: Document.t() | nil,
          document_mode: DashboardResolveRequest.document_mode() | nil,
          resolve_mode: DashboardResolveRequest.resolve_mode() | nil,
          scope_context: map() | struct() | nil,
          time_context: map() | struct() | nil,
          data_context: map() | struct() | nil,
          limit_context: map() | struct() | nil
        }

  @field_set MapSet.new(@fields)

  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = request), do: request

  def new(attrs) when is_map(attrs) do
    attrs
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case request_field(key) do
        nil -> acc
        field -> Map.put(acc, field, value)
      end
    end)
    |> then(&struct!(__MODULE__, &1))
  end

  @spec from_socket(Phoenix.LiveView.Socket.t() | map(), DashboardResolveRequest.resolve_mode()) ::
          t()
  def from_socket(%{assigns: assigns}, resolve_mode), do: from_assigns(assigns, resolve_mode)

  @spec from_assigns(map(), DashboardResolveRequest.resolve_mode()) :: t()
  def from_assigns(assigns, resolve_mode) when is_map(assigns) do
    assigns
    |> RuntimeAssigns.engine_request_attrs(resolve_mode)
    |> new()
  end

  @spec to_engine_request(t() | map()) :: DashboardResolveRequest.t()
  def to_engine_request(request) when is_map(request) do
    request = new(request)

    DashboardResolveRequest.new(%{
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      dashboard_id: request.dashboard_id,
      document: request.document,
      document_mode: request.document_mode,
      resolve_mode: request.resolve_mode,
      scope_context: request.scope_context,
      time_context: request.time_context,
      data_context: request.data_context,
      limit_context: request.limit_context
    })
  end

  defp request_field(key) when is_atom(key) do
    if MapSet.member?(@field_set, key), do: key
  end

  defp request_field(key) when is_binary(key) do
    key
    |> String.to_existing_atom()
    |> request_field()
  rescue
    ArgumentError -> nil
  end

  defp request_field(_key), do: nil
end
