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

  describe "a fleet item names a count and a few craft (#796)" do
    defp insert_craft(org, mission, count) do
      now = DateTime.utc_now()

      rows =
        for n <- 1..count do
          pad = String.pad_leading(Integer.to_string(n), 4, "0")

          %{
            spacecraft_id: "#{mission}-#{pad}",
            organization_id: org,
            mission_id: mission,
            display_name: "Craft #{pad}",
            metadata: %{},
            lifecycle_state: "active",
            inserted_at: now
          }
        end

      Cadence.Repo.insert_all("mission_spacecraft", rows)
      Enum.map(rows, & &1.spacecraft_id)
    end

    defp preview(items),
      do: %{
        verdict: :hold,
        checks: [%{key: "compatibility", verdict: :hold, blocking: false, items: items}],
        diffs: []
      }

    test "replaces spacecraft_ids with the count and the first five by name" do
      %{organization_id: org, mission_id: mission} = configuration_mission()
      ids = insert_craft(org, mission, 1_500)

      item = %{reason: :catalog_change, spacecraft_ids: Enum.reverse(ids), from: "a", to: "b"}
      %{checks: [%{items: [shown]}]} = ConfigLabels.preview(org, mission, preview([item]))

      refute Map.has_key?(shown, :spacecraft_ids)
      assert shown.spacecraft_count == 1_500

      assert shown.spacecraft_sample ==
               for(n <- 1..5, do: %{id: "#{mission}-000#{n}", name: "Craft 000#{n}"})

      assert %{reason: :catalog_change, from: "a", to: "b"} = shown
    end

    test "a craft that isn't the mission's is counted by the check but never named" do
      %{organization_id: org, mission_id: mission} = configuration_mission()
      other = configuration_mission()
      [mine] = insert_craft(org, mission, 1)
      [theirs] = insert_craft(other.organization_id, other.mission_id, 1)

      item = %{reason: :catalog_configuration_pending, spacecraft_ids: [theirs, mine]}
      %{checks: [%{items: [shown]}]} = ConfigLabels.preview(org, mission, preview([item]))

      assert shown.spacecraft_count == 2
      assert shown.spacecraft_sample == [%{id: mine, name: "Craft 0001"}]
    end

    test "items without a fleet are untouched" do
      %{organization_id: org, mission_id: mission} = configuration_mission()
      item = %{reason: :other, message: "x"}
      assert %{checks: [%{items: [^item]}]} = ConfigLabels.preview(org, mission, preview([item]))
    end
  end
end
