defmodule Cadence.Reads.SpacecraftDirectoryPageTest do
  @moduledoc """
  The Setup directory a page at a time (#796): keyset paging by name then id, the server-side
  filter, the whole-mission summary and its one-query shape at 1,000 spacecraft.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport, TransportStore}
  alias Cadence.Reads.SpacecraftDirectory
  alias Cadence.{Repo, Spacecraft, SpacecraftStore, SpacecraftType, SpacecraftTypeStore}

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("dirpage")
    %{org: org, mission: mission}
  end

  defp craft!(c, name, opts \\ []) do
    {:ok, craft} =
      SpacecraftStore.persist_spacecraft(
        c.org,
        Spacecraft.new(%{
          spacecraft_id: Keyword.get(opts, :id, unique("sc")),
          organization_id: c.org,
          mission_id: c.mission,
          display_name: name,
          scid: opts[:scid],
          spacecraft_type_id: opts[:profile_id],
          spacecraft_type_version: if(opts[:profile_id], do: 1)
        })
      )

    craft
  end

  defp profile!(c, name) do
    {:ok, type} =
      SpacecraftTypeStore.persist_spacecraft_type(
        c.org,
        SpacecraftType.new(%{
          mission_id: c.mission,
          display_name: name,
          downlink_protocol: :aos,
          uplink_protocol: :tc,
          packet_protocol: :space_packet,
          frame_parameters: %{"frame_size" => 1024, "insert_zone_length" => 0, "ocf_length" => 0},
          applications: %{"telemetry_decom" => %{}}
        })
      )

    type
  end

  defp route!(c, craft, enabled? \\ true) do
    {:ok, transport} =
      TransportStore.persist_transport(
        c.org,
        Transport.new(%{
          mission_id: c.mission,
          display_name: "T-" <> craft.spacecraft_id,
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "listen",
            "direction_capability" => "inbound",
            "host" => "0.0.0.0",
            "port" => "5000",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          }
        })
      )

    {:ok, rule} =
      RoutingRuleStore.create_routing_rule(
        c.org,
        RoutingRule.new(%{
          mission_id: c.mission,
          spacecraft_id: craft.spacecraft_id,
          display_name: "Live",
          purpose_label: "Live telemetry",
          direction: :inbound,
          transport_id: transport.transport_id,
          transport_version: transport.version,
          role: :primary
        })
      )

    unless enabled?,
      do: RoutingRuleStore.set_routing_rule_enabled(c.org, c.mission, rule.routing_rule_id, false)

    rule
  end

  defp walk(c, opts, acc \\ []) do
    {:ok, page} = SpacecraftDirectory.page(c.org, c.mission, opts)
    acc = acc ++ Enum.map(page.spacecraft, & &1.name)

    if page.next_cursor,
      do: walk(c, Keyword.put(opts, :cursor, page.next_cursor), acc),
      else: acc
  end

  test "pages by name then id; a craft added or renamed between pages neither repeats nor skips",
       c do
    for name <- ~w(delta alpha echo bravo charlie), do: craft!(c, name)
    craft!(c, "alpha", id: "sc-alpha-2")

    {:ok, first} = SpacecraftDirectory.page(c.org, c.mission, limit: 2)
    assert Enum.map(first.spacecraft, & &1.name) == ["alpha", "alpha"]
    assert first.next_cursor

    # A new craft sorting before the cursor, and one renamed to sort after it.
    craft!(c, "aaa")

    {:ok, second} =
      SpacecraftDirectory.page(c.org, c.mission, limit: 2, cursor: first.next_cursor)

    assert Enum.map(second.spacecraft, & &1.name) == ["bravo", "charlie"]

    assert walk(c, limit: 2, cursor: second.next_cursor) == ["delta", "echo"]
    assert {:error, :invalid_cursor} = SpacecraftDirectory.page(c.org, c.mission, cursor: "x")
  end

  test "the summary and SCIDs come with the first page only; later pages carry just their rows (#933)",
       c do
    for {name, scid} <- [{"alpha", 1}, {"bravo", nil}, {"charlie", nil}],
        do: craft!(c, name, scid: scid)

    {:ok, first} = SpacecraftDirectory.page(c.org, c.mission, limit: 2)
    assert %{total: 3} = first.summary
    assert %{scids_in_use: [1], next_free_scid: 2} = first

    {:ok, later} = SpacecraftDirectory.page(c.org, c.mission, limit: 2, cursor: first.next_cursor)
    assert Enum.map(later.spacecraft, & &1.name) == ["charlie"]
    refute Map.has_key?(later, :summary)
    refute Map.has_key?(later, :scids_in_use)
    refute Map.has_key?(later, :next_free_scid)
    assert later.telemetry in [:ok, :degraded]
  end

  test "q matches name, profile name or a SCID prefix; the summary stays whole-mission", c do
    bus = profile!(c, "Cube Bus")
    craft!(c, "Earendil-1", scid: 101, profile_id: bus.spacecraft_type_id)
    craft!(c, "Earendil-2", scid: 102)
    craft!(c, "Nova", scid: 205, profile_id: bus.spacecraft_type_id)

    names = fn q ->
      {:ok, page} = SpacecraftDirectory.page(c.org, c.mission, q: q)
      Enum.map(page.spacecraft, & &1.name)
    end

    assert names.("earen") == ["Earendil-1", "Earendil-2"]
    assert names.("cube") == ["Earendil-1", "Nova"]
    assert names.("20") == ["Nova"]
    assert names.("10") == ["Earendil-1", "Earendil-2"]
    # Wildcards are literal.
    assert names.("%") == []
    assert names.("  ") == ["Earendil-1", "Earendil-2", "Nova"]

    {:ok, page} = SpacecraftDirectory.page(c.org, c.mission, q: "nova")
    assert %{total: 3, profiles: 1, without_profile: 1} = page.summary
  end

  test "the summary counts profiles, missing SCIDs, routing and craft never heard", c do
    bus = profile!(c, "Bus")
    a = craft!(c, "A", scid: 1, profile_id: bus.spacecraft_type_id)
    b = craft!(c, "B", scid: 2, profile_id: bus.spacecraft_type_id)
    craft!(c, "C", profile_id: bus.spacecraft_type_id)
    craft!(c, "D", scid: 4)
    route!(c, a)
    route!(c, b, false)

    {:ok, page} = SpacecraftDirectory.page(c.org, c.mission)

    assert page.summary == %{
             total: 4,
             profiles: 1,
             without_profile: 1,
             without_scid: 1,
             without_routing_rule: 3,
             awaiting_first_aos: 4
           }

    by_name = Map.new(page.spacecraft, &{&1.name, &1})
    assert by_name["A"].routing_rule_count == 1 and by_name["A"].ready
    assert by_name["B"].routing_rule_count == 0
  end

  test "an archived craft is not in the directory or its summary", c do
    craft!(c, "Live")
    gone = craft!(c, "Gone")

    {:ok, _} =
      SpacecraftStore.archive_spacecraft(c.org, c.mission, gone.spacecraft_id, %{kind: "test"})

    {:ok, page} = SpacecraftDirectory.page(c.org, c.mission)
    assert Enum.map(page.spacecraft, & &1.name) == ["Live"]
    assert page.summary.total == 1
  end

  test "1,000 spacecraft page in bounded queries on the name index; the summary is whole-fleet",
       c do
    now = DateTime.utc_now()

    rows =
      for n <- 1..1_000 do
        %{
          spacecraft_id: "sc-#{String.pad_leading(Integer.to_string(n), 4, "0")}",
          organization_id: c.org,
          mission_id: c.mission,
          display_name: "Craft #{String.pad_leading(Integer.to_string(n), 4, "0")}",
          scid: if(rem(n, 2) == 0, do: n),
          metadata: %{},
          lifecycle_state: "active",
          inserted_at: now
        }
      end

    Repo.insert_all("mission_spacecraft", rows)

    assert walk(c, limit: 500) |> length() == 1_000
    {:ok, page} = SpacecraftDirectory.page(c.org, c.mission, limit: 500)
    assert length(page.spacecraft) == 500
    assert %{total: 1_000, without_scid: 500, without_profile: 1_000} = page.summary

    Repo.query!("ANALYZE mission_spacecraft")
    # On a table this small the planner rightly prefers a seq scan; forbid it to show the index
    # serves the order and the keyset range without a sort (what a large fleet gets).
    Repo.query!("SET LOCAL enable_seqscan = off")

    # And forbid a sort, so a cheaper index on one column plus a sort can't be chosen in its place.
    Repo.query!("SET LOCAL enable_sort = off")

    # The page is a range scan of the (organization, mission, name, id) index, not a sort.
    %{rows: plan} =
      Repo.query!(
        "EXPLAIN SELECT spacecraft_id FROM mission_spacecraft WHERE organization_id = $1 AND mission_id = $2 AND lifecycle_state = 'active' AND (display_name > 'Craft 0500' OR (display_name = 'Craft 0500' AND spacecraft_id > 'sc-0500')) ORDER BY display_name, spacecraft_id LIMIT 201",
        [c.org, c.mission]
      )

    text = plan |> List.flatten() |> Enum.join("\n")
    assert text =~ "mission_spacecraft_name_cursor_idx"
    refute text =~ "Sort"
  end
end
