defmodule Cadence.Commands.QueueTest do
  use Cadence.DataCase, async: false

  alias Cadence.Commands
  alias Cadence.Commands.{Queue, QueueEntry}
  alias Cadence.Organizations.Organization
  alias Cadence.Missions.Mission
  alias Cadence.Targets.Target

  setup do
    # Create organization
    org =
      %Organization{}
      |> Organization.changeset(%{
        name: "Test Org",
        slug: "test-org-#{System.unique_integer([:positive])}",
        status: "active",
        subscription_tier: "free"
      })
      |> Repo.insert!()

    # Create mission
    mission =
      %Mission{}
      |> Mission.changeset(%{
        organization_id: org.id,
        name: "Test Mission",
        slug: "test-mission-#{System.unique_integer([:positive])}",
        status: "active",
        phase: "operational"
      })
      |> Repo.insert!()

    # Create target
    target =
      %Target{}
      |> Target.changeset(%{
        mission_id: mission.id,
        name: "SC1",
        type: "spacecraft",
        identifier: "SC1_#{System.unique_integer([:positive])}",
        status: "online"
      })
      |> Repo.insert!()

    # Start the queue for this mission
    {:ok, _pid} = start_supervised({Queue, mission_id: mission.id})

    %{
      org: org,
      mission: mission,
      target: target
    }
  end

  describe "enqueue/4" do
    test "enqueues a command successfully", %{mission: mission, target: target} do
      result = Commands.enqueue(mission.id, "SET_MODE", %{mode: 1}, target: target.id)

      assert {:ok, %QueueEntry{} = entry} = result
      assert entry.mission_id == mission.id
      assert entry.target_id == target.id
      assert entry.command_name == "SET_MODE"
      assert entry.parameters == %{mode: 1}
      assert entry.status == :pending
      assert entry.priority == 3
      assert entry.sequence_number == 1
    end

    test "assigns incrementing sequence numbers", %{mission: mission, target: target} do
      {:ok, entry1} = Commands.enqueue(mission.id, "CMD_1", %{}, target: target.id)
      {:ok, entry2} = Commands.enqueue(mission.id, "CMD_2", %{}, target: target.id)
      {:ok, entry3} = Commands.enqueue(mission.id, "CMD_3", %{}, target: target.id)

      assert entry1.sequence_number == 1
      assert entry2.sequence_number == 2
      assert entry3.sequence_number == 3
    end

    test "respects custom priority", %{mission: mission, target: target} do
      {:ok, entry} = Commands.enqueue(mission.id, "URGENT", %{}, target: target.id, priority: 1)

      assert entry.priority == 1
    end

    test "accepts scheduled_at option", %{mission: mission, target: target} do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      {:ok, entry} = Commands.enqueue(mission.id, "DELAYED", %{}, target: target.id, scheduled_at: future)

      assert entry.scheduled_at == future
    end

    test "accepts expires_at option", %{mission: mission, target: target} do
      future = DateTime.add(DateTime.utc_now(), 300, :second)
      {:ok, entry} = Commands.enqueue(mission.id, "EXPIRING", %{}, target: target.id, expires_at: future)

      assert entry.expires_at == future
    end

    test "returns error when target not provided", %{mission: mission} do
      result = Commands.enqueue(mission.id, "SET_MODE", %{}, [])

      assert {:error, :target_required} = result
    end
  end

  describe "pause_queue/1 and resume_queue/1" do
    test "pauses and resumes queue", %{mission: mission} do
      # Initially not paused
      status = Commands.queue_status(mission.id)
      refute status.paused

      # Pause
      :ok = Commands.pause_queue(mission.id)
      status = Commands.queue_status(mission.id)
      assert status.paused

      # Resume
      :ok = Commands.resume_queue(mission.id)
      status = Commands.queue_status(mission.id)
      refute status.paused
    end
  end

  describe "cancel_queued/2" do
    test "cancels a pending entry", %{mission: mission, target: target} do
      {:ok, entry} = Commands.enqueue(mission.id, "TO_CANCEL", %{}, target: target.id)

      {:ok, cancelled} = Commands.cancel_queued(mission.id, entry.id)

      assert cancelled.status == :cancelled
    end

    test "returns error for non-existent entry", %{mission: mission} do
      result = Commands.cancel_queued(mission.id, Ecto.UUID.generate())

      assert {:error, :not_found} = result
    end
  end

  describe "cancel_all_queued_for_target/2" do
    test "cancels all pending entries for a target", %{mission: mission, target: target} do
      {:ok, _} = Commands.enqueue(mission.id, "CMD_1", %{}, target: target.id)
      {:ok, _} = Commands.enqueue(mission.id, "CMD_2", %{}, target: target.id)
      {:ok, _} = Commands.enqueue(mission.id, "CMD_3", %{}, target: target.id)

      {:ok, count} = Commands.cancel_all_queued_for_target(mission.id, target.id)

      assert count == 3

      # Verify all are cancelled
      entries = Commands.list_queue_entries(mission.id, status: :pending)
      assert Enum.empty?(entries)
    end
  end

  describe "clear_queue/1" do
    test "clears all pending entries", %{mission: mission, target: target} do
      {:ok, _} = Commands.enqueue(mission.id, "CMD_1", %{}, target: target.id)
      {:ok, _} = Commands.enqueue(mission.id, "CMD_2", %{}, target: target.id)

      {:ok, count} = Commands.clear_queue(mission.id)

      assert count == 2

      entries = Commands.list_queue_entries(mission.id, status: :pending)
      assert Enum.empty?(entries)
    end
  end

  describe "queue_status/1" do
    test "returns queue statistics", %{mission: mission, target: target} do
      {:ok, _} = Commands.enqueue(mission.id, "CMD_1", %{}, target: target.id)
      {:ok, _} = Commands.enqueue(mission.id, "CMD_2", %{}, target: target.id)

      status = Commands.queue_status(mission.id)

      assert status.mission_id == mission.id
      assert status.pending == 2
      assert status.executing == 0
      assert status.paused == false
    end
  end

  describe "list_queued/2" do
    test "lists pending entries in priority order", %{mission: mission, target: target} do
      {:ok, _} = Commands.enqueue(mission.id, "LOW", %{}, target: target.id, priority: 4)
      {:ok, _} = Commands.enqueue(mission.id, "HIGH", %{}, target: target.id, priority: 1)
      {:ok, _} = Commands.enqueue(mission.id, "NORMAL", %{}, target: target.id, priority: 3)

      entries = Commands.list_queued(mission.id)

      assert length(entries) == 3
      assert Enum.at(entries, 0).command_name == "HIGH"
      assert Enum.at(entries, 1).command_name == "NORMAL"
      assert Enum.at(entries, 2).command_name == "LOW"
    end

    test "filters by target_id", %{mission: mission, target: target} do
      # Create another target
      target2 =
        %Target{}
        |> Target.changeset(%{
          mission_id: mission.id,
          name: "SC2",
          type: "spacecraft",
          identifier: "SC2_#{System.unique_integer([:positive])}",
          status: "online"
        })
        |> Repo.insert!()

      {:ok, _entry1} = Commands.enqueue(mission.id, "CMD_SC1", %{}, target: target.id)
      {:ok, _entry2} = Commands.enqueue(mission.id, "CMD_SC2", %{}, target: target2.id)

      entries = Commands.list_queued(mission.id, target_id: target.id)

      assert length(entries) == 1
      assert Enum.at(entries, 0).command_name == "CMD_SC1"
    end
  end

  describe "reorder_queued/3" do
    test "changes priority of a queued entry", %{mission: mission, target: target} do
      {:ok, entry} = Commands.enqueue(mission.id, "TO_REORDER", %{}, target: target.id, priority: 3)

      {:ok, updated} = Commands.reorder_queued(mission.id, entry.id, 1)

      assert updated.priority == 1
    end

    test "returns error for non-existent entry", %{mission: mission} do
      result = Commands.reorder_queued(mission.id, Ecto.UUID.generate(), 1)

      assert {:error, :not_found} = result
    end
  end

  describe "QueueEntry helpers" do
    test "ready?/1 returns true for pending entry without scheduled time" do
      entry = %QueueEntry{status: :pending, scheduled_at: nil}
      assert QueueEntry.ready?(entry)
    end

    test "ready?/1 returns true for pending entry with past scheduled time" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      entry = %QueueEntry{status: :pending, scheduled_at: past}
      assert QueueEntry.ready?(entry)
    end

    test "ready?/1 returns false for pending entry with future scheduled time" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      entry = %QueueEntry{status: :pending, scheduled_at: future}
      refute QueueEntry.ready?(entry)
    end

    test "ready?/1 returns false for non-pending entries" do
      entry = %QueueEntry{status: :executing, scheduled_at: nil}
      refute QueueEntry.ready?(entry)
    end

    test "expired?/1 returns false for entry without expires_at" do
      entry = %QueueEntry{expires_at: nil}
      refute QueueEntry.expired?(entry)
    end

    test "expired?/1 returns true for entry past expires_at" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      entry = %QueueEntry{expires_at: past}
      assert QueueEntry.expired?(entry)
    end

    test "expired?/1 returns false for entry before expires_at" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      entry = %QueueEntry{expires_at: future}
      refute QueueEntry.expired?(entry)
    end

    test "retriable?/1 returns true for failed entry under max attempts" do
      entry = %QueueEntry{status: :failed, attempts: 1, max_attempts: 3}
      assert QueueEntry.retriable?(entry)
    end

    test "retriable?/1 returns false for failed entry at max attempts" do
      entry = %QueueEntry{status: :failed, attempts: 3, max_attempts: 3}
      refute QueueEntry.retriable?(entry)
    end

    test "retriable?/1 returns false for non-failed entries" do
      entry = %QueueEntry{status: :pending, attempts: 0, max_attempts: 3}
      refute QueueEntry.retriable?(entry)
    end
  end
end
