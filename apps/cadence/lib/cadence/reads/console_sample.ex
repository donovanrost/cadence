defmodule Cadence.Reads.ConsoleSample do
  @moduledoc """
  §11c(D) D1: one telemetry sample for the console's Investigate (the Sample aside), the read the
  legacy Explore page's "Selected sample" made. It runs the same authorized exploration read
  (`Reads.Dashboards.Exploration`: the dashboard source resolver, then physical inspection on the
  resolved bindings) and the same allowlisted projection (`ExplorationSampleSnapshot`), then adds
  display names beside the ids (ux, U25): each is nil when it can't be resolved, never the id.

  The sample is matched on its receipt time when the caller passes it (exact). Without it, `at`
  (its generation time, as alarm triggers carry it) bounds the search to ±60 s; with neither, the
  last 24 hours. The read never pages display rows (limit 1), and source execution's own budget
  (5 s) ends a slow read as status `timeout` rather than holding a connection.
  """

  import Ecto.Query

  alias Cadence.Auth.Scope
  alias Cadence.Reads.Dashboards.{Exploration, ExplorationSampleSnapshot}
  alias Cadence.Reads.{DataSourceDirectory, OperationalState, PointInfo, SampleOrigin}
  alias Cadence.Repo

  @type selection :: %{
          sample_id: binary(),
          point_id: binary(),
          spacecraft_id: binary(),
          receipt_time: DateTime.t() | nil,
          at: DateTime.t() | nil
        }

  @spec load(Scope.t(), binary(), selection(), keyword()) ::
          %{status: binary(), sample: map() | nil}
  def load(%Scope{} = scope, mission_id, selection, opts \\ []) do
    case Exploration.load(scope, mission_id, params(selection), opts) do
      {:ok, %{query: query, request: request, result: result, selected_sample: selected}} ->
        selected
        |> ExplorationSampleSnapshot.build(query, request)
        |> named(scope.organization_id, mission_id, result)

      {:error, _reason} ->
        %{status: "unavailable", sample: nil}
    end
  end

  defp params(%{receipt_time: %DateTime{} = at} = selection) do
    selection
    |> base_params()
    |> Map.merge(%{
      "selected_time" => DateTime.to_iso8601(at),
      # The window is on the receipt clock, the one the match is on.
      "time_axis" => "receipt_time",
      "time_mode" => "range",
      "from" => at |> DateTime.add(-1, :second) |> DateTime.to_iso8601(),
      "to" => at |> DateTime.add(1, :second) |> DateTime.to_iso8601()
    })
  end

  defp params(%{at: %DateTime{} = at} = selection) do
    selection
    |> base_params()
    |> Map.merge(%{
      "time_axis" => "generation_time",
      "time_mode" => "range",
      "from" => at |> DateTime.add(-60, :second) |> DateTime.to_iso8601(),
      "to" => at |> DateTime.add(60, :second) |> DateTime.to_iso8601()
    })
  end

  defp params(selection), do: selection |> base_params() |> Map.put("time_mode", "last_24h")

  defp base_params(selection),
    do: %{
      "point_id" => selection.point_id,
      "spacecraft_id" => selection.spacecraft_id,
      "sample_id" => selection.sample_id,
      # Only the one sample is wanted, never a page of display rows.
      "limit" => "1"
    }

  defp named(%{status: "ready", sample: sample}, org, mission, result) do
    resolved = resolved_binding(result, sample.source)

    sample =
      sample
      |> Map.put(:engineering_unit, PointInfo.fetch(org, mission, sample.point_id).unit)
      |> Map.update!(:source, &source_names(&1, org, mission, resolved))
      |> Map.update!(:record, &record_names(&1, org, mission))
      |> Map.merge(origin(mission, sample))

    %{status: "ready", sample: sample}
  end

  defp named(%{status: status}, _org, _mission, _result), do: %{status: status, sample: nil}

  # Where its packet came from (#1078 E1a), from the archived packet: `origin`, or `origin_reason`
  # saying why there is none. One lookup for the one sample.
  defp origin(mission, sample) do
    SampleOrigin.for_sample(mission, %{
      sample_id: sample.sample_id,
      packet_id: sample.record.packet_id,
      packet_definition_id: sample.record.packet_definition_id
    })
  end

  defp source_names(source, org, mission, resolved) do
    Map.merge(source, %{
      data_source_name: resolved && DataSourceDirectory.name(resolved.data_source),
      binding_label: resolved && label(resolved.binding.metadata),
      binding_version: resolved && resolved.binding.binding_version,
      endpoint_label: endpoint_label(org, mission, source.source_endpoint_id),
      replay_run_label: replay_run_label(org, mission, source.replay_run_id)
    })
  end

  defp record_names(record, org, mission) do
    Map.put(
      record,
      :packet_definition_name,
      packet_name(org, mission, record.packet_definition_id, record.packet_definition_version)
    )
  end

  defp resolved_binding(%{resolved_bindings_by_request_id: by_request}, source)
       when is_map(by_request) do
    by_request
    |> Map.values()
    |> List.flatten()
    |> Enum.find(fn resolved ->
      resolved.data_source.data_source_id == source.data_source_id and
        resolved.binding.binding_id == source.source_binding_id
    end)
  end

  defp resolved_binding(_result, _source), do: nil

  defp label(%{} = metadata), do: text(metadata["display_name"] || metadata["label"])
  defp label(_metadata), do: nil

  defp endpoint_label(_org, _mission, nil), do: nil

  defp endpoint_label(org, mission, endpoint_id) do
    case OperationalState.fetch_source_endpoint(org, mission, endpoint_id) do
      {:ok, endpoint} -> text(endpoint.display_name)
      _missing -> nil
    end
  end

  defp packet_name(_org, _mission, nil, _version), do: nil

  defp packet_name(org, mission, definition_id, version) do
    from(d in "governed_packet_definitions",
      where:
        d.organization_id == ^org and d.mission_id == ^mission and
          d.packet_definition_id == ^definition_id,
      order_by: [desc: d.version],
      select: {d.version, d.packet_name}
    )
    |> Repo.all()
    |> then(fn rows -> List.keyfind(rows, version, 0) || List.first(rows) end)
    |> case do
      {_version, name} -> text(name)
      nil -> nil
    end
  end

  defp replay_run_label(_org, _mission, nil), do: nil

  defp replay_run_label(org, mission, run_id) do
    from(r in "replay_runs",
      where:
        r.organization_id == ^org and r.mission_id == ^mission and r.replay_run_id == ^run_id,
      select: fragment("?->>'label'", r.metadata)
    )
    |> Repo.one()
    |> text()
  end

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil
end
