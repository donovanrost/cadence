defmodule Cadence.Reads.LimitStateEvidence do
  @moduledoc "Canonical evaluated-state evidence shared by Limits posture and Ops alarm conditions."
  alias Cadence.Reads.ApplicationSurfaces.Limits.Pages

  def row(e, mission, definition_href) do
    evidence =
      %{
        "point_id" => e.point_id,
        "spacecraft_id" => e.spacecraft_id,
        "sample_id" => e.sample_id,
        "selected_time" => Pages.stamp(e.receipt_time)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    %{
      "id" => e.limit_event_id,
      "point_id" => e.point_id,
      "point_name" => e.point_name,
      "spacecraft_id" => e.spacecraft_id,
      "limit_set_name" => e.limit_set_name,
      "definition_id" => e.limit_definition_id,
      "definition_version" => e.limit_definition_version,
      "sample_id" => e.sample_id,
      "source_sample_type" => to_string(e.source_sample_type),
      "value" => inspect(e.evaluated_value, limit: 10, printable_limit: 256),
      "state" => to_string(e.limit_state),
      "severity" => to_string(e.normalized_state),
      "violation" => e.violation,
      "generation_time" => Pages.stamp(e.generation_time),
      "receipt_time" => Pages.stamp(e.receipt_time),
      "definition_href" => definition_href,
      "evidence_href" => "/missions/#{mission}/ops/explore?" <> URI.encode_query(evidence)
    }
  end
end
