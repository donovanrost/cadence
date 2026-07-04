defmodule CadenceWeb.OpsDashboardShowLive.DataViewComparison do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.DataContext
  alias CadenceWeb.OpsDashboardShowLive.{RuntimeDataRequest, RuntimeResult}

  defstruct [:primary_result, :comparison_result]

  @type t :: %__MODULE__{
          primary_result: RuntimeResult.result(),
          comparison_result: RuntimeResult.result() | nil
        }

  @spec request(Phoenix.LiveView.Socket.t() | map(), atom()) :: RuntimeDataRequest.t() | nil
  def request(%{assigns: assigns}, resolve_mode), do: request(assigns, resolve_mode)

  def request(assigns, resolve_mode) when is_map(assigns) do
    compare_data_view = compare_data_view(assigns)

    if is_nil(compare_data_view) do
      nil
    else
      assigns
      |> RuntimeDataRequest.from_assigns(resolve_mode)
      |> put_data_view(compare_data_view)
    end
  end

  @spec new(RuntimeResult.result(), RuntimeResult.result() | nil) :: RuntimeResult.result() | t()
  def new(primary_result, nil), do: primary_result

  def new(primary_result, comparison_result),
    do: %__MODULE__{primary_result: primary_result, comparison_result: comparison_result}

  @spec assign_result(Phoenix.LiveView.Socket.t(), RuntimeResult.result() | nil) ::
          Phoenix.LiveView.Socket.t()
  def assign_result(socket, comparison_result) do
    assign(socket, :dashboard_compare_engine_result, comparison_result)
    |> assign(
      :dashboard_compare_engine_frames_by_placement,
      RuntimeResult.frames_by_placement(comparison_result)
    )
  end

  defp compare_data_view(assigns) do
    compare_data_view =
      assigns
      |> Map.get(:dashboard_compare_data_view)
      |> present_string()

    active_data_view =
      assigns
      |> Map.get(:dashboard_data_view)
      |> present_string()

    if is_nil(compare_data_view) or compare_data_view == active_data_view do
      nil
    else
      compare_data_view
    end
  end

  defp put_data_view(%RuntimeDataRequest{} = request, compare_data_view) do
    %RuntimeDataRequest{
      request
      | data_context: data_context_with_view(request.data_context, compare_data_view)
    }
  end

  defp data_context_with_view(%DataContext{} = context, compare_data_view),
    do: %DataContext{context | view: compare_data_view}

  defp data_context_with_view(context, compare_data_view) when is_map(context) do
    context
    |> Map.put("view", compare_data_view)
    |> Map.delete(:view)
  end

  defp data_context_with_view(_context, compare_data_view), do: %{"view" => compare_data_view}

  defp present_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_string(_value), do: nil
end
