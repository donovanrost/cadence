defmodule Cadence.Reads.LimitStateEvidence do
  @moduledoc "Canonical evaluated-state evidence shared by Limits posture and Ops alarm conditions."
  alias Cadence.Reads.ApplicationSurfaces.Limits.Pages
  alias Cadence.Reads.ConsoleSampleLinks

  @doc """
  One evaluated state's row. `links` is `ConsoleSampleLinks.context/2` for the mission (read once
  per page): `evidence_href` opens the sample in the console's Investigate (§11c(D) D2).
  """
  def row(e, links, definition_href) do
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
      "evidence_href" =>
        ConsoleSampleLinks.href(
          links,
          e.spacecraft_id,
          e.point_id,
          Pages.stamp(e.generation_time),
          Pages.stamp(e.receipt_time)
        )
    }
  end
end
