defmodule Cadence.Dashboards.Sources.Telemetry.PhysicalSampleRequest do
  @moduledoc """
  Compiles a physical selection within an already-authorized planned request.

  Unlike history options, unsupported scope and clock constraints are errors.
  Selection may narrow sample identity but cannot supply tenant/source context.
  """

  alias Cadence.Dashboards.{
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ScopeContext,
    TimeContext
  }

  alias Cadence.Dashboards.Sources.Telemetry.FrameContext
  alias Cadence.Telemetry.PhysicalSampleQuery

  @scope_fields [:mission_id, :spacecraft_id, :source_endpoint_id]
  @filter_fields [:mission_ids, :spacecraft_ids, :source_endpoint_ids]
  @allowed_filters @filter_fields ++ Enum.map(@filter_fields, &Atom.to_string/1)

  def build(
        %PlannedSourceRequest{logical_source: :telemetry} = request,
        %ResolvedSourceBinding{} = binding,
        selection
      )
      when is_map(selection) do
    with true <- not is_struct(selection),
         true <- Enum.all?(Map.keys(selection), &(&1 in [:point_id, :sample_id, :receipt_time])),
         true <- selection[:point_id] in request.observables,
         {:ok, scope} <- scope(request.scope_context, request.mission_id),
         {:ok, times} <- times(request.time_context, binding),
         :ok <- replay_context(request) do
      %{
        organization_id: request.organization_id,
        mission_id: request.mission_id,
        point_id: selection[:point_id],
        sample_id: selection[:sample_id],
        receipt_time: selection[:receipt_time],
        realm: binding.realm,
        data_source_id: binding.data_source.data_source_id,
        source_binding_id: binding.binding.binding_id,
        replay_run_id: FrameContext.replay_run_id(request)
      }
      |> Map.merge(scope)
      |> Map.merge(times)
      |> PhysicalSampleQuery.new()
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_physical_sample_selection}
    end
  rescue
    _ -> {:error, :invalid_physical_sample_selection}
  end

  def build(_, _, _), do: {:error, :invalid_physical_sample_selection}

  defp scope(%ScopeContext{} = scope, mission) do
    filters = scope.filters || %{}

    with true <- is_map(filters),
         true <- Enum.all?(Map.keys(filters), &(&1 in @allowed_filters)),
         true <-
           Enum.all?(
             [:contact_id, :ground_station_id, :transport_id, :link_id],
             &is_nil(Map.get(scope, &1))
           ),
         {:ok, primary} <- primary(scope.primary),
         {:ok, [mission_ids, spacecraft_ids, endpoints]} <- constraints(scope, filters, primary),
         true <- is_nil(mission_ids) or mission_ids == [mission],
         true <- is_nil(spacecraft_ids) or length(spacecraft_ids) == 1 do
      {:ok,
       %{spacecraft_id: spacecraft_ids && hd(spacecraft_ids), source_endpoint_ids: endpoints}}
    else
      _ -> {:error, :unsupported_physical_sample_scope}
    end
  end

  defp scope(_, _), do: {:error, :unsupported_physical_sample_scope}

  defp primary(nil), do: {:ok, %{}}

  defp primary(%{kind: kind, mode: mode, ids: ids} = selector)
       when mode in [nil, :one, "one", :many, "many", :context, "context"] do
    field =
      %{
        "mission" => :mission_id,
        "spacecraft" => :spacecraft_id,
        "source_endpoint" => :source_endpoint_id,
        mission: :mission_id,
        spacecraft: :spacecraft_id,
        source_endpoint: :source_endpoint_id
      }[kind]

    if field && Enum.all?(Map.keys(selector), &(&1 in [:kind, :mode, :ids])) && valid_ids?(ids) &&
         (mode in [:many, "many"] or length(ids) == 1),
       do: {:ok, %{field => ids}},
       else: :error
  end

  defp primary(_), do: :error

  defp constraints(scope, filters, primary) do
    Enum.zip(@scope_fields, @filter_fields)
    |> Enum.reduce_while({:ok, []}, fn {field, filter}, {:ok, acc} ->
      sets =
        [
          typed_ids(Map.get(scope, field)),
          Map.get(primary, field),
          Map.get(filters, filter),
          Map.get(filters, Atom.to_string(filter))
        ]
        |> Enum.reject(&is_nil/1)

      case intersect(sets) do
        {:ok, ids} -> {:cont, {:ok, acc ++ [ids]}}
        _ -> {:halt, :error}
      end
    end)
  end

  defp typed_ids(nil), do: nil
  defp typed_ids(id), do: [id]
  defp intersect([]), do: {:ok, nil}

  defp intersect([first | rest] = sets) do
    if Enum.all?(sets, &valid_ids?/1) do
      ids = Enum.reduce(rest, first, fn set, acc -> Enum.filter(acc, &(&1 in set)) end)
      if ids == [], do: :error, else: {:ok, ids}
    else
      :error
    end
  end

  defp valid_ids?(ids) when is_list(ids),
    do:
      length(ids) in 1..100 and Enum.all?(ids, &valid_id?/1) and
        Enum.uniq(ids) == ids

  defp valid_ids?(_), do: false

  defp valid_id?(id) when is_binary(id),
    do:
      byte_size(id) in 1..256 and String.valid?(id) and
        not String.match?(id, ~r/[\x00-\x1f\x7f]/u)

  defp valid_id?(_), do: false

  defp times(%TimeContext{} = time, binding) do
    with true <- time.axis in [:receipt_time, "receipt_time", :generation_time, "generation_time"],
         true <-
           time.mode in [
             :live,
             "live",
             :range,
             "range",
             :archive,
             "archive",
             :replay_run,
             "replay_run"
           ],
         true <- is_nil(time.range),
         {:ok, from} <- clock([time.from, time.start, time.start_time]),
         {:ok, to} <- clock([time.to, time.end, time.end_time]),
         true <- is_nil(time.window_seconds) or (not is_nil(from) and not is_nil(to)),
         true <- time.mode in [:live, "live"] or (not is_nil(from) and not is_nil(to)),
         {:ok, from, to} <- segment(from, to, binding) do
      if time.axis in [:receipt_time, "receipt_time"],
        do: {:ok, %{from_receipt_time: from, to_receipt_time: to}},
        else: {:ok, %{from_observed_at: from, to_observed_at: to}}
    else
      _ -> {:error, :unsupported_physical_sample_time}
    end
  end

  defp times(_, _), do: {:error, :unsupported_physical_sample_time}

  defp clock(values) do
    case Enum.reject(values, &is_nil/1) do
      [] ->
        {:ok, nil}

      [%DateTime{} = first | rest] ->
        if valid_clock?(first) and
             Enum.all?(rest, &(valid_clock?(&1) and DateTime.compare(first, &1) == :eq)),
           do: {:ok, first},
           else: :error

      _ ->
        :error
    end
  end

  defp segment(from, to, %{segment_from: nil, segment_to: nil}), do: {:ok, from, to}

  defp segment(from, to, %{segment_from: %DateTime{} = start, segment_to: %DateTime{} = finish}) do
    if valid_clock?(start) and valid_clock?(finish) and DateTime.compare(start, finish) != :gt,
      do: {:ok, later(from, start), earlier(to, finish)},
      else: :error
  end

  defp segment(_, _, _), do: :error
  defp later(nil, right), do: right
  defp later(left, right), do: if(DateTime.compare(left, right) == :gt, do: left, else: right)
  defp earlier(nil, right), do: right
  defp earlier(left, right), do: if(DateTime.compare(left, right) == :lt, do: left, else: right)

  defp valid_clock?(%DateTime{calendar: Calendar.ISO} = value) do
    case DateTime.from_iso8601(DateTime.to_iso8601(value)) do
      {:ok, parsed, _} -> DateTime.compare(value, parsed) == :eq
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_clock?(_), do: false

  defp replay_context(request) do
    time_run = request.time_context.replay_run_id
    run = FrameContext.replay_run_id(request)

    if is_nil(time_run) or time_run == run,
      do: :ok,
      else: {:error, :invalid_physical_sample_selection}
  end
end
