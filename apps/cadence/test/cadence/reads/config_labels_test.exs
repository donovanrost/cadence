defmodule Cadence.Reads.ConfigLabelsTest do
  @moduledoc "Display labels for spacecraft kinds without an edit schema (fe-setup / ux)."
  use Cadence.DataCase, async: true

  import Cadence.ConfigurationFixtures

  alias Cadence.Reads.ConfigLabels

  defp entry(kind, doc, paths),
    do: %{
      kind: kind,
      entity_id: Ecto.UUID.generate(),
      before: doc,
      after: doc,
      fields: Enum.map(paths, &%{path: &1})
    }

  test "profile, spacecraft and override paths reuse the editors' labels" do
    %{organization_id: org, mission_id: mission} = configuration_mission()
    named = %{"display_name" => "Earendil"}

    %{entries: [profile, craft, override]} =
      ConfigLabels.revision(org, mission, %{
        entries: [
          entry("spacecraft_profile", named, ["frame_parameters.frame_size"]),
          entry("spacecraft", named, ["spacecraft_type_version", "scid", "metadata.norad_id"]),
          entry("spacecraft_override", nil, [
            "frame_parameters/frame_size.value",
            "frame_parameters/frame_size.reason"
          ])
        ]
      })

    assert [%{label: "TM frame length", unit: "bytes"}] = profile.fields
    assert profile.entity_name == "Earendil"

    assert [
             %{label: "Profile version", format: "version"},
             %{label: "SCID"},
             %{label: "NORAD ID"}
           ] = craft.fields

    assert [
             %{label: "TM frame length", unit: "bytes"},
             %{label: "TM frame length override reason", unit: nil}
           ] = override.fields
  end
end
