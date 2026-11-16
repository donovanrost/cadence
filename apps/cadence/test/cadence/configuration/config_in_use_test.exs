defmodule Cadence.Configuration.ConfigInUseTest do
  @moduledoc """
  Archiving a transport or ground station is refused while anything still uses it (director
  11-16, ux U82): at stage (nothing staged) and again at apply, with the same {:in_use, %{entity, uses}}.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, TransportStore}
  alias Cadence.Contacts.{ContactStore, RealizedContact}
  alias Cadence.Control.{Configuration, ConfigUsers}
  alias Cadence.ProviderChangeFixtures

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("in-use")
    alice = member_scope(org, :member, "Alice")
    ids = %{fbk: unique("fbk"), down: unique("fbk-down"), spare: unique("spare")}

    apply_ops(%{alice: alice, mission: mission}, "Fairbanks", [
      create("ground_station", %{"display_name" => "Fairbanks", "code" => "FBK"}, ids.fbk),
      create("transport", station_transport("FBK down", ids.fbk, "inbound"), ids.down),
      create("transport", Map.delete(transport_doc("Spare"), "ground_station_id"), ids.spare)
    ])

    [sc] =
      apply_ops(%{alice: alice, mission: mission}, "Craft", [
        create("spacecraft", spacecraft_doc("EARENDIL-312", 1))
      ])

    %{org: org, mission: mission, alice: alice, ids: ids, sc: sc}
  end

  test "a transport nothing uses archives", ctx do
    apply_ops(ctx, "Archive spare", [archive("transport", ctx.ids.spare)])

    assert {:error, :transport_not_found} =
             TransportStore.fetch_transport(ctx.org, ctx.mission, ctx.ids.spare)
  end

  test "a transport a route uses is refused at stage, naming the route", ctx do
    legacy!(ctx, ctx.ids.down, "Fairbanks (Demo) — primary")

    assert {:error,
            {:in_use, %{entity: %{kind: "transport", id: id, name: "FBK down"}, uses: uses}}} =
             stage(ctx, archive("transport", ctx.ids.down))

    assert id == ctx.ids.down

    assert %{
             routes: %{count: 1, items: [route]},
             profile_routes: %{count: 0, items: []},
             booked_passes: %{count: 0, next_at: nil},
             listening_now: %{count: 0, items: []},
             transports: %{count: 0, items: []}
           } = uses

    assert %{
             name: "Fairbanks (Demo) — primary",
             spacecraft: %{name: "EARENDIL-312"},
             station: %{code: "FBK", name: "Fairbanks"},
             direction: "downlink"
           } = route
  end

  test "a transport a profile rule reaches through its station is refused", ctx do
    profile_id = "profile-" <> unique("p")

    apply_ops(ctx, "Profile", [
      create("spacecraft_profile", profile_with_rule(ctx.ids.fbk), profile_id)
    ])

    assert {:error, {:in_use, %{uses: %{profile_routes: %{count: 1, items: [rule]}}}}} =
             stage(ctx, archive("transport", ctx.ids.down))

    assert %{profile: %{name: "Block 1"}, label: "TT&C"} = rule
  end

  test "a transport an open contact listens on is refused", ctx do
    open_contact!(ctx, ctx.ids.down)

    assert {:error, {:in_use, %{uses: %{listening_now: listening}}}} =
             stage(ctx, archive("transport", ctx.ids.down))

    assert %{count: 1, items: [%{spacecraft: %{name: "EARENDIL-312"}, station_code: "FBK"}]} =
             listening
  end

  test "a booked pass counts, with when the next one is" do
    booked = ProviderChangeFixtures.setup_contact()
    transport_id = booked.reservation.transport_id

    assert %{booked_passes: %{count: 1, next_at: next_at}} =
             ConfigUsers.transport_uses(booked.organization_id, booked.mission_id, transport_id)

    assert DateTime.compare(next_at, booked.reservation.starts_at) == :eq
  end

  test "a station its transport still sits at is refused, naming the transport", ctx do
    assert {:error,
            {:in_use,
             %{
               entity: %{kind: "ground_station"},
               uses: %{transports: %{count: 1, items: [%{name: "FBK down"}]}}
             }}} =
             stage(ctx, archive("ground_station", ctx.ids.fbk))
  end

  # A station goes with its transports: the transport's archive beside it, in this stage or
  # already staged in the open set, frees the station at stage; apply checks op by op.
  test "a station archived with its transport stages, in one call or two, and applies", ctx do
    assert {:ok, _} =
             Configuration.stage(ctx.alice, ctx.mission, %{summary: "Both"}, [
               archive("transport", ctx.ids.down),
               archive("ground_station", ctx.ids.fbk)
             ])

    {:ok, %{change_set: set}} = Configuration.current(ctx.alice, ctx.mission)
    {:ok, _} = Configuration.discard(ctx.alice, ctx.mission, set.id, set.version)

    assert {:ok, _} = stage(ctx, archive("transport", ctx.ids.down))
    assert {:ok, staged} = stage(ctx, archive("ground_station", ctx.ids.fbk))

    assert {:ok, %{state: :applied}} =
             Configuration.submit(ctx.alice, ctx.mission, staged.change_set_id, %{
               reason: "Retire Fairbanks and its transport",
               expected_version: staged.version
             })
  end

  # lead: the check holds at apply too, not only at stage.
  test "staged while free, used before apply: the apply is refused with the same uses", ctx do
    {:ok, staged} =
      Configuration.stage(ctx.alice, ctx.mission, %{summary: "Archive"}, [
        archive("transport", ctx.ids.down)
      ])

    legacy!(ctx, ctx.ids.down, "Fairbanks (Demo) — primary")

    assert {:error,
            {:in_use,
             %{entity: %{kind: "transport", name: "FBK down"}, uses: %{routes: %{count: 1}}}}} =
             Configuration.submit(ctx.alice, ctx.mission, staged.change_set_id, %{
               reason: "Archive the downlink transport",
               expected_version: staged.version
             })

    assert {:ok, _still} = TransportStore.fetch_transport(ctx.org, ctx.mission, ctx.ids.down)
  end

  defp stage(ctx, op),
    do: Configuration.stage(ctx.alice, ctx.mission, %{summary: "Archive"}, [op])

  defp archive(kind, id), do: %{kind: kind, action: :delete, entity_id: id}

  defp legacy!(ctx, transport_id, name) do
    {:ok, transport} = TransportStore.fetch_transport(ctx.org, ctx.mission, transport_id)

    {:ok, _rule} =
      RoutingRuleStore.create_routing_rule(
        ctx.org,
        RoutingRule.new(%{
          mission_id: ctx.mission,
          spacecraft_id: ctx.sc,
          display_name: name,
          purpose_label: "TT&C downlink",
          direction: :inbound,
          transport_id: transport_id,
          transport_version: transport.version,
          role: :primary
        })
      )
  end

  defp open_contact!(ctx, transport_id) do
    now = DateTime.utc_now()

    {:ok, _contact} =
      ContactStore.persist_realized(
        RealizedContact.new(%{
          realized_contact_id: unique("realized"),
          organization_id: ctx.org,
          mission_id: ctx.mission,
          source_endpoint_refs: ["spacecraft_runtime:" <> ctx.sc],
          clock_mode: :live,
          initial_time: now,
          realized_at: now,
          lifecycle_state: :active,
          metadata: %{"transport_id" => transport_id}
        })
      )
  end

  defp profile_with_rule(station),
    do:
      Map.put(profile_doc("Block 1"), "routing_rules", [
        %{
          "id" => "ttc",
          "label" => "TT&C",
          "stations" => [%{"ground_station_id" => station}],
          "legs" => [%{"direction" => "downlink", "role" => "primary"}]
        }
      ])

  defp station_transport(name, station, direction) do
    name
    |> transport_doc()
    |> put_in(["configuration", "direction_capability"], direction)
    |> Map.put("ground_station_id", station)
  end

  defp apply_ops(%{alice: alice, mission: mission}, summary, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: summary}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: " <> summary,
        expected_version: staged.version
      })

    staged.entity_ids
  end

  defp create(kind, document, id \\ nil) do
    op = %{kind: kind, action: :create, document: document}
    if id, do: Map.put(op, :entity_id, id), else: op
  end
end
