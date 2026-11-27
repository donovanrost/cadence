defmodule CadenceWeb.Console.LegacyConversionAPITest do
  @moduledoc """
  ux U79 over HTTP. TEMPORARY with the conversion (removed with 9ac6dc8ee), except the older
  route removal label, which stays with the legacy_routing_rule kind.
  - The conversion read and stage, the change set's legacy_conversion marker and viewer, and the
    refusals while a batch is staged.
  - An older route's removal is named '“name” · spacecraft' in the change set's preview.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.{GroundStation, GroundStationStore, RoutingRule, RoutingRuleStore}
  alias Cadence.Comms.{Transport, TransportStore}
  alias Cadence.Configuration.Submission
  alias Cadence.Governance.ActivationPolicy
  alias CadenceWeb.TestFixtures

  setup do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: false)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)

    org = TestFixtures.persist_org!()
    stager = TestFixtures.persist_user!(display_name: "Mira K.")
    reviewer = TestFixtures.persist_user!(display_name: "Ana R.")
    TestFixtures.grant_membership!(stager, org, role: :organization_admin)
    TestFixtures.grant_membership!(reviewer, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-389", scid: 389)

    {:ok, station} =
      GroundStationStore.persist_ground_station(
        org.organization_id,
        GroundStation.new(%{mission_id: mission.mission_id, display_name: "Inuvik", code: "INU"})
      )

    {:ok, transport} =
      TransportStore.persist_transport(
        org.organization_id,
        Transport.new(%{
          mission_id: mission.mission_id,
          display_name: "INU S-band",
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          ground_station_id: station.ground_station_id,
          configuration: %{
            "mode" => "listen",
            "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
            "direction_capability" => "inbound",
            "host" => "127.0.0.1",
            "port" => Integer.to_string(40_000 + rem(System.unique_integer([:positive]), 20_000)),
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          }
        })
      )

    {:ok, rule} =
      RoutingRuleStore.create_routing_rule(
        org.organization_id,
        RoutingRule.new(%{
          mission_id: mission.mission_id,
          spacecraft_id: craft.spacecraft_id,
          display_name: "Old INU downlink",
          purpose_label: "TT&C downlink",
          direction: :inbound,
          transport_id: transport.transport_id,
          transport_version: transport.version,
          ground_station_id: station.ground_station_id,
          role: :primary
        })
      )

    %{
      stager: TestFixtures.member_conn(stager),
      reviewer: TestFixtures.member_conn(reviewer),
      base: "/api/v1/missions/#{mission.mission_id}",
      org_id: org.organization_id,
      mission_id: mission.mission_id,
      rule: rule
    }
  end

  defp read(conn, c, path),
    do: conn |> get(c.base <> path) |> json_response(200) |> Map.fetch!("data")

  test "progress, a staged batch, its change set's marker and who may review it", c do
    assert %{
             "routes_converted" => 0,
             "routes_total" => 1,
             "batches_total" => 1,
             "next_batch" => 1,
             "staged_batch" => nil,
             "can_stage" => true,
             "unmappable" => %{"count" => 0, "routes" => []}
           } = read(c.stager, c, "/routes/legacy-conversion")

    assert %{"change_set_id" => set_id, "batch" => 1, "batches_total" => 1, "unmappable" => []} =
             c.stager
             |> post(c.base <> "/routes/legacy-conversion", %{})
             |> json_response(201)
             |> Map.fetch!("data")

    assert %{"staged_batch" => %{"change_set_id" => ^set_id, "batch" => 1, "author" => author}} =
             read(c.stager, c, "/routes/legacy-conversion")

    assert author["name"] == "Mira K."

    # The stager can't review their own batch; another admin can.
    assert %{
             "legacy_conversion" => %{"batch" => 1, "batches_total" => 1},
             "viewer" => %{"can_review" => false, "review_blocked_reason" => "reviewer_is_author"}
           } = read(c.stager, c, "/config/change-sets/#{set_id}")

    assert %{
             "change_set" => %{
               "viewer" => %{"can_review" => true, "review_blocked_reason" => nil}
             }
           } =
             read(c.reviewer, c, "/config")
  end

  # fe-setup on #555: the mission is 'direct', but a conversion batch is forced to need a second
  # person, so its submit is a Request review and a refusal there opens "Not sent for review:".
  test "a conversion set's submit is a Request review even under 'direct'", c do
    assert %{"data" => %{"change_set_id" => set_id}} =
             c.stager |> post(c.base <> "/routes/legacy-conversion", %{}) |> json_response(201)

    refute ActivationPolicy.evidence(c.org_id, c.mission_id)[
             "approval_required"
           ]

    assert Submission.needs_approval?(c.org_id, c.mission_id, set_id)

    refute Submission.needs_approval?(
             c.org_id,
             c.mission_id,
             "change_set_missing"
           )
  end

  test "while a batch is staged: no second batch, and no other staging", c do
    assert %{"data" => %{"change_set_id" => set_id}} =
             c.stager |> post(c.base <> "/routes/legacy-conversion", %{}) |> json_response(201)

    assert %{"error" => %{"code" => "conversion_already_staged", "details" => details}} =
             c.reviewer |> post(c.base <> "/routes/legacy-conversion", %{}) |> json_response(409)

    assert %{"change_set_id" => ^set_id, "batch" => 1} = details

    op = %{"kind" => "spacecraft", "action" => "create", "document" => %{"display_name" => "X"}}

    assert %{"error" => %{"code" => "conversion_in_progress", "details" => in_progress}} =
             c.reviewer
             |> post(c.base <> "/config/stage", %{"summary" => "Add", "ops" => [op]})
             |> json_response(409)

    assert %{"change_set_id" => ^set_id, "batch" => 1} = in_progress
  end

  test "a batch size that isn't a whole number is a field error", c do
    assert %{"error" => %{"code" => "invalid_params", "details" => %{"spacecraft" => _}}} =
             c.stager
             |> post(c.base <> "/routes/legacy-conversion", %{"spacecraft" => "lots"})
             |> json_response(422)
  end

  test "an older route's removal is named '“name” · spacecraft' in the preview, never an id", c do
    op = %{
      "kind" => "legacy_routing_rule",
      "action" => "delete",
      "entity_id" => c.rule.routing_rule_id
    }

    assert %{"data" => %{"change_set_id" => set_id}} =
             c.stager
             |> post(c.base <> "/config/stage", %{"summary" => "Remove", "ops" => [op]})
             |> json_response(201)

    preview =
      c.stager
      |> post(c.base <> "/config/change-sets/#{set_id}/preview", %{})
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"entity_name" => "“Old INU downlink” · EARENDIL-389"} | _] =
             Enum.filter(preview["diffs"], &(&1["kind"] == "legacy_routing_rule"))
  end

  test "once applied (the rule archived), the history still names it from the revision", c do
    rule_id = c.rule.routing_rule_id
    op = %{"kind" => "legacy_routing_rule", "action" => "delete", "entity_id" => rule_id}

    %{"change_set_id" => set_id, "version" => version} =
      c.stager
      |> post(c.base <> "/config/stage", %{"summary" => "Remove", "ops" => [op]})
      |> json_response(201)
      |> Map.fetch!("data")

    c.stager
    |> post("#{c.base}/config/change-sets/#{set_id}/submit", %{
      "reason" => "Its transport has no use any more",
      "expected_version" => version
    })
    |> json_response(200)

    %{"revisions" => [%{"entries" => entries}]} =
      read(
        c.stager,
        c,
        "/config/revisions?entity_kind=legacy_routing_rule&entity_id=#{rule_id}&limit=1"
      )

    assert [%{"entity_name" => "“Old INU downlink” · EARENDIL-389"}] = entries
  end
end
