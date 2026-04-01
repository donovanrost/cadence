defmodule Cadence.SchedulesTest do
  use Cadence.UseCaseCase

  alias Cadence.Schedules

  describe "schedules" do
    setup do
      org_id = Ecto.UUID.generate()
      mission_id = Ecto.UUID.generate()
      procedure_id = Ecto.UUID.generate()

      %{org_id: org_id, mission_id: mission_id, procedure_id: procedure_id}
    end

    test "list_schedules/2 returns schedules for organization", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      schedule = schedule_fixture(org_id, mission_id, procedure_id)

      schedules = Schedules.list_schedules(org_id)
      assert length(schedules) == 1
      assert hd(schedules).id == schedule.id
    end

    test "list_schedules/2 filters by mission", %{org_id: org_id} do
      mission1_id = Ecto.UUID.generate()
      mission2_id = Ecto.UUID.generate()
      proc1_id = Ecto.UUID.generate()
      proc2_id = Ecto.UUID.generate()

      sched1 = schedule_fixture(org_id, mission1_id, proc1_id)
      _sched2 = schedule_fixture(org_id, mission2_id, proc2_id)

      schedules = Schedules.list_schedules(org_id, mission_id: mission1_id)
      assert length(schedules) == 1
      assert hd(schedules).id == sched1.id
    end

    test "list_schedules/2 filters enabled only", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      _enabled = schedule_fixture(org_id, mission_id, procedure_id, enabled: true)
      _disabled = schedule_fixture(org_id, mission_id, procedure_id, enabled: false)

      enabled_only = Schedules.list_schedules(org_id, enabled_only: true)
      assert length(enabled_only) == 1
    end

    test "create_schedule/1 creates cron schedule", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      {:ok, schedule} =
        Schedules.create_schedule(%{
          name: "Daily Check",
          organization_id: org_id,
          mission_id: mission_id,
          procedure_id: procedure_id,
          schedule_type: :cron,
          cron_expression: "0 8 * * *"
        })

      assert schedule.name == "Daily Check"
      assert schedule.schedule_type == :cron
      assert schedule.cron_expression == "0 8 * * *"
      assert schedule.enabled == true
    end

    test "create_schedule/1 creates one-time schedule", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      scheduled_time =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      {:ok, schedule} =
        Schedules.create_schedule(%{
          name: "One-time Task",
          organization_id: org_id,
          mission_id: mission_id,
          procedure_id: procedure_id,
          schedule_type: :once,
          scheduled_at: scheduled_time
        })

      assert schedule.schedule_type == :once
      assert schedule.scheduled_at == scheduled_time
    end

    test "create_schedule/1 validates cron expression required for cron type", %{
      org_id: org_id,
      procedure_id: procedure_id
    } do
      {:error, error} =
        Schedules.create_schedule(%{
          name: "Bad Schedule",
          organization_id: org_id,
          procedure_id: procedure_id,
          schedule_type: :cron
        })

      # Domain entity returns error tuples
      assert error == {:required_for_cron, :cron_expression}
    end

    test "create_schedule/1 validates scheduled_at required for once type", %{
      org_id: org_id,
      procedure_id: procedure_id
    } do
      {:error, error} =
        Schedules.create_schedule(%{
          name: "Bad Schedule",
          organization_id: org_id,
          procedure_id: procedure_id,
          schedule_type: :once
        })

      # Domain entity returns error tuples
      assert error == {:required_for_once, :scheduled_at}
    end

    test "create_schedule/1 validates cron expression syntax", %{
      org_id: org_id,
      procedure_id: procedure_id
    } do
      {:error, error} =
        Schedules.create_schedule(%{
          name: "Bad Cron",
          organization_id: org_id,
          procedure_id: procedure_id,
          schedule_type: :cron,
          cron_expression: "not a cron"
        })

      # Domain entity returns error tuples
      assert error == {:invalid, :cron_expression}
    end

    test "update_schedule/2 updates schedule", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      schedule = schedule_fixture(org_id, mission_id, procedure_id)

      {:ok, updated} = Schedules.update_schedule(schedule, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "delete_schedule/1 deletes schedule", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      schedule = schedule_fixture(org_id, mission_id, procedure_id)

      {:ok, _} = Schedules.delete_schedule(schedule)
      assert Schedules.get_schedule(schedule.id, org_id) == nil
    end

    test "enable_schedule/1 enables schedule", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      schedule = schedule_fixture(org_id, mission_id, procedure_id, enabled: false)

      {:ok, updated} = Schedules.enable_schedule(schedule)
      assert updated.enabled == true
    end

    test "disable_schedule/1 disables schedule", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      schedule = schedule_fixture(org_id, mission_id, procedure_id, enabled: true)

      {:ok, updated} = Schedules.disable_schedule(schedule)
      assert updated.enabled == false
    end

    test "record_run/2 updates run tracking", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      schedule = schedule_fixture(org_id, mission_id, procedure_id)
      assert schedule.run_count == 0
      assert schedule.last_run_at == nil

      {:ok, updated} = Schedules.record_run(schedule)

      assert updated.run_count == 1
      assert updated.last_run_at != nil
    end
  end

  describe "due schedules" do
    setup do
      org_id = Ecto.UUID.generate()
      mission_id = Ecto.UUID.generate()
      procedure_id = Ecto.UUID.generate()

      %{org_id: org_id, mission_id: mission_id, procedure_id: procedure_id}
    end

    test "get_due_once_schedules/0 returns due one-time schedules", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, schedule} =
        Schedules.create_schedule(%{
          name: "Past Schedule",
          organization_id: org_id,
          mission_id: mission_id,
          procedure_id: procedure_id,
          schedule_type: :once,
          scheduled_at: past
        })

      due = Schedules.get_due_once_schedules()
      assert length(due) == 1
      assert hd(due).id == schedule.id
    end

    test "get_due_once_schedules/0 excludes future schedules", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _schedule} =
        Schedules.create_schedule(%{
          name: "Future Schedule",
          organization_id: org_id,
          mission_id: mission_id,
          procedure_id: procedure_id,
          schedule_type: :once,
          scheduled_at: future
        })

      due = Schedules.get_due_once_schedules()
      assert due == []
    end

    test "get_due_once_schedules/0 excludes already run schedules", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, schedule} =
        Schedules.create_schedule(%{
          name: "Already Run",
          organization_id: org_id,
          mission_id: mission_id,
          procedure_id: procedure_id,
          schedule_type: :once,
          scheduled_at: past
        })

      # Mark as run
      {:ok, _} = Schedules.record_run(schedule)

      due = Schedules.get_due_once_schedules()
      assert due == []
    end
  end

  # Fixture helper
  defp schedule_fixture(org_id, mission_id, procedure_id, opts \\ []) do
    attrs = %{
      name: "Test Schedule #{System.unique_integer([:positive])}",
      organization_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id,
      schedule_type: Keyword.get(opts, :schedule_type, :cron),
      cron_expression: Keyword.get(opts, :cron_expression, "0 * * * *"),
      enabled: Keyword.get(opts, :enabled, true)
    }

    {:ok, schedule} = Schedules.create_schedule(attrs)
    schedule
  end
end
