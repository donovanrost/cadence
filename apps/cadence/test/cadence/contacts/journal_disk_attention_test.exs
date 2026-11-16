defmodule Cadence.Contacts.JournalDiskAttentionTest do
  @moduledoc """
  The journal-disk item of the ingress_backpressure source (ux U66): the monitor (in its own
  namespace, with the disk reading injected; the shared monitor is global) and the item's shape.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.{ContactStore, IngressBackpressureAttention, RealizedContact}
  alias Cadence.Reads.ActionQueue.{AttentionItems, Item}
  alias Cadence.Runtime.IngressBackpressureMonitor, as: Monitor
  alias Cadence.Runtime.ProcessNamespace

  defmodule FakeJournal do
    @moduledoc false
    use GenServer

    def start_link({name, last_error}),
      do: GenServer.start_link(__MODULE__, last_error, name: name)

    @impl true
    def init(last_error), do: {:ok, last_error}

    @impl true
    def handle_call(:snapshot, _from, last_error) do
      {:reply,
       {:ok, %{retained_bytes: 10, max_bytes: 1_000, stream_id: "fake", last_error: last_error}},
       last_error}
    end
  end

  @org "org-journal-disk"
  @mission "mission-journal-disk"
  @size 100_000_000_000

  describe "the monitor" do
    setup do
      namespace =
        ProcessNamespace.new!(
          root_supervisor: __MODULE__.Root,
          registry: __MODULE__.Registry,
          mission_supervisor: __MODULE__.Missions,
          capability_registry: __MODULE__.Capabilities
        )

      start_supervised!({Registry, keys: :unique, name: __MODULE__.Registry})
      reading = start_supervised!({Agent, fn -> {:unknown, []} end})

      start_supervised!(
        {Monitor,
         process_namespace: namespace,
         interval_ms: 3_600_000,
         disk_every_ticks: 1,
         journal_volume: fn -> Agent.get(reading, & &1) end}
      )

      %{namespace: namespace, reading: reading}
    end

    test "raises from the disk reading, names this mission's holders, and clears below 60 %",
         %{namespace: ns, reading: reading} do
      streams = [
        %{mission_id: @mission, realized_contact_id: "c1", stream_id: "s1", bytes: 900},
        %{mission_id: "elsewhere", realized_contact_id: "x1", stream_id: "s2", bytes: 400}
      ]

      set(reading, 92.0, streams)
      :ok = Monitor.sample_now(ns)

      assert %{disk: disk} = Monitor.snapshot(@mission, ns)
      assert %{level: :critical, percent: 92.0, refusing: false} = disk
      assert disk.holders == [%{realized_contact_id: "c1", bytes: 900}]
      assert disk.other_missions_bytes == 400

      set(reading, 59.0, [])
      :ok = Monitor.sample_now(ns)

      assert %{disk: nil, disk_resolved: [%{refused_from: nil}]} = Monitor.snapshot(@mission, ns)
    end

    test "is refusing while a journal's appends fail for lack of space",
         %{namespace: ns, reading: reading} do
      key = {:provider_ingress_journal, @mission, "c1", "path-a", "binding-a"}
      start_supervised!({FakeJournal, {ProcessNamespace.via(ns, key), ":enospc"}})

      set(reading, 99.5, [])
      :ok = Monitor.sample_now(ns)

      assert %{disk: %{refusing: true, refused_since: %DateTime{}}} =
               Monitor.snapshot(@mission, ns)
    end

    test "an unreadable disk raises nothing", %{namespace: ns} do
      :ok = Monitor.sample_now(ns)
      assert %{disk: nil, disk_resolved: []} = Monitor.snapshot(@mission, ns)
    end
  end

  describe "the item" do
    test "is P1 when critical; holders say storing or kept until when; others unnamed" do
      persist_mission_scope(@org, @mission)
      kept = contact!("kept", %{"state" => "settled", "settled_at" => "2026-11-15T02:48:00Z"})
      storing = contact!("storing", %{"state" => "unsettled"})

      disk = %{
        level: :critical,
        raised_at: ~U[2026-11-15 12:00:00Z],
        percent: 91.0,
        used_bytes: round(@size * 0.91),
        size_bytes: @size,
        rate_bytes_per_hour: 1_800_000_000,
        eta_full_s: 18_000,
        holders: [
          %{realized_contact_id: storing.realized_contact_id, bytes: 800},
          %{realized_contact_id: kept.realized_contact_id, bytes: 1_200}
        ],
        more_count: 4,
        other_missions_bytes: 2_100,
        refusing: false,
        refused_since: nil
      }

      assert [item] = IngressBackpressureAttention.disk_items(@org, @mission, disk)

      assert %{id: "journal_disk", conflict: "journal_disk", p1: true} =
               item

      assert %{percent: 91.0, more_count: 4, other_missions_bytes: 2_100, eta_full_s: 18_000} =
               item.journal_disk

      assert [
               %{state: "storing", kept_until: nil, bytes: 800},
               %{state: "kept", kept_until: kept_until, bytes: 1_200}
             ] = item.journal_disk.holders

      assert kept_until == ~U[2026-11-18 02:48:00Z]

      caution = %{disk | level: :caution, holders: []}

      assert [%{p1: false}] =
               IngressBackpressureAttention.disk_items(@org, @mission, caution)

      assert [] == IngressBackpressureAttention.disk_items(@org, @mission, nil)

      # On the wire (fe-ops): the shared keys present, null; each holder named.
      names = %{
        spacecraft: %{
          "sc-8" =>
            Item.member(%{
              id: "sc-8",
              name: "EARENDIL-008",
              scid: 8,
              plane: nil,
              stale: nil,
              last_received_at: nil,
              violating_points: nil
            })
        },
        station:
          &StationRefs.resolve(&1, %{"svb" => %{id: "st-1", code: "SVB", name: "Svalbard"}}),
        providers: %{}
      }

      holders = [
        %{hd(item.journal_disk.holders) | spacecraft_id: "sc-8", ground_station_ref: "svb"},
        %{List.last(item.journal_disk.holders) | spacecraft_id: nil, ground_station_ref: nil}
      ]

      wire =
        AttentionItems.object(put_in(item, [:journal_disk, :holders], holders), names)

      for key <- [
            :contact_id,
            :station,
            :provider,
            :starts_at,
            :provider_message,
            :acknowledged_by
          ],
          do: assert(Map.has_key?(wire, key), "missing #{key}")

      assert wire.contact_id == nil and wire.starts_at == nil and wire.acknowledged_by == nil

      assert [named, unnamed] = wire.journal_disk.holders
      assert named.spacecraft == %{id: "sc-8", name: "EARENDIL-008", scid: 8}
      assert %{ref: "svb", code: "SVB", name: "Svalbard"} = named.station
      assert unnamed.spacecraft == nil
      assert unnamed.station == %{ref: nil, id: nil, code: nil, name: nil}
    end
  end

  defp set(reading, percent, streams) do
    used = round(@size * percent / 100)

    Agent.update(reading, fn _ ->
      {{:ok, %{size_bytes: @size, used_bytes: used, percent: percent}}, streams}
    end)
  end

  defp contact!(name, settlement) do
    contact =
      RealizedContact.new(%{
        realized_contact_id: "disk-" <> name,
        organization_id: @org,
        mission_id: @mission,
        source_endpoint_refs: [],
        paths: []
      })

    {:ok, _} = Cadence.Contacts.persist_realized_contact(@org, contact)
    {:ok, stored} = ContactStore.fetch_realized(@mission, contact.realized_contact_id)

    {:ok, completed} =
      ContactStore.update_realized_lifecycle(stored, :completed, %{"settlement" => settlement})

    completed
  end
end
