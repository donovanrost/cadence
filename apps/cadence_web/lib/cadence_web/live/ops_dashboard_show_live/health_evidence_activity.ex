defmodule CadenceWeb.OpsDashboardShowLive.HealthEvidenceActivity do
  @moduledoc false

  alias Cadence.Dashboards.LifecycleEvent
  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivity

  def build(%{kind: :dashboard_health} = inspector, events) when is_list(events) do
    snapshot_id = snapshot_id(inspector)
    event = matching_event(snapshot_id, events)

    %{
      render?: match?(%LifecycleEvent{}, event),
      event: event,
      event_id: event_id(event),
      snapshot_id: snapshot_id
    }
  end

  def build(_inspector, _events) do
    %{
      render?: false,
      event: nil,
      event_id: nil,
      snapshot_id: nil
    }
  end

  def snapshot_id(%{snapshot_id: snapshot_id}), do: snapshot_id |> value_text() |> empty_to_nil()

  def snapshot_id(%{subject_rows: rows}) when is_list(rows) do
    rows
    |> Enum.find_value(fn
      %{label: "Health snapshot", value: value} -> value_text(value)
      %{"label" => "Health snapshot", "value" => value} -> value_text(value)
      _row -> nil
    end)
    |> empty_to_nil()
  end

  def snapshot_id(_inspector), do: nil

  defp matching_event(nil, _events), do: nil

  defp matching_event(snapshot_id, events) when is_binary(snapshot_id) do
    Enum.find(events, fn
      %LifecycleEvent{event_type: :health_snapshot_captured} = event ->
        HealthSnapshotActivity.snapshot_id(event) == snapshot_id

      _event ->
        false
    end)
  end

  defp event_id(%LifecycleEvent{dashboard_lifecycle_event_id: event_id}), do: event_id
  defp event_id(_event), do: nil

  defp value_text(nil), do: ""
  defp value_text(value) when is_binary(value), do: value
  defp value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp value_text(value), do: to_string(value)

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
