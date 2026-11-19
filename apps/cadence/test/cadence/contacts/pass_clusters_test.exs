defmodule Cadence.Contacts.PassClustersTest do
  @moduledoc "#359 follow-up: is a pass near (AOS-5 min to LOS+5 min, or a realized contact active)?"
  use Cadence.DataCase, async: true

  alias Cadence.Contacts.ContactStore.{RealizedContactRow, ScheduledContactRow}
  alias Cadence.Contacts.PassClusters

  @org "org-pass-clusters"
  @mission "mission-pass-clusters"
  # A 10-minute pass: AOS 12:00, LOS 12:10.
  @aos ~U[2026-11-19 12:00:00.000000Z]
  @los ~U[2026-11-19 12:10:00.000000Z]

  setup do
    now = NaiveDateTime.utc_now()

    Repo.insert_all("organizations", [
      %{organization_id: @org, slug: @org, display_name: @org, inserted_at: now}
    ])

    Repo.insert_all("missions", [
      %{
        mission_id: @mission,
        organization_id: @org,
        slug: @mission,
        display_name: @mission,
        inserted_at: now
      }
    ])

    :ok
  end

  test "nothing scheduled: no pass is near" do
    refute PassClusters.near?(@aos)
  end

  test "near from 5 min before AOS to 5 min after LOS, and not outside that" do
    scheduled!("pass", "scheduled", @aos, @los)

    refute PassClusters.near?(at(@aos, -301))
    assert PassClusters.near?(at(@aos, -300))
    assert PassClusters.near?(at(@aos, 120))
    assert PassClusters.near?(at(@los, 300))
    refute PassClusters.near?(at(@los, 301))
  end

  test "a realized or completed contact counts by its window too" do
    scheduled!("done", "completed", @aos, @los)
    assert PassClusters.near?(at(@los, 60))
    refute PassClusters.near?(at(@los, 600))
  end

  test "a canceled contact never counts" do
    scheduled!("canceled", "canceled", @aos, @los)
    refute PassClusters.near?(at(@aos, 60))
  end

  test "a contact with no LOS counts only around its AOS" do
    scheduled!("open", "scheduled", @aos, nil)
    assert PassClusters.near?(at(@aos, 200))
    refute PassClusters.near?(at(@aos, 3_600))
  end

  test "a realized contact still active counts at any time (an overrun, or started by hand)" do
    refute PassClusters.near?(at(@los, 7_200))
    realized!("overrun", "active")
    assert PassClusters.near?(at(@los, 7_200))
  end

  test "a realized contact that stopped doesn't count" do
    realized!("stopped", "completed")
    refute PassClusters.near?(at(@los, 7_200))
  end

  defp at(time, seconds), do: DateTime.add(time, seconds, :second)

  defp scheduled!(id, state, starts_at, ends_at) do
    Repo.insert!(%ScheduledContactRow{
      scheduled_contact_id: "scheduled-#{id}",
      organization_id: @org,
      mission_id: @mission,
      source_endpoint_refs: ["station-a"],
      path_documents: %{},
      starts_at: starts_at,
      ends_at: ends_at,
      lifecycle_state: state
    })
  end

  defp realized!(id, state) do
    Repo.insert!(%RealizedContactRow{
      realized_contact_id: "realized-#{id}",
      organization_id: @org,
      mission_id: @mission,
      clock_mode: "realtime",
      lifecycle_state: state
    })
  end
end
