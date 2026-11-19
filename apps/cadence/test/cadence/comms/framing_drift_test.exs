defmodule Cadence.Comms.FramingDriftTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.FramingDrift
  alias Cadence.Control.Configuration
  alias Cadence.Reads.Readiness

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("drift")
    %{org: org, mission: mission, alice: member_scope(org, :member, "Alice")}
  end

  test "reports profile framing that differs from the feeding transport", ctx do
    profile = setup_fleet(ctx, 1279)

    assert [%{profile: %{id: ^profile}, spacecraft_count: 1, differences: differences}] =
             FramingDrift.audit(ctx.org, ctx.mission)

    assert %{path: "frame_parameters.frame_size", profile_value: 1279, transport_value: 1115} in differences

    %{findings: findings} = Readiness.evaluate(ctx.org, ctx.mission)

    assert %{severity: :caution, cause: :framing_drift, fix: %{kind: :profile, id: ^profile}} =
             Enum.find(findings, &(&1.cause == :framing_drift))
  end

  test "matching framing is not drift", ctx do
    setup_fleet(ctx, 1115)
    assert [] = FramingDrift.audit(ctx.org, ctx.mission)
  end

  defp setup_fleet(ctx, frame_size) do
    [station, transport, profile] = Enum.map(~w(st tr pr), &unique/1)

    transport_document =
      transport_doc("Svalbard TCP")
      |> Map.put("ground_station_id", station)
      |> put_in(["configuration", "ingress_metadata"], %{"frame_size" => 1115, "ocf_length" => 4})

    rule = %{
      "id" => "ttc",
      "stations" => [%{"ground_station_id" => station}],
      "legs" => [%{"direction" => "downlink", "role" => "primary"}]
    }

    profile_document =
      "Block"
      |> profile_doc(%{"frame_size" => frame_size})
      |> Map.put("routing_rules", [rule])

    apply_ops(ctx, [
      %{
        kind: "ground_station",
        action: :create,
        entity_id: station,
        document: %{"display_name" => "Svalbard", "code" => "SVB"}
      },
      %{kind: "transport", action: :create, entity_id: transport, document: transport_document},
      %{
        kind: "spacecraft_profile",
        action: :create,
        entity_id: profile,
        document: profile_document
      }
    ])

    apply_ops(ctx, [
      %{kind: "spacecraft", action: :create, document: spacecraft_doc("SC-1", 1, {profile, 1})}
    ])

    profile
  end

  defp apply_ops(%{alice: alice, mission: mission}, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: "Setup"}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test fleet setup",
        expected_version: staged.version
      })
  end
end
