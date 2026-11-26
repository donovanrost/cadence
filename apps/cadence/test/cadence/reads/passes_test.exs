defmodule Cadence.Reads.PassesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.GroundStation
  alias Cadence.Contacts.{ProviderReservation, ProviderReservations}
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Reads.Passes

  defp reservation(id, opts) do
    %ProviderReservation{
      provider_reservation_id: id,
      mission_id: "m1",
      provider_id: "simulator",
      lifecycle_state: Keyword.get(opts, :state, :confirmed),
      pass_phase: :scheduled,
      delivery_state: :pending,
      spacecraft_id: Keyword.get(opts, :spacecraft_id, "sc1"),
      starts_at: ~U[2026-11-08 03:00:00Z],
      ends_at: ~U[2026-11-08 03:10:00Z],
      scheduled_contact_id: "sched-#{id}",
      requested_snapshot_document: Keyword.get(opts, :requested, %{}),
      cadence_accepted_snapshot_document: Keyword.get(opts, :accepted, %{}),
      provider_confirmed_snapshot_document: %{},
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp station(id, code, name),
    do: %GroundStation{ground_station_id: id, display_name: name, metadata: %{"code" => code}}

  defp build(reservations, filters \\ %{}) do
    Passes.build(%{
      from: ~U[2026-11-08 00:00:00Z],
      to: ~U[2026-11-09 00:00:00Z],
      truncated: false,
      reservations: reservations,
      stations: [station("gs-svalbard", "SVL", "Svalbard")],
      spacecraft: [
        %Cadence.Spacecraft{
          spacecraft_id: "sc1",
          mission_id: "m1",
          display_name: "SC-1",
          scid: 101
        }
      ],
      filters: filters
    })
  end

  describe "build/1" do
    test "booking evidence: the provider's word, an operator's attestation, or none (U32)" do
      leg = %{"uplink" => %{"routing_rule_id" => "rr-1"}}

      marker = %{
        "action" => "booked",
        "actor" => %{"kind" => "user", "id" => "u1", "name" => "Mira K."}
      }

      attested = %{
        reservation("attested", state: :pending, metadata: %{"operator_resolution" => marker})
        | request_document: leg
      }

      confirmed = %{
        reservation("confirmed", state: :confirmed, metadata: %{"operator_resolution" => marker})
        | request_document: leg,
          provider_confirmed_snapshot_document: %{"uplink" => %{"status" => "included"}}
      }

      lost = reservation("lost", state: :canceled, metadata: %{"operator_resolution" => marker})
      downlink_only = reservation("downlink", state: :confirmed)

      %{passes: passes} = build([attested, confirmed, lost, downlink_only])
      by_id = Map.new(passes, &{&1.id, &1})

      assert %{
               booking_evidence: "operator_attested",
               attested_by: %{kind: "user", id: "u1", name: "Mira K."},
               uplink_confirmed: false,
               attention: nil
             } = by_id["attested"]

      # The provider confirming after an attestation makes it the provider's word.
      assert %{booking_evidence: "provider", attested_by: nil, uplink_confirmed: true} =
               by_id["confirmed"]

      assert %{booking_evidence: nil, attested_by: nil} = by_id["lost"]
      assert %{booking_evidence: "provider", uplink_confirmed: nil} = by_id["downlink"]
    end

    test "takes station and antenna from the newest snapshot and matches Cadence stations" do
      %{passes: [pass]} =
        build([
          reservation("r1",
            requested: %{"ground_station_ref" => "OLD"},
            accepted: %{
              "ground_station_ref" => "SVL",
              "antenna_or_service_pool_ref" => "ant-3",
              "synthetic" => true,
              "extensions" => %{"cost" => %{"amount" => 12.5, "currency" => "USD"}}
            }
          )
        ])

      assert pass.kind == "contact"
      assert pass.spacecraft == %{id: "sc1", name: "SC-1", scid: 101}
      assert pass.state == "confirmed"
      assert pass.station == %{ref: "SVL", id: "gs-svalbard", code: "SVL", name: "Svalbard"}
      assert pass.antenna == %{id: "ant-3", label: nil}
      assert pass.source.synthetic == true
      assert pass.cost == %{amount: 12.5, currency: "USD"}
      assert pass.max_elevation_deg == nil
      assert pass.uplink_capable == nil
    end

    test "an unknown station keeps its ref; empty snapshots fall back to metadata" do
      %{passes: [pass]} =
        build([reservation("r1", metadata: %{"ground_station_ref" => "KSAT-X"})])

      assert pass.station == %{ref: "KSAT-X", id: nil, code: nil, name: nil}
      assert pass.antenna == nil
      assert pass.source.synthetic == nil
    end

    test "filters by state and station" do
      reservations = [
        reservation("r1", accepted: %{"ground_station_ref" => "SVL"}),
        reservation("r2", state: :canceled, accepted: %{"ground_station_ref" => "SVL"}),
        reservation("r3", accepted: %{"ground_station_ref" => "OTHER"})
      ]

      assert %{passes: [%{id: "r2"}]} = build(reservations, %{states: ["canceled"]})

      assert ["r1", "r2"] =
               build(reservations, %{station: "gs-svalbard"}).passes |> Enum.map(& &1.id)
    end
  end

  describe "ended_by (qa #30)" do
    test "a workspace cancel or an operator's not-booked names the user; otherwise the provider" do
      user = %{kind: "user", id: "u1", name: "QA Org Admin"}

      resolution = %{
        "operator_resolution" => %{
          "action" => "not_booked",
          "actor" => %{"kind" => "user", "id" => "u2", "name" => "Ops Admin"}
        }
      }

      # #468: PassEnders.load names a #53 resolution's actor (ActorRef) under
      # {:resolution, id}; the builder reads it from there, never the stored name.
      passes =
        Passes.build(%{
          from: ~U[2026-11-08 00:00:00Z],
          to: ~U[2026-11-09 00:00:00Z],
          truncated: false,
          reservations: [
            reservation("live", []),
            reservation("ours", state: :canceled),
            reservation("resolved", state: :failed, metadata: resolution),
            reservation("theirs",
              state: :canceled,
              metadata: %{"provider_display_name" => "Earendil Demo Ground Network"}
            )
          ],
          enders: %{
            "ours" => user,
            {:resolution, "resolved"} => %{kind: "user", id: "u2", name: "Ops Admin"}
          },
          stations: [],
          filters: %{}
        }).passes
        |> Map.new(&{&1.id, &1.ended_by})

      assert passes["live"] == nil
      assert passes["ours"] == user
      assert passes["resolved"] == %{kind: "user", id: "u2", name: "Ops Admin"}

      assert passes["theirs"] == %{
               kind: "provider",
               id: "simulator",
               name: "Earendil Demo Ground Network"
             }
    end
  end

  describe "load/5" do
    setup do
      c = ProviderChangeFixtures.setup_contact()

      for {n, offset} <- [{1, 3_600}, {2, 2 * 86_400}] do
        attrs =
          c.reservation
          |> Map.from_struct()
          |> Map.merge(%{
            provider_reservation_id: "reservation-window-#{n}",
            provider_contact_ref: nil,
            idempotency_key: "window-key-#{n}",
            scheduled_contact_id: "schedule-window-#{n}",
            starts_at: DateTime.add(c.reservation.starts_at, offset),
            ends_at: DateTime.add(c.reservation.ends_at, offset)
          })

        {:ok, _} = ProviderReservations.create_attempt(c.organization_id, attrs)
      end

      c
    end

    test "returns reservations overlapping the window, oldest first", c do
      from = DateTime.add(c.reservation.starts_at, 300)
      to = DateTime.add(c.reservation.starts_at, 86_400)

      result = Passes.load(c.organization_id, c.mission_id, from, to)

      assert Enum.map(result.passes, & &1.id) == [
               c.reservation.provider_reservation_id,
               "reservation-window-1"
             ]

      assert result.truncated == false
      assert hd(result.passes).spacecraft_id == c.reservation.spacecraft_id
    end

    test "filters by spacecraft, caps with truncated, and is scoped", c do
      from = DateTime.add(c.reservation.starts_at, -60)
      to = DateTime.add(c.reservation.starts_at, 3 * 86_400)

      assert %{passes: [], truncated: false} =
               Passes.load(c.organization_id, c.mission_id, from, to, %{spacecraft_id: "nobody"})

      assert %{passes: [_one], truncated: true} =
               Passes.load(c.organization_id, c.mission_id, from, to, %{limit: 1})

      assert %{passes: []} = Passes.load("foreign", c.mission_id, from, to)
    end
  end
end
