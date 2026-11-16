defmodule Cadence.Contacts.JournalReclaimTest do
  @moduledoc """
  #71 follow-up: a settled contact's ingress journal leaves the disk after its retention, only
  when it is drained on disk and nothing has it open; anything else is kept (and an undrained
  stream is marked once for a manual decision).
  """
  use Cadence.DataCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.Contacts.{ContactStore, JournalReclaim, RealizedContact}
  alias Cadence.IngressJournal.FileSystem
  alias Cadence.Runtime.ProcessNamespace

  @org "org-journal-reclaim"
  @mission "mission-journal-reclaim"
  @now ~U[2026-11-17 12:00:00Z]
  @settled_long_ago "2026-11-14T01:44:30Z"

  setup do
    persist_mission_scope(@org, @mission)

    base_path =
      Path.join(System.tmp_dir!(), "journal-reclaim-#{System.unique_integer([:positive])}")

    previous = Application.get_env(:cadence, :ingress_journal)

    Application.put_env(
      :cadence,
      :ingress_journal,
      Keyword.merge(previous || [], enabled?: true, base_path: base_path)
    )

    JournalReclaim.reset_pressure()

    on_exit(fn ->
      Application.put_env(:cadence, :ingress_journal, previous)
      JournalReclaim.reset_pressure()
      File.rm_rf!(base_path)
    end)

    %{base_path: base_path}
  end

  test "a settled contact's drained stream is reclaimed after its retention, and recorded", c do
    contact = settled_contact!("drained")
    stream!(c, contact, "path-a", [:processing, :archive])

    # Within the retention it stays.
    assert :none = JournalReclaim.run(@mission, ~U[2026-11-14 12:00:00Z])
    assert [_stream] = streams(c)

    assert {:reclaimed, id} = JournalReclaim.run(@mission, @now)
    assert id == contact.realized_contact_id
    assert streams(c) == []

    assert %{"journal_disk" => "reclaimed", "journal_disk_at" => at, "journal" => "enabled"} =
             settlement(contact)

    assert at == DateTime.to_iso8601(@now)
    assert :none = JournalReclaim.run(@mission, @now)
  end

  test "a stream whose cursor lags is KEPT and marked once for a manual decision", c do
    contact = settled_contact!("lagging")
    stream!(c, contact, "path-a", [:processing])

    assert {:retained, _id} = JournalReclaim.run(@mission, @now)
    assert [_kept] = streams(c)

    assert %{"journal_disk" => "retained_undrained", "journal_disk_bytes" => bytes} =
             settlement(contact)

    assert bytes > 0
    assert :none = JournalReclaim.run(@mission, @now)
    assert [_still_kept] = streams(c)
  end

  test "an open journal, a never-inspected contact, or an unsettled one keeps its stream", c do
    open = settled_contact!("open")
    stream!(c, open, "path-a", [:processing, :archive], keep_open: true)

    absent = settled_contact!("absent", %{"runtime" => "absent"})
    stream!(c, absent, "path-a", [:processing, :archive])

    unsettled = settled_contact!("unsettled", %{"state" => "unsettled"})
    stream!(c, unsettled, "path-a", [:processing, :archive])

    assert :none = JournalReclaim.run(@mission, @now)
    assert length(streams(c)) == 3
  end

  test "a journal open on another node of a cluster keeps the stream (api-ops)", c do
    contact = settled_contact!("remote")
    stream!(c, contact, "path-a", [:processing, :archive])

    # Clustered placement: runtime names are global. A journal registered from "another node"
    # is only a global name; nothing in the local Registry.
    %ProcessNamespace{registry: registry} = ProcessNamespace.default()
    {:ok, previous} = with :error <- Registry.meta(registry, :cluster), do: {:ok, nil}
    :ok = Registry.put_meta(registry, :cluster, id: "reclaim-test")
    on_exit(fn -> Registry.put_meta(registry, :cluster, previous) end)

    remote = spawn(fn -> Process.sleep(:infinity) end)
    key = {:provider_ingress_journal, @mission, contact.realized_contact_id, "path-a", "remote"}
    name = {Cadence.Runtime.Cluster, "reclaim-test", registry, key}
    :yes = :global.register_name(name, remote)
    on_exit(fn -> :global.unregister_name(name) end)

    assert :none = JournalReclaim.run(@mission, @now)
    assert [_kept] = streams(c)

    :global.unregister_name(name)
    assert {:reclaimed, _} = JournalReclaim.run(@mission, @now)
  end

  test "a contact with two streams is recorded reclaimed only when both are gone", c do
    contact = settled_contact!("two-paths")
    stream!(c, contact, "path-a", [:processing, :archive])
    stream!(c, contact, "path-b", [:processing, :archive])

    assert {:reclaimed, _} = JournalReclaim.run(@mission, @now)
    assert [_one_left] = streams(c)
    refute Map.has_key?(settlement(contact), "journal_disk")

    assert {:reclaimed, _} = JournalReclaim.run(@mission, @now)
    assert streams(c) == []
    assert %{"journal_disk" => "reclaimed"} = settlement(contact)
  end

  describe "under disk pressure (director 11-15)" do
    @recent "2026-11-17T10:00:00Z"
    @earlier "2026-11-17T08:00:00Z"

    test "a kept stream goes before its 72 h, oldest settled first, logged and marked", c do
      newer = settled_contact!("newer", %{"settled_at" => @recent})
      older = settled_contact!("older", %{"settled_at" => @earlier})
      stream!(c, newer, "path-a", [:processing, :archive])
      stream!(c, older, "path-a", [:processing, :archive])

      # Not under pressure: both are within the 72 h and stay.
      assert :none = JournalReclaim.run(@mission, @now, volume: volume(79.0))

      log =
        capture_log(fn ->
          assert {:reclaimed, id} = JournalReclaim.run(@mission, @now, volume: volume(85.0))
          assert id == older.realized_contact_id
        end)

      assert log =~ "EARLY" and log =~ older.realized_contact_id and log =~ "85.0 % full"

      assert %{
               "journal_disk" => "reclaimed_early",
               "journal_disk_reason" => "volume_pressure",
               "journal_disk_volume_percent" => 85.0
             } = settlement(older)

      assert [%{context: %{realized_contact_id: left}}] = streams(c)
      assert left == newer.realized_contact_id
    end

    test "never a stream still being stored, an open one, or an unsettled one; nothing marked",
         c do
      storing = settled_contact!("storing", %{"settled_at" => @recent})
      stream!(c, storing, "path-a", [:processing])

      open = settled_contact!("open-early", %{"settled_at" => @recent})
      stream!(c, open, "path-a", [:processing, :archive], keep_open: true)

      unsettled = settled_contact!("unsettled-early", %{"state" => "unsettled"})
      stream!(c, unsettled, "path-a", [:processing, :archive])

      # Read to the end, but a partial frame keeps its resume point short of it.
      partial = settled_contact!("partial-frame", %{"settled_at" => @recent})
      stream!(c, partial, "path-a", [:processing, :archive], resume_offset: 3)

      assert :none = JournalReclaim.run(@mission, @now, volume: volume(95.0))
      assert length(streams(c)) == 4
      refute Map.has_key?(settlement(storing), "journal_disk")
    end

    test "runs from 80 % until back under 70 % (hysteresis)" do
      assert nil == JournalReclaim.pressure(volume: volume(75.0))
      assert %{percent: 80.0} = JournalReclaim.pressure(volume: volume(80.0))
      assert %{percent: 72.0} = JournalReclaim.pressure(volume: volume(72.0))
      assert nil == JournalReclaim.pressure(volume: volume(69.9))
      assert nil == JournalReclaim.pressure(volume: volume(75.0))
    end

    test "deployment thresholds, and a free-space floor (a big shared disk isn't an emergency)" do
      t = %{reclaim_at: 97.0, reclaim_to: 95.0, emergency_free_bytes: 100}
      # volume/1 is a 1,000-byte disk: 98 % leaves 20 bytes free, under the floor.
      assert %{percent: 98.0} = JournalReclaim.pressure(volume: volume(98.0), thresholds: t)
      assert %{} = JournalReclaim.pressure(volume: volume(96.0), thresholds: t)
      assert nil == JournalReclaim.pressure(volume: volume(94.0), thresholds: t)
      assert nil == JournalReclaim.pressure(volume: volume(96.0), thresholds: t)

      plenty = %{t | emergency_free_bytes: 10}
      assert nil == JournalReclaim.pressure(volume: volume(98.0), thresholds: plenty)
    end

    test "an unreadable disk is never pressure: the 72 h holds (fail-safe)", c do
      contact = settled_contact!("unknown-disk", %{"settled_at" => @recent})
      stream!(c, contact, "path-a", [:processing, :archive])

      assert %{} = JournalReclaim.pressure(volume: volume(90.0))
      assert nil == JournalReclaim.pressure(volume: :unknown)
      assert :none = JournalReclaim.run(@mission, @now, volume: :unknown)
      assert [_kept] = streams(c)

      # And the real reader is :unknown here (no disksup under test).
      assert :none = JournalReclaim.run(@mission, @now)
    end
  end

  defp volume(percent),
    do: {:ok, %{size_bytes: 1_000, used_bytes: round(percent * 10), percent: percent}}

  defp settled_contact!(name, settlement \\ %{}) do
    contact =
      RealizedContact.new(%{
        realized_contact_id: "reclaim-" <> name,
        organization_id: @org,
        mission_id: @mission,
        source_endpoint_refs: [],
        paths: []
      })

    {:ok, _} = Cadence.Contacts.persist_realized_contact(@org, contact)
    {:ok, stored} = ContactStore.fetch_realized(@mission, contact.realized_contact_id)

    settled =
      Map.merge(
        %{"state" => "settled", "settled_at" => @settled_long_ago, "journal" => "enabled"},
        settlement
      )

    {:ok, completed} =
      ContactStore.update_realized_lifecycle(stored, :completed, %{"settlement" => settled})

    completed
  end

  # A journal stream of the contact with one record and the given consumers acknowledged. Stopped
  # (its final checkpoint written) unless kept open, as a running runtime or replay holds it.
  defp stream!(c, contact, path_id, acked, opts \\ []) do
    binding = "binding-#{System.unique_integer([:positive])}"

    key =
      {:provider_ingress_journal, @mission, contact.realized_contact_id, path_id, binding}

    journal_opts = [
      name: ProcessNamespace.via(ProcessNamespace.default(), key),
      mission_id: @mission,
      realized_contact_id: contact.realized_contact_id,
      path_id: path_id,
      provider_binding_id: binding,
      base_path: c.base_path,
      durability: :sync
    ]

    journal = start_supervised!({FileSystem, journal_opts})
    {:ok, entry} = FileSystem.append(journal, "captured", DateTime.utc_now())

    for consumer <- acked do
      resume = if consumer == :processing, do: Keyword.take(opts, [:resume_offset]), else: []
      :ok = FileSystem.acknowledge(journal, consumer, entry.end_offset, resume)
    end

    if not Keyword.get(opts, :keep_open, false),
      do: :ok = stop_supervised({:ingress_journal, binding})
  end

  defp streams(c), do: FileSystem.stored_stream_directories(c.base_path)

  defp settlement(contact) do
    {:ok, current} = ContactStore.fetch_realized(@mission, contact.realized_contact_id)
    current.metadata["settlement"]
  end
end
