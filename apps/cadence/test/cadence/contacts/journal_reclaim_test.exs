defmodule Cadence.Contacts.JournalReclaimTest do
  @moduledoc """
  #71 follow-up: a settled contact's ingress journal leaves the disk after its retention, only
  when it is drained on disk and nothing has it open; anything else is kept (and an undrained
  stream is marked once for a manual decision).
  """
  use Cadence.DataCase, async: false

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

    on_exit(fn ->
      Application.put_env(:cadence, :ingress_journal, previous)
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
    for consumer <- acked, do: :ok = FileSystem.acknowledge(journal, consumer, entry.end_offset)

    if not Keyword.get(opts, :keep_open, false),
      do: :ok = stop_supervised({:ingress_journal, binding})
  end

  defp streams(c), do: FileSystem.stored_stream_directories(c.base_path)

  defp settlement(contact) do
    {:ok, current} = ContactStore.fetch_realized(@mission, contact.realized_contact_id)
    current.metadata["settlement"]
  end
end
