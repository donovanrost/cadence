defmodule Cadence.SchedulesTest do
  use Cadence.DataCase, async: true

  alias Cadence.Schedules
  alias Cadence.Schedules.Schedule

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.ProceduresFixtures

  describe "schedules" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = procedure_fixture(organization: org, mission: mission)

      %{org: org, mission: mission, procedure: procedure}
    end

    test "list_schedules/2 returns schedules for organization", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      schedule = schedule_fixture(org, mission, procedure)

      schedules = Schedules.list_schedules(org.id)
      assert length(schedules) == 1
      assert hd(schedules).id == schedule.id
    end

    test "list_schedules/2 filters by mission", %{org: org, procedure: procedure} do
      mission1 = mission_fixture(organization: org)
      mission2 = mission_fixture(organization: org)
      proc1 = procedure_fixture(organization: org, mission: mission1)
      proc2 = procedure_fixture(organization: org, mission: mission2)

      sched1 = schedule_fixture(org, mission1, proc1)
      _sched2 = schedule_fixture(org, mission2, proc2)

      schedules = Schedules.list_schedules(org.id, mission_id: mission1.id)
      assert length(schedules) == 1
      assert hd(schedules).id == sched1.id
    end

    test "list_schedules/2 filters enabled only", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      _enabled = schedule_fixture(org, mission, procedure, enabled: true)
      _disabled = schedule_fixture(org, mission, procedure, enabled: false)

      enabled_only = Schedules.list_schedules(org.id, enabled_only: true)
      assert length(enabled_only) == 1
    end

    test "create_schedule/1 creates cron schedule", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      {:ok, schedule} =
        Schedules.create_schedule(%{
          name: "Daily Check",
          organization_id: org.id,
          mission_id: mission.id,
          procedure_id: procedure.id,
          schedule_type: :cron,
          cron_expression: "0 8 * * *"
        })

      assert schedule.name == "Daily Check"
      assert schedule.schedule_type == :cron
      assert schedule.cron_expression == "0 8 * * *"
      assert schedule.enabled == true
    end

    test "create_schedule/1 creates one-time schedule", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      scheduled_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, schedule} =
        Schedules.create_schedule(%{
          name: "One-time Task",
          organization_id: org.id,
          mission_id: mission.id,
          procedure_id: procedure.id,
          schedule_type: :once,
          scheduled_at: scheduled_time
        })

      assert schedule.schedule_type == :once
      assert schedule.scheduled_at == DateTime.truncate(scheduled_time, :second)
    end

    test "create_schedule/1 validates cron expression required for cron type", %{
      org: org,
      procedure: procedure
    } do
      {:error, changeset} =
        Schedules.create_schedule(%{
          name: "Bad Schedule",
          organization_id: org.id,
          procedure_id: procedure.id,
          schedule_type: :cron
        })

      assert errors_on(changeset).cron_expression != nil
    end

    test "create_schedule/1 validates scheduled_at required for once type", %{
      org: org,
      procedure: procedure
    } do
      {:error, changeset} =
        Schedules.create_schedule(%{
          name: "Bad Schedule",
          organization_id: org.id,
          procedure_id: procedure.id,
          schedule_type: :once
        })

      assert errors_on(changeset).scheduled_at != nil
    end

    test "create_schedule/1 validates cron expression syntax", %{org: org, procedure: procedure} do
      {:error, changeset} =
        Schedules.create_schedule(%{
          name: "Bad Cron",
          organization_id: org.id,
          procedure_id: procedure.id,
          schedule_type: :cron,
          cron_expression: "not a cron"
        })

      assert errors_on(changeset).cron_expression != nil
    end

    test "update_schedule/2 updates schedule", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      schedule = schedule_fixture(org, mission, procedure)

      {:ok, updated} = Schedules.update_schedule(schedule, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "delete_schedule/1 deletes schedule", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      schedule = schedule_fixture(org, mission, procedure)

      {:ok, _} = Schedules.delete_schedule(schedule)
      assert Schedules.get_schedule(schedule.id) == nil
    end

    test "enable_schedule/1 enables schedule", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      schedule = schedule_fixture(org, mission, procedure, enabled: false)

      {:ok, updated} = Schedules.enable_schedule(schedule)
      assert updated.enabled == true
    end

    test "disable_schedule/1 disables schedule", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      schedule = schedule_fixture(org, mission, procedure, enabled: true)

      {:ok, updated} = Schedules.disable_schedule(schedule)
      assert updated.enabled == false
    end

    test "record_run/2 updates run tracking", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      schedule = schedule_fixture(org, mission, procedure)
      assert schedule.run_count == 0
      assert schedule.last_run_at == nil

      {:ok, updated} = Schedules.record_run(schedule)

      assert updated.run_count == 1
      assert updated.last_run_at != nil
    end
  end

  describe "due schedules" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = procedure_fixture(organization: org, mission: mission)

      %{org: org, mission: mission, procedure: procedure}
    end

    test "get_due_once_schedules/0 returns due one-time schedules", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, schedule} =
        Schedules.create_schedule(%{
          name: "Past Schedule",
          organization_id: org.id,
          mission_id: mission.id,
          procedure_id: procedure.id,
          schedule_type: :once,
          scheduled_at: past
        })

      due = Schedules.get_due_once_schedules()
      assert length(due) == 1
      assert hd(due).id == schedule.id
    end

    test "get_due_once_schedules/0 excludes future schedules", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _schedule} =
        Schedules.create_schedule(%{
          name: "Future Schedule",
          organization_id: org.id,
          mission_id: mission.id,
          procedure_id: procedure.id,
          schedule_type: :once,
          scheduled_at: future
        })

      due = Schedules.get_due_once_schedules()
      assert due == []
    end

    test "get_due_once_schedules/0 excludes already run schedules", %{
      org: org,
      mission: mission,
      procedure: procedure
    } do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, schedule} =
        Schedules.create_schedule(%{
          name: "Already Run",
          organization_id: org.id,
          mission_id: mission.id,
          procedure_id: procedure.id,
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
  defp schedule_fixture(org, mission, procedure, opts \\ []) do
    attrs = %{
      name: "Test Schedule #{System.unique_integer([:positive])}",
      organization_id: org.id,
      mission_id: mission.id,
      procedure_id: procedure.id,
      schedule_type: Keyword.get(opts, :schedule_type, :cron),
      cron_expression: Keyword.get(opts, :cron_expression, "0 * * * *"),
      enabled: Keyword.get(opts, :enabled, true)
    }

    {:ok, schedule} = Schedules.create_schedule(attrs)
    schedule
  end
end
