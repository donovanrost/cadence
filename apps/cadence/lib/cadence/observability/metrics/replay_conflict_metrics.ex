defmodule Cadence.Observability.Metrics.ReplayConflictMetrics do
  @moduledoc """
  The stuck-processing metrics (#99 follow-up; devops' rules in
  dev/grafana/provisioning/alerting/cadence.yaml), joined to `Observability.Metrics.Catalog`:

  - `cadence.runtime.replay_id.conflict`: every retry that hits `MM_REPLAY_ID_CONFLICT` (kind, path,
    mission); any increase is a bug;
  - `cadence.runtime.replay_id.tripped.units` / `.oldest_age_seconds` (per path), and
    `.streams` / `.stream_headroom_bytes` (each tripped stream once): from the sampler;
  - `cadence.ingress.journal.disk.free_bytes`, so headroom can be compared with the disk.

  Never a stream key or record id as a label (devops).
  """

  alias Cadence.Observability.Metrics.Definition

  @conflict "cadence.runtime.replay_id.conflict"

  @spec definitions() :: [Definition.t()]
  def definitions do
    [
      %Definition{
        name: @conflict,
        type: :counter,
        event_name: [:cadence, :replay_id, :conflict],
        measurement: :count,
        unit: "{conflict}",
        description: "Retries that hit a replay-id conflict (MM_REPLAY_ID_CONFLICT): a bug.",
        attributes: ["kind", "path", "cadence.mission.id"],
        tag_values: &conflict_tags/1
      },
      tripped_gauge("units", :units, "{unit}", "Open stuck-processing units."),
      tripped_gauge(
        "oldest_age_seconds",
        :oldest_age_seconds,
        "s",
        "Age of the oldest open stuck-processing unit."
      ),
      stream_gauge("streams", :streams, "{stream}", "Journal streams with stuck processing."),
      stream_gauge(
        "stream_headroom_bytes",
        :stream_headroom_bytes,
        "By",
        "Room the stuck streams can still take before each reaches its own cap."
      ),
      %Definition{
        name: "cadence.ingress.journal.disk.free_bytes",
        type: :gauge,
        event_name: [:cadence, :ingress_journal, :disk],
        measurement: :free_bytes,
        unit: "By",
        description: "Free bytes on the ingress journal's disk.",
        attributes: []
      }
    ]
  end

  defp tripped_gauge(suffix, measurement, unit, description) do
    %Definition{
      name: "cadence.runtime.replay_id.tripped." <> suffix,
      type: :gauge,
      event_name: [:cadence, :replay_id, :tripped],
      measurement: measurement,
      unit: unit,
      description: description,
      attributes: ["path"],
      tag_values: &%{"path" => to_string(&1[:path])}
    }
  end

  defp stream_gauge(suffix, measurement, unit, description) do
    %Definition{
      name: "cadence.runtime.replay_id.tripped." <> suffix,
      type: :gauge,
      event_name: [:cadence, :replay_id, :tripped_streams],
      measurement: measurement,
      unit: unit,
      description: description,
      attributes: []
    }
  end

  defp conflict_tags(metadata) do
    %{
      "kind" => to_string(metadata[:kind]),
      "path" => to_string(metadata[:path]),
      "cadence.mission.id" => metadata[:mission_id]
    }
  end
end
