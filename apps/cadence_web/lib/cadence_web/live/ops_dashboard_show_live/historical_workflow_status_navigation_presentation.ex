defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.RouteQuery

  @type comparison_review_links :: %{
          review_href: binary() | nil,
          placement_links: [%{placement_id: binary(), href: binary()}]
        }

  @type lifecycle_handoff :: %{
          event_id: binary(),
          role: binary(),
          label: binary(),
          href: binary()
        }

  @type failed_item_handoff :: %{
          label: binary() | nil,
          run_id: binary() | nil,
          event_id: binary(),
          recovery_action: binary() | nil,
          retryable: binary() | nil,
          href: binary()
        }

  @spec comparison_review_links(map() | nil, binary() | nil) :: comparison_review_links()
  def comparison_review_links(workflow_context, current_path)
      when is_map(workflow_context) and is_binary(current_path) do
    request_event_id = Map.get(workflow_context, :comparison_review_request_event_id)

    if present_text?(request_event_id) do
      %{
        review_href:
          ActivityNavigation.open_comparison_review_link(current_path, request_event_id),
        placement_links:
          workflow_context
          |> Map.get(:comparison_review_open_placement_ids)
          |> placement_ids()
          |> Enum.map(fn placement_id ->
            %{
              placement_id: placement_id,
              href:
                ActivityNavigation.open_comparison_review_link(current_path, request_event_id,
                  selected_placement: placement_id
                )
            }
          end)
      }
    else
      empty_comparison_review_links()
    end
  end

  def comparison_review_links(_workflow_context, _current_path),
    do: empty_comparison_review_links()

  @spec latest_action_handoffs(map() | nil, binary() | nil) :: [lifecycle_handoff()]
  def latest_action_handoffs(outcome, current_path)
      when is_map(outcome) and is_binary(current_path) do
    target_event_id = Map.get(outcome, :target_event_id)
    result_event_ids = outcome |> Map.get(:result_event_ids) |> event_ids()

    [target_event_id | result_event_ids]
    |> Enum.reject(&(not present_text?(&1)))
    |> Enum.uniq()
    |> Enum.reduce({[], 0}, fn event_id, {handoffs, result_count} ->
      role = handoff_role(event_id, target_event_id, result_event_ids)
      {label, result_count} = handoff_label(role, result_count)

      handoff = %{
        event_id: event_id,
        role: role,
        label: label,
        href: lifecycle_event_handoff_link(current_path, event_id)
      }

      {[handoff | handoffs], result_count}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def latest_action_handoffs(_outcome, _current_path), do: []

  @spec primary_handoff_event_id([lifecycle_handoff()]) :: binary() | nil
  def primary_handoff_event_id([%{event_id: event_id} | _handoffs]), do: event_id
  def primary_handoff_event_id(_handoffs), do: nil

  @spec group_failed_item_handoffs(map() | nil, binary() | nil) :: [failed_item_handoff()]
  def group_failed_item_handoffs(workflow_context, current_path)
      when is_map(workflow_context) and is_binary(current_path) do
    workflow_context
    |> Map.get(:request_group_failed_item_events)
    |> group_failed_item_event_entries()
    |> Enum.map(fn entry ->
      Map.put(entry, :href, lifecycle_event_handoff_link(current_path, entry.event_id))
    end)
  end

  def group_failed_item_handoffs(_workflow_context, _current_path), do: []

  defp handoff_role(event_id, target_event_id, result_event_ids) do
    cond do
      event_id == target_event_id and event_id in result_event_ids -> "target_result"
      event_id == target_event_id -> "target"
      true -> "result"
    end
  end

  defp handoff_label("target_result", result_count), do: {"Selected result", result_count}
  defp handoff_label("target", result_count), do: {"Selected event", result_count}
  defp handoff_label(_role, result_count), do: {"Result #{result_count + 1}", result_count + 1}

  defp group_failed_item_event_entries(value) when is_binary(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.map(&group_failed_item_event_entry/1)
    |> Enum.reject(&(Map.get(&1, :event_id) in [nil, ""]))
  end

  defp group_failed_item_event_entries(_value), do: []

  defp group_failed_item_event_entry(value) do
    tokens =
      value
      |> String.trim()
      |> String.split(" ", trim: true)
      |> Map.new(fn token ->
        case String.split(token, "=", parts: 2) do
          [key, token_value] -> {key, decode_token_value(token_value)}
          [key] -> {key, nil}
        end
      end)

    %{
      label: Map.get(tokens, "label") || Map.get(tokens, "event"),
      run_id: Map.get(tokens, "run"),
      event_id: Map.get(tokens, "event"),
      recovery_action: Map.get(tokens, "recovery"),
      retryable: Map.get(tokens, "retryable")
    }
  end

  defp decode_token_value(nil), do: nil

  defp decode_token_value(value) when is_binary(value) do
    URI.decode(value)
  rescue
    ArgumentError -> value
  end

  defp lifecycle_event_handoff_link(current_path, event_id)
       when is_binary(current_path) and is_binary(event_id) do
    current_path
    |> URI.parse()
    |> put_lifecycle_event_query(event_id)
    |> URI.to_string()
  end

  defp put_lifecycle_event_query(%URI{} = uri, event_id) do
    query =
      (uri.query || "")
      |> URI.decode_query()
      |> RouteQuery.merge(%{
        "panel" => "data_link",
        "selected_target" => "telemetry_backfill_lifecycle_event",
        "selected_id" => event_id,
        "activity_filter" => nil,
        "activity_event" => nil,
        "selected_placement" => nil
      })

    %{uri | query: RouteQuery.encode(query)}
  end

  defp event_ids(value) when is_binary(value) do
    value
    |> String.split([",", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp event_ids(_value), do: []

  defp placement_ids(value) when is_binary(value) do
    value
    |> String.split([",", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(_value), do: []

  defp empty_comparison_review_links, do: %{review_href: nil, placement_links: []}

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false
end
