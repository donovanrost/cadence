defmodule Cadence.Dashboards.Sources.Limits.FrameBuilder do
  @moduledoc """
  Builds dashboard frame shapes for resolved limit products.

  The limits adapter supplies evidence and metadata. This module owns only the
  frame identity, axes, and field columns presented to dashboard consumers.
  """

  alias Cadence.Dashboards.{Field, Frame, PlannedSourceRequest}
  alias Cadence.Limits.{DefinitionInterval, Event}

  @spec latest(PlannedSourceRequest.t(), binary(), Event.t() | nil, map()) :: Frame.t()
  def latest(%PlannedSourceRequest{} = request, observable_id, event, meta) do
    events = List.wrap(event)
    times = Enum.map(events, &event_time/1)
    time_axis = latest_time_axis(event)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :limits,
      shape: :scalar,
      time_axis: time_axis,
      scope: request.scope_context,
      fields: [
        %Field{name: "time", kind: :time, values: times, metadata: %{axis: time_axis}},
        %Field{
          name: "normalized_state",
          kind: :enum,
          values: Enum.map(events, & &1.normalized_state)
        },
        %Field{name: "limit_state", kind: :enum, values: Enum.map(events, & &1.limit_state)},
        %Field{name: "violation", kind: :boolean, values: Enum.map(events, & &1.violation)}
      ],
      meta: meta
    }
  end

  @spec recomputed_latest(PlannedSourceRequest.t(), binary(), map(), map()) :: Frame.t()
  def recomputed_latest(
        %PlannedSourceRequest{} = request,
        observable_id,
        analysis,
        meta
      ) do
    event = analysis.event
    events = List.wrap(event)
    observed_events = analysis.observed_events
    semantics_mode = analysis.semantics_mode
    time_axis = latest_time_axis(event)
    times = Enum.map(events, &event_time/1)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}:latest_state:#{semantics_mode}",
      source: :limits,
      shape: :scalar,
      time_axis: time_axis,
      scope: request.scope_context,
      fields: recomputed_latest_fields(events, observed_events, semantics_mode, times, time_axis),
      meta: meta
    }
  end

  @spec event_history(PlannedSourceRequest.t(), binary(), [Event.t()], map()) :: Frame.t()
  def event_history(%PlannedSourceRequest{} = request, observable_id, events, meta) do
    times = Enum.map(events, & &1.receipt_time)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :limits,
      shape: :events,
      time_axis: :receipt_time,
      scope: request.scope_context,
      fields: [
        %Field{name: "time", kind: :time, values: times, metadata: %{axis: :receipt_time}},
        %Field{
          name: "limit_event_id",
          kind: :string,
          values: Enum.map(events, & &1.limit_event_id)
        },
        %Field{name: "sample_id", kind: :string, values: Enum.map(events, & &1.sample_id)},
        %Field{
          name: "limit_definition_id",
          kind: :string,
          values: Enum.map(events, & &1.limit_definition_id)
        },
        %Field{
          name: "limit_definition_version",
          kind: :number,
          values: Enum.map(events, & &1.limit_definition_version)
        },
        %Field{
          name: "normalized_state",
          kind: :enum,
          values: Enum.map(events, & &1.normalized_state)
        },
        %Field{name: "limit_state", kind: :enum, values: Enum.map(events, & &1.limit_state)},
        %Field{name: "violation", kind: :boolean, values: Enum.map(events, & &1.violation)}
      ],
      meta: meta
    }
  end

  @spec recomputed_event_history(PlannedSourceRequest.t(), binary(), map(), map()) :: Frame.t()
  def recomputed_event_history(
        %PlannedSourceRequest{} = request,
        observable_id,
        analysis,
        meta
      ) do
    events = analysis.events
    observed_events = analysis.observed_events
    semantics_mode = analysis.semantics_mode
    times = Enum.map(events, & &1.receipt_time)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}:#{semantics_mode}",
      source: :limits,
      shape: :events,
      time_axis: :receipt_time,
      scope: request.scope_context,
      fields: recomputed_event_fields(events, observed_events, semantics_mode, times),
      meta: meta
    }
  end

  @spec analysis_buckets(PlannedSourceRequest.t(), binary(), atom(), [map()], map()) :: Frame.t()
  def analysis_buckets(
        %PlannedSourceRequest{} = request,
        observable_id,
        semantics_mode,
        buckets,
        meta
      ) do
    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}:analysis_buckets:#{semantics_mode}",
      source: :limits,
      shape: :events,
      time_axis: :receipt_time,
      scope: request.scope_context,
      fields: limit_analysis_bucket_fields(buckets),
      meta: meta
    }
  end

  @spec definition_intervals(
          PlannedSourceRequest.t(),
          binary(),
          [DefinitionInterval.t()],
          map()
        ) :: Frame.t()
  def definition_intervals(
        %PlannedSourceRequest{} = request,
        observable_id,
        intervals,
        meta
      ) do
    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :limits,
      shape: :intervals,
      time_axis: :receipt_time,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "active_from",
          kind: :time,
          values: Enum.map(intervals, & &1.active_from),
          metadata: %{axis: :receipt_time}
        },
        %Field{
          name: "active_to",
          kind: :time,
          values: Enum.map(intervals, & &1.active_to),
          metadata: %{axis: :receipt_time, open_ended?: true}
        },
        %Field{
          name: "limit_definition_id",
          kind: :string,
          values: Enum.map(intervals, & &1.limit_definition_id)
        },
        %Field{
          name: "limit_definition_version",
          kind: :number,
          values: Enum.map(intervals, & &1.limit_definition_version)
        },
        %Field{
          name: "limit_set_name",
          kind: :string,
          values: Enum.map(intervals, & &1.limit_set_name)
        },
        %Field{name: "red_low", kind: :number, values: threshold_values(intervals, "red_low")},
        %Field{
          name: "yellow_low",
          kind: :number,
          values: threshold_values(intervals, "yellow_low")
        },
        %Field{
          name: "yellow_high",
          kind: :number,
          values: threshold_values(intervals, "yellow_high")
        },
        %Field{name: "red_high", kind: :number, values: threshold_values(intervals, "red_high")}
      ],
      meta: meta
    }
  end

  defp recomputed_latest_fields(events, observed_events, semantics_mode, times, time_axis) do
    base_fields = [
      %Field{name: "time", kind: :time, values: times, metadata: %{axis: time_axis}},
      %Field{name: "sample_id", kind: :string, values: Enum.map(events, & &1.sample_id)},
      %Field{
        name: "limit_definition_id",
        kind: :string,
        values: Enum.map(events, & &1.limit_definition_id)
      },
      %Field{
        name: "limit_definition_version",
        kind: :number,
        values: Enum.map(events, & &1.limit_definition_version)
      },
      %Field{
        name: "normalized_state",
        kind: :enum,
        values: Enum.map(events, & &1.normalized_state)
      },
      %Field{name: "limit_state", kind: :enum, values: Enum.map(events, & &1.limit_state)},
      %Field{name: "violation", kind: :boolean, values: Enum.map(events, & &1.violation)}
    ]

    maybe_put_observed_comparison_fields(base_fields, events, observed_events, semantics_mode)
  end

  defp recomputed_event_fields(events, observed_events, semantics_mode, times) do
    base_fields = [
      %Field{name: "time", kind: :time, values: times, metadata: %{axis: :receipt_time}},
      %Field{name: "sample_id", kind: :string, values: Enum.map(events, & &1.sample_id)},
      %Field{
        name: "limit_definition_id",
        kind: :string,
        values: Enum.map(events, & &1.limit_definition_id)
      },
      %Field{
        name: "limit_definition_version",
        kind: :number,
        values: Enum.map(events, & &1.limit_definition_version)
      },
      %Field{
        name: "normalized_state",
        kind: :enum,
        values: Enum.map(events, & &1.normalized_state)
      },
      %Field{name: "limit_state", kind: :enum, values: Enum.map(events, & &1.limit_state)},
      %Field{name: "violation", kind: :boolean, values: Enum.map(events, & &1.violation)}
    ]

    maybe_put_observed_comparison_fields(base_fields, events, observed_events, semantics_mode)
  end

  defp maybe_put_observed_comparison_fields(base_fields, events, observed_events, :compare) do
    observed_by_sample_id = Map.new(observed_events, &{&1.sample_id, &1})

    base_fields ++
      [
        %Field{
          name: "observed_limit_event_id",
          kind: :string,
          values:
            Enum.map(
              events,
              &(observed_by_sample_id[&1.sample_id] &&
                  observed_by_sample_id[&1.sample_id].limit_event_id)
            )
        },
        %Field{
          name: "observed_normalized_state",
          kind: :enum,
          values: Enum.map(events, &Map.get(&1.provenance, "observed_normalized_state"))
        },
        %Field{
          name: "limit_state_diverged",
          kind: :boolean,
          values: Enum.map(events, &Map.get(&1.provenance, "limit_state_diverged?"))
        }
      ]
  end

  defp maybe_put_observed_comparison_fields(base_fields, _events, _observed_events, _mode),
    do: base_fields

  defp limit_analysis_bucket_fields(buckets) do
    [
      %Field{
        name: "time",
        kind: :time,
        values: Enum.map(buckets, & &1.bucket_start),
        metadata: %{axis: :receipt_time}
      },
      %Field{
        name: "bucket_start",
        kind: :time,
        values: Enum.map(buckets, & &1.bucket_start),
        metadata: %{axis: :receipt_time}
      },
      %Field{
        name: "bucket_end",
        kind: :time,
        values: Enum.map(buckets, & &1.bucket_end),
        metadata: %{axis: :receipt_time}
      },
      %Field{name: "event_count", kind: :number, values: Enum.map(buckets, & &1.event_count)},
      %Field{
        name: "limit_event_id",
        kind: :string,
        values: Enum.map(buckets, & &1.limit_event_id)
      },
      %Field{name: "sample_id", kind: :string, values: Enum.map(buckets, & &1.sample_id)},
      %Field{
        name: "limit_event_ids",
        kind: :string,
        values: Enum.map(buckets, & &1.limit_event_ids)
      },
      %Field{name: "sample_ids", kind: :string, values: Enum.map(buckets, & &1.sample_ids)},
      %Field{
        name: "limit_definition_id",
        kind: :string,
        values: Enum.map(buckets, & &1.limit_definition_id)
      },
      %Field{
        name: "limit_definition_version",
        kind: :number,
        values: Enum.map(buckets, & &1.limit_definition_version)
      },
      %Field{
        name: "limit_set_name",
        kind: :string,
        values: Enum.map(buckets, & &1.limit_set_name)
      },
      %Field{
        name: "normalized_state",
        kind: :enum,
        values: Enum.map(buckets, & &1.normalized_state)
      },
      %Field{name: "limit_state", kind: :enum, values: Enum.map(buckets, & &1.limit_state)},
      %Field{name: "violation", kind: :boolean, values: Enum.map(buckets, & &1.violation)},
      %Field{
        name: "observed_normalized_state",
        kind: :enum,
        values: Enum.map(buckets, & &1.observed_normalized_state)
      },
      %Field{
        name: "limit_state_diverged",
        kind: :boolean,
        values: Enum.map(buckets, & &1.limit_state_diverged)
      },
      %Field{
        name: "limit_divergence_count",
        kind: :number,
        values: Enum.map(buckets, & &1.limit_divergence_count)
      }
    ]
  end

  defp threshold_values(intervals, threshold_name) do
    Enum.map(intervals, fn %DefinitionInterval{} = interval ->
      Map.get(interval.thresholds || %{}, threshold_name)
    end)
  end

  defp latest_time_axis(%Event{generation_time: %DateTime{}}), do: :generation_time
  defp latest_time_axis(_event), do: :receipt_time

  defp event_time(%Event{generation_time: %DateTime{} = generation_time}), do: generation_time
  defp event_time(%Event{receipt_time: receipt_time}), do: receipt_time
end
