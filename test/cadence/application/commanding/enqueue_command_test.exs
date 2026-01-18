defmodule Cadence.Application.Commanding.EnqueueCommandTest do
  @moduledoc """
  Use case tests for EnqueueCommand.

  Tests the command queuing logic with in-memory adapters.
  """
  use Cadence.UseCaseCase

  alias Cadence.Application.Commanding.EnqueueCommand
  alias Cadence.Domain.Targeting.Entities.Target, as: TargetEntity
  alias Cadence.Test.Adapters.FakeEventPublisher
  alias Cadence.Test.Adapters.InMemoryEventRecorder
  alias Cadence.Test.Adapters.InMemoryTargetRepository

  describe "enqueue/2" do
    test "enqueues a command with default priority" do
      attrs = valid_enqueue_attrs()

      {:ok, entry} = EnqueueCommand.enqueue(attrs)

      assert entry.id != nil
      assert entry.command_name == attrs.command_name
      assert entry.status == :pending
      assert entry.priority == 3
      assert entry.sequence_number != nil
    end

    test "enqueues with custom priority" do
      attrs = valid_enqueue_attrs()

      {:ok, entry} = EnqueueCommand.enqueue(attrs, priority: 1)

      assert entry.priority == 1
    end

    test "enqueues with scheduled_at" do
      attrs = valid_enqueue_attrs()
      scheduled = from_now(30, :minutes)

      {:ok, entry} = EnqueueCommand.enqueue(attrs, scheduled_at: scheduled)

      assert entry.scheduled_at == scheduled
    end

    test "enqueues with expires_at" do
      attrs = valid_enqueue_attrs()
      expires = from_now(1, :hour)

      {:ok, entry} = EnqueueCommand.enqueue(attrs, expires_at: expires)

      assert entry.expires_at == expires
    end

    test "assigns sequential sequence numbers" do
      attrs = valid_enqueue_attrs()

      {:ok, entry1} = EnqueueCommand.enqueue(attrs)
      {:ok, entry2} = EnqueueCommand.enqueue(attrs)
      {:ok, entry3} = EnqueueCommand.enqueue(attrs)

      assert entry2.sequence_number == entry1.sequence_number + 1
      assert entry3.sequence_number == entry2.sequence_number + 1
    end

    test "broadcasts enqueued event" do
      attrs = valid_enqueue_attrs()

      {:ok, _entry} = EnqueueCommand.enqueue(attrs)

      events = FakeEventPublisher.list_events()
      assert length(events) >= 1

      assert Enum.any?(events, fn entry ->
               entry.topic =~ "target:" and match?({:command_enqueued, _}, entry.event)
             end)
    end

    test "records command_queued event" do
      attrs = valid_enqueue_attrs()

      {:ok, _entry} = EnqueueCommand.enqueue(attrs)

      assert InMemoryEventRecorder.recorded?(:command_queued)
    end
  end

  describe "schedule/3" do
    test "schedules a command for future execution" do
      attrs = valid_enqueue_attrs()
      scheduled = from_now(1, :hour)

      {:ok, entry} = EnqueueCommand.schedule(attrs, scheduled)

      assert entry.scheduled_at == scheduled
      assert entry.status == :pending
    end
  end

  describe "enqueue_emergency/2" do
    test "enqueues with priority 0" do
      attrs = valid_enqueue_attrs()

      {:ok, entry} = EnqueueCommand.enqueue_emergency(attrs)

      assert entry.priority == 0
    end

    test "overrides any provided priority" do
      attrs = valid_enqueue_attrs()

      {:ok, entry} = EnqueueCommand.enqueue_emergency(attrs, priority: 5)

      assert entry.priority == 0
    end
  end

  describe "enqueue_batch/2" do
    test "enqueues multiple commands" do
      commands = [
        {valid_enqueue_attrs(command_name: "CMD_1"), []},
        {valid_enqueue_attrs(command_name: "CMD_2"), []},
        {valid_enqueue_attrs(command_name: "CMD_3"), []}
      ]

      {:ok, entries} = EnqueueCommand.enqueue_batch(commands)

      assert length(entries) == 3
      assert Enum.map(entries, & &1.command_name) == ["CMD_1", "CMD_2", "CMD_3"]
    end

    test "applies base_opts to all commands" do
      commands = [
        {valid_enqueue_attrs(command_name: "CMD_1"), []},
        {valid_enqueue_attrs(command_name: "CMD_2"), []}
      ]

      {:ok, entries} = EnqueueCommand.enqueue_batch(commands, priority: 1)

      assert Enum.all?(entries, &(&1.priority == 1))
    end

    test "individual opts override base_opts" do
      commands = [
        {valid_enqueue_attrs(command_name: "CMD_1"), [priority: 2]},
        {valid_enqueue_attrs(command_name: "CMD_2"), []}
      ]

      {:ok, entries} = EnqueueCommand.enqueue_batch(commands, priority: 3)

      [entry1, entry2] = entries
      assert entry1.priority == 2
      assert entry2.priority == 3
    end

    test "maintains ordering through sequence numbers" do
      commands = [
        {valid_enqueue_attrs(command_name: "CMD_1"), []},
        {valid_enqueue_attrs(command_name: "CMD_2"), []},
        {valid_enqueue_attrs(command_name: "CMD_3"), []}
      ]

      {:ok, entries} = EnqueueCommand.enqueue_batch(commands)

      sequences = Enum.map(entries, & &1.sequence_number)
      assert sequences == Enum.sort(sequences)
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp valid_enqueue_attrs(overrides \\ []) do
    target = build_target()

    defaults = %{
      organization_id: random_id(),
      mission_id: target.mission_id,
      target_id: target.id,
      command_name: Keyword.get(overrides, :command_name, "TEST_CMD"),
      user_id: random_id(),
      parameters: %{"param1" => "value1"}
    }

    Map.merge(defaults, Map.new(overrides))
  end

  defp build_target do
    {:ok, target} =
      TargetEntity.new(%{
        mission_id: random_id(),
        definition_set_id: random_id(),
        name: "Test Target",
        identifier: "SAT_#{System.unique_integer([:positive])}",
        type: :spacecraft
      })

    {:ok, saved} = InMemoryTargetRepository.save(target)
    saved
  end
end
