defmodule Cadence.Dashboards.Sources.Telemetry.FrameBuilder do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    SourceActions,
    TelemetryActions
  }

  alias Cadence.Dashboards.Sources.Telemetry.FrameContext
  alias Cadence.Telemetry.Sample

  @spec latest(
          PlannedSourceRequest.t(),
          map() | nil,
          binary(),
          Sample.t() | nil,
          [map()],
          map()
        ) :: Frame.t()
  def latest(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        sample,
        warnings,
        source_filter_context
      ) do
    value_type = FrameContext.value_type(request)
    samples = List.wrap(sample)
    values = Enum.map(samples, &sample_value(&1, value_type))
    times = Enum.map(samples, &sample_time/1)
    time_axis = latest_time_axis(sample)
    evidence = telemetry_evidence_refs(source_binding, samples)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :telemetry,
      shape: :scalar,
      time_axis: time_axis,
      scope: request.scope_context,
      overlays: %{requested: request.overlays || []},
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: times,
          metadata: %{axis: time_axis}
        },
        %Field{
          name: observable_id,
          kind: field_kind(values),
          values: values,
          metadata: field_metadata(request, source_binding, observable_id, value_type, samples)
        }
      ],
      meta:
        %{
          source_request_id: request.request_id,
          observable_id: observable_id,
          point_id: observable_id,
          logical_source: :telemetry,
          source_binding_id: FrameContext.source_binding_id(source_binding),
          dataset: FrameContext.dataset(source_binding),
          data_view: FrameContext.data_view(request),
          analysis_basis: FrameContext.analysis_basis(request),
          sampling: :latest,
          value_type: value_type,
          latest?: true,
          realm: FrameContext.realm(request, source_binding),
          data_source_id: FrameContext.data_source_id(request, source_binding),
          replay_run_id: FrameContext.replay_run_id(request),
          returned_points: length(samples),
          truncated?: false,
          evidence: evidence,
          links:
            DataLinks.telemetry_links(request, observable_id, samples,
              source: :frame,
              source_binding: source_binding
            ),
          actions: explore_actions(request, source_binding, observable_id, samples, :frame),
          warning_codes: Enum.map(warnings, & &1.code)
        }
        |> Map.merge(source_filter_context)
    }
  end

  @spec history(
          PlannedSourceRequest.t(),
          map() | nil,
          binary(),
          [Sample.t()],
          [map()],
          map(),
          map()
        ) :: Frame.t()
  def history(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        samples,
        warnings,
        diagnostics,
        source_filter_context
      ) do
    value_type = FrameContext.value_type(request)
    values = Enum.map(samples, &sample_value(&1, value_type))
    time_axis = bounded_history_axis(request, source_filter_context)
    times = Enum.map(samples, &sample_time(&1, time_axis))
    evidence = telemetry_evidence_refs(source_binding, samples)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :telemetry,
      shape: :wide,
      time_axis: time_axis,
      scope: request.scope_context,
      overlays: %{requested: request.overlays || []},
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: times,
          metadata: %{axis: time_axis}
        },
        %Field{
          name: observable_id,
          kind: field_kind(values),
          values: values,
          metadata: field_metadata(request, source_binding, observable_id, value_type, samples)
        }
      ],
      meta:
        %{
          source_request_id: request.request_id,
          observable_id: observable_id,
          point_id: observable_id,
          logical_source: :telemetry,
          source_binding_id: FrameContext.source_binding_id(source_binding),
          dataset: FrameContext.dataset(source_binding),
          data_view: FrameContext.data_view(request),
          analysis_basis: FrameContext.analysis_basis(request),
          sampling: FrameContext.sampling_mode(request),
          value_type: value_type,
          realm: FrameContext.realm(request, source_binding),
          data_source_id: FrameContext.data_source_id(request, source_binding),
          replay_run_id: FrameContext.replay_run_id(request),
          returned_points: length(samples),
          truncated?: length(samples) >= FrameContext.raw_point_limit(request),
          evidence: evidence,
          links:
            DataLinks.telemetry_links(request, observable_id, samples,
              source: :frame,
              source_binding: source_binding
            ),
          actions: explore_actions(request, source_binding, observable_id, samples, :frame),
          history_diagnostics: diagnostics,
          warning_codes: Enum.map(warnings, & &1.code)
        }
        |> Map.merge(source_filter_context)
    }
  end

  @spec decimated(
          PlannedSourceRequest.t(),
          map() | nil,
          binary(),
          [map()],
          [map()],
          map(),
          map()
        ) :: Frame.t()
  def decimated(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        buckets,
        warnings,
        diagnostics,
        source_filter_context
      ) do
    value_type = FrameContext.value_type(request)
    evidence = source_binding_interval_evidence_refs(source_binding)

    field_metadata =
      decimated_field_metadata(request, source_binding, observable_id, value_type, buckets)

    time_axis = bounded_history_axis(request, source_filter_context)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :telemetry,
      shape: :wide,
      time_axis: time_axis,
      scope: request.scope_context,
      overlays: %{requested: request.overlays || []},
      fields: [
        %Field{
          name: "bucket_start",
          kind: :time,
          values: Enum.map(buckets, &bucket_value(&1, :bucket_start)),
          metadata: %{axis: time_axis}
        },
        %Field{
          name: "bucket_end",
          kind: :time,
          values: Enum.map(buckets, &bucket_value(&1, :bucket_end)),
          metadata: %{axis: time_axis}
        },
        %Field{
          name: "#{observable_id}_min",
          kind: :number,
          values: Enum.map(buckets, &bucket_value(&1, :min)),
          metadata: field_metadata
        },
        %Field{
          name: "#{observable_id}_max",
          kind: :number,
          values: Enum.map(buckets, &bucket_value(&1, :max)),
          metadata: field_metadata
        },
        %Field{
          name: "#{observable_id}_value",
          kind: :number,
          values: Enum.map(buckets, &bucket_representative_value/1),
          metadata: field_metadata
        },
        %Field{
          name: "#{observable_id}_sample_count",
          kind: :number,
          values: Enum.map(buckets, &bucket_value(&1, :sample_count)),
          metadata: field_metadata
        }
      ],
      meta:
        %{
          source_request_id: request.request_id,
          observable_id: observable_id,
          point_id: observable_id,
          logical_source: :telemetry,
          source_binding_id: FrameContext.source_binding_id(source_binding),
          dataset: FrameContext.dataset(source_binding),
          data_view: FrameContext.data_view(request),
          analysis_basis: FrameContext.analysis_basis(request),
          sampling: :decimated_envelope,
          decimation: :native_min_max_envelope,
          canonical_mode: :physical,
          aggregate_semantics: :physical_as_recorded,
          bucket_width_ms: FrameContext.bucket_width_ms(request),
          target_points: FrameContext.target_points(request),
          value_type: value_type,
          realm: FrameContext.realm(request, source_binding),
          data_source_id: FrameContext.data_source_id(request, source_binding),
          replay_run_id: FrameContext.replay_run_id(request),
          returned_points: length(buckets),
          truncated?: false,
          evidence: evidence,
          links:
            DataLinks.telemetry_links(request, observable_id, [],
              source: :frame,
              source_binding: source_binding
            ),
          actions: explore_actions(request, source_binding, observable_id, [], :frame),
          decimated_diagnostics: diagnostics,
          warning_codes: Enum.map(warnings, & &1.code)
        }
        |> Map.merge(source_filter_context)
    }
  end

  defp field_metadata(request, source_binding, observable_id, value_type, samples) do
    %{
      observable_id: observable_id,
      point_id: observable_id,
      data_view: FrameContext.data_view(request),
      analysis_basis: FrameContext.analysis_basis(request),
      value_type: value_type,
      unit: sample_unit(samples),
      quality_states: samples |> Enum.map(& &1.quality_state) |> Enum.uniq(),
      sample_ids: Enum.map(samples, & &1.sample_id),
      evidence_ids: samples |> Enum.map(& &1.evidence_id) |> Enum.reject(&is_nil/1),
      evidence: telemetry_evidence_refs(source_binding, samples),
      links:
        DataLinks.telemetry_links(request, observable_id, samples,
          source: :field,
          source_binding: source_binding
        ),
      actions: explore_actions(request, source_binding, observable_id, samples, :field)
    }
  end

  defp decimated_field_metadata(request, source_binding, observable_id, value_type, buckets) do
    %{
      observable_id: observable_id,
      point_id: observable_id,
      data_view: FrameContext.data_view(request),
      analysis_basis: FrameContext.analysis_basis(request),
      value_type: value_type,
      unit: bucket_unit(buckets),
      decimated?: true,
      decimation: :native_min_max_envelope,
      canonical_mode: :physical,
      aggregate_semantics: :physical_as_recorded,
      quality_states:
        buckets
        |> Enum.map(&bucket_value(&1, :worst_quality_state))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      validity_states:
        buckets
        |> Enum.map(&bucket_value(&1, :worst_validity_state))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      evidence: source_binding_interval_evidence_refs(source_binding),
      links:
        DataLinks.telemetry_links(request, observable_id, [],
          source: :field,
          source_binding: source_binding
        ),
      actions: explore_actions(request, source_binding, observable_id, [], :field)
    }
  end

  defp telemetry_evidence_refs(source_binding, samples) do
    (DataLinks.telemetry_sample_evidence_refs(samples) ++
       source_binding_interval_evidence_refs(source_binding))
    |> Enum.uniq_by(&evidence_identity/1)
  end

  defp source_binding_interval_evidence_refs(%{binding_interval: interval})
       when not is_nil(interval) do
    DataLinks.source_binding_interval_evidence_refs([interval], source: :telemetry)
  end

  defp source_binding_interval_evidence_refs(_source_binding), do: []

  defp explore_actions(request, source_binding, observable_id, samples, source) do
    telemetry_actions =
      TelemetryActions.explore_actions(request, observable_id, samples,
        source: source,
        source_binding: source_binding,
        action_id: "telemetry-explore:#{request.request_id}:#{observable_id}:#{source}"
      )

    source_inventory_action =
      SourceActions.source_inventory_action(
        %{
          logical_source: :telemetry,
          realm: FrameContext.realm(request, source_binding),
          data_source_id: FrameContext.data_source_id(request, source_binding),
          source_binding_id: FrameContext.source_binding_id(source_binding),
          dataset: FrameContext.dataset(source_binding)
        },
        source: source,
        inventory_action_id: "source-inventory:#{request.request_id}:#{observable_id}:#{source}"
      )

    [source_inventory_action | telemetry_actions]
    |> Enum.reject(&is_nil/1)
  end

  defp sample_unit(samples) when is_list(samples) do
    Enum.find_value(samples, fn sample ->
      sample
      |> Map.get(:provenance, %{})
      |> first_metadata_value([:unit, :engineering_unit, :value_unit])
    end)
  end

  defp bucket_unit(buckets) when is_list(buckets) do
    Enum.find_value(buckets, fn bucket ->
      first_metadata_value(bucket, [:unit, :engineering_unit, :value_unit])
    end)
  end

  defp latest_time_axis(%Sample{generation_time: %DateTime{}}), do: :generation_time
  defp latest_time_axis(_sample), do: :receipt_time

  defp sample_time(%Sample{generation_time: %DateTime{} = generation_time}), do: generation_time
  defp sample_time(%Sample{receipt_time: receipt_time}), do: receipt_time

  defp sample_time(%Sample{receipt_time: %DateTime{} = receipt_time}, :receipt_time),
    do: receipt_time

  defp sample_time(%Sample{} = sample, :generation_time), do: sample_time(sample)
  defp sample_time(%Sample{} = sample, _axis), do: sample_time(sample)

  defp bounded_history_axis(%PlannedSourceRequest{} = request, source_filter_context) do
    case context_value(source_filter_context, :time_axis) || FrameContext.time_axis(request) do
      :generation_time -> :generation_time
      "generation_time" -> :generation_time
      _axis -> :receipt_time
    end
  end

  defp sample_value(%Sample{} = sample, :raw), do: sample.raw_value
  defp sample_value(%Sample{} = sample, :engineering), do: sample.engineering_value

  defp bucket_representative_value(bucket) do
    bucket_value(bucket, :value) || bucket_value(bucket, :mean)
  end

  defp bucket_value(bucket, :bucket_start) do
    first_context_value(bucket, [:bucket_start, :start, :from])
  end

  defp bucket_value(bucket, :bucket_end) do
    first_context_value(bucket, [:bucket_end, :end, :to])
  end

  defp bucket_value(bucket, key), do: context_value(bucket, key)

  defp field_kind(values) do
    values
    |> Enum.find(&(not is_nil(&1)))
    |> value_kind()
  end

  defp value_kind(value) when is_number(value), do: :number
  defp value_kind(value) when is_boolean(value), do: :boolean
  defp value_kind(value) when is_atom(value), do: :enum
  defp value_kind(_value), do: :string

  defp first_metadata_value(metadata, keys) when is_map(metadata) and is_list(keys) do
    Enum.find_value(keys, &metadata_value(metadata, &1))
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp first_context_value(context, keys) do
    Enum.find_value(keys, &context_value(context, &1))
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp evidence_identity(%{kind: kind, id: id}), do: {kind, id}
  defp evidence_identity(ref), do: ref
end
