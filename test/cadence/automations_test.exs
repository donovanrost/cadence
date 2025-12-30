defmodule Cadence.AutomationsTest do
  use Cadence.PureCase, async: false

  alias Cadence.Automations

  alias Cadence.Test.Adapters.FakeEventPublisher
  alias Cadence.Test.Adapters.InMemoryAutomationExecutionRepository
  alias Cadence.Test.Adapters.InMemoryAutomationRepository

  describe "automations" do
    setup do
      {:ok, _} = InMemoryAutomationRepository.start_link()
      {:ok, _} = InMemoryAutomationExecutionRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :automation_repository, InMemoryAutomationRepository)

      Application.put_env(
        :cadence,
        :automation_execution_repository,
        InMemoryAutomationExecutionRepository
      )

      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      org_id = Ecto.UUID.generate()
      mission_id = Ecto.UUID.generate()
      procedure_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :automation_repository)
        Application.delete_env(:cadence, :automation_execution_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryAutomationExecutionRepository.stop()
        InMemoryAutomationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{org_id: org_id, mission_id: mission_id, procedure_id: procedure_id}
    end

    test "list_automations/2 returns automations for organization", %{
      org_id: org_id,
      mission_id: mission_id
    } do
      automation = automation_fixture(organization_id: org_id, mission_id: mission_id)

      automations = Automations.list_automations(org_id)
      assert length(automations) == 1
      assert hd(automations).id == automation.id
    end

    test "list_automations/2 filters by mission", %{org_id: org_id, mission_id: mission_id} do
      mission2_id = Ecto.UUID.generate()
      auto1 = automation_fixture(organization_id: org_id, mission_id: mission_id)
      _auto2 = automation_fixture(organization_id: org_id, mission_id: mission2_id)

      automations = Automations.list_automations(org_id, mission_id: mission_id)
      assert length(automations) == 1
      assert hd(automations).id == auto1.id
    end

    test "list_automations/2 filters enabled only", %{org_id: org_id, mission_id: mission_id} do
      _enabled =
        automation_fixture(organization_id: org_id, mission_id: mission_id, enabled: true)

      _disabled =
        automation_fixture(organization_id: org_id, mission_id: mission_id, enabled: false)

      enabled_only = Automations.list_automations(org_id, enabled_only: true)
      assert length(enabled_only) == 1
    end

    test "create_automation/1 creates automation with valid attrs", %{
      org_id: org_id,
      mission_id: mission_id,
      procedure_id: procedure_id
    } do
      {:ok, automation} =
        Automations.create_automation(%{
          name: "Test Automation",
          organization_id: org_id,
          mission_id: mission_id,
          trigger_type: :alarm_fired,
          trigger_conditions: %{"severity_in" => ["critical"]},
          action_type: :execute_procedure,
          action_config: %{"procedure_id" => procedure_id}
        })

      assert automation.name == "Test Automation"
      assert automation.trigger_type == :alarm_fired
      assert automation.enabled == true
    end

    test "create_automation/1 validates required fields", %{org_id: org_id} do
      {:error, error} =
        Automations.create_automation(%{
          organization_id: org_id
        })

      # Domain entity returns error tuples like {:required, :field}
      assert error == {:required, :name}
    end

    test "create_automation/1 validates trigger_type", %{org_id: org_id} do
      {:error, error} =
        Automations.create_automation(%{
          name: "Test",
          organization_id: org_id,
          trigger_type: "invalid_type",
          action_type: :execute_procedure,
          action_config: %{"procedure_id" => Ecto.UUID.generate()}
        })

      assert error == {:invalid, :trigger_type}
    end

    test "create_automation/1 validates action_type", %{org_id: org_id} do
      {:error, error} =
        Automations.create_automation(%{
          name: "Test",
          organization_id: org_id,
          trigger_type: :alarm_fired,
          action_type: "invalid_action"
        })

      assert error == {:invalid, :action_type}
    end

    test "create_automation/1 validates execute_procedure requires procedure_id", %{
      org_id: org_id
    } do
      {:error, error} =
        Automations.create_automation(%{
          name: "Test",
          organization_id: org_id,
          trigger_type: :alarm_fired,
          action_type: :execute_procedure,
          action_config: %{}
        })

      assert error == {:missing_config, :procedure_id}
    end

    test "update_automation/2 updates automation", %{org_id: org_id, mission_id: mission_id} do
      automation = automation_fixture(organization_id: org_id, mission_id: mission_id)

      {:ok, updated} = Automations.update_automation(automation, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "delete_automation/1 deletes automation", %{org_id: org_id, mission_id: mission_id} do
      automation = automation_fixture(organization_id: org_id, mission_id: mission_id)

      {:ok, _} = Automations.delete_automation(automation)
      assert Automations.get_automation(automation.id, org_id) == nil
    end

    test "enable_automation/1 enables automation", %{org_id: org_id, mission_id: mission_id} do
      automation =
        automation_fixture(organization_id: org_id, mission_id: mission_id, enabled: false)

      {:ok, updated} = Automations.enable_automation(automation)
      assert updated.enabled == true
    end

    test "disable_automation/1 disables automation", %{org_id: org_id, mission_id: mission_id} do
      automation =
        automation_fixture(organization_id: org_id, mission_id: mission_id, enabled: true)

      {:ok, updated} = Automations.disable_automation(automation)
      assert updated.enabled == false
    end
  end

  describe "condition matching" do
    setup do
      {:ok, _} = InMemoryAutomationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :automation_repository, InMemoryAutomationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      org_id = Ecto.UUID.generate()
      mission_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :automation_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryAutomationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{org_id: org_id, mission_id: mission_id}
    end

    test "matches_conditions?/2 returns true when no conditions", %{
      org_id: org_id,
      mission_id: mission_id
    } do
      automation =
        automation_fixture(
          organization_id: org_id,
          mission_id: mission_id,
          trigger_conditions: %{}
        )

      event = %{severity: "critical", item_name: "TEMP_SENSOR"}

      assert Automations.matches_conditions?(automation, event)
    end

    test "matches_conditions?/2 matches severity_in", %{org_id: org_id, mission_id: mission_id} do
      automation =
        automation_fixture(
          organization_id: org_id,
          mission_id: mission_id,
          trigger_conditions: %{"severity_in" => ["critical", "warning"]}
        )

      assert Automations.matches_conditions?(automation, %{severity: "critical"})
      assert Automations.matches_conditions?(automation, %{severity: "warning"})
      refute Automations.matches_conditions?(automation, %{severity: "info"})
    end

    test "matches_conditions?/2 matches item_pattern", %{org_id: org_id, mission_id: mission_id} do
      automation =
        automation_fixture(
          organization_id: org_id,
          mission_id: mission_id,
          trigger_conditions: %{"item_pattern" => "TEMP_.*"}
        )

      assert Automations.matches_conditions?(automation, %{item_name: "TEMP_SENSOR"})
      assert Automations.matches_conditions?(automation, %{item_name: "TEMP_123"})
      refute Automations.matches_conditions?(automation, %{item_name: "PRESSURE_SENSOR"})
    end

    test "matches_conditions?/2 matches state_in for limit events", %{
      org_id: org_id,
      mission_id: mission_id
    } do
      automation =
        automation_fixture(
          organization_id: org_id,
          mission_id: mission_id,
          trigger_type: "telemetry_limit",
          trigger_conditions: %{"state_in" => ["red", "yellow"]}
        )

      assert Automations.matches_conditions?(automation, %{new_state: :red})
      assert Automations.matches_conditions?(automation, %{new_state: "yellow"})
      refute Automations.matches_conditions?(automation, %{new_state: :green})
    end

    test "matches_conditions?/2 requires all conditions to match", %{
      org_id: org_id,
      mission_id: mission_id
    } do
      automation =
        automation_fixture(
          organization_id: org_id,
          mission_id: mission_id,
          trigger_conditions: %{
            "severity_in" => ["critical"],
            "item_pattern" => "TEMP_.*"
          }
        )

      # Both match
      assert Automations.matches_conditions?(automation, %{
               severity: "critical",
               item_name: "TEMP_SENSOR"
             })

      # Only severity matches
      refute Automations.matches_conditions?(automation, %{
               severity: "critical",
               item_name: "PRESSURE"
             })

      # Only pattern matches
      refute Automations.matches_conditions?(automation, %{
               severity: "warning",
               item_name: "TEMP_SENSOR"
             })
    end
  end

  describe "rate limiting" do
    setup do
      {:ok, _} = InMemoryAutomationRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :automation_repository, InMemoryAutomationRepository)
      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      org_id = Ecto.UUID.generate()
      mission_id = Ecto.UUID.generate()

      on_exit(fn ->
        Application.delete_env(:cadence, :automation_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryAutomationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{org_id: org_id, mission_id: mission_id}
    end

    test "check_rate_limits/1 allows when no limits set", %{
      org_id: org_id,
      mission_id: mission_id
    } do
      automation = automation_fixture(organization_id: org_id, mission_id: mission_id)
      assert {:ok, :allowed} = Automations.check_rate_limits(automation)
    end

    test "check_rate_limits/1 returns cooldown error when in cooldown", %{
      org_id: org_id,
      mission_id: mission_id
    } do
      automation =
        automation_fixture(
          organization_id: org_id,
          mission_id: mission_id,
          cooldown_seconds: 60
        )

      # Simulate a recent trigger
      {:ok, triggered} = Automations.record_trigger(automation)

      assert {:error, :cooldown} = Automations.check_rate_limits(triggered)
    end

    test "check_rate_limits/1 allows when cooldown expired", %{
      org_id: org_id,
      mission_id: mission_id
    } do
      automation =
        automation_fixture(
          organization_id: org_id,
          mission_id: mission_id,
          cooldown_seconds: 60
        )

      # Simulate a trigger in the past (beyond cooldown)
      past = DateTime.add(DateTime.utc_now(), -120, :second)

      expired_automation =
        %{automation | last_triggered_at: past, trigger_count: 1}

      assert {:ok, :allowed} = Automations.check_rate_limits(expired_automation)
    end

    test "record_trigger/1 updates trigger tracking", %{org_id: org_id, mission_id: mission_id} do
      automation = automation_fixture(organization_id: org_id, mission_id: mission_id)
      assert automation.trigger_count == 0
      assert automation.last_triggered_at == nil

      {:ok, updated} = Automations.record_trigger(automation)

      assert updated.trigger_count == 1
      assert updated.last_triggered_at != nil
    end
  end

  describe "executions" do
    setup do
      {:ok, _} = InMemoryAutomationRepository.start_link()
      {:ok, _} = InMemoryAutomationExecutionRepository.start_link()
      {:ok, _} = FakeEventPublisher.start_link()
      Application.put_env(:cadence, :automation_repository, InMemoryAutomationRepository)

      Application.put_env(
        :cadence,
        :automation_execution_repository,
        InMemoryAutomationExecutionRepository
      )

      Application.put_env(:cadence, :event_publisher, FakeEventPublisher)

      org_id = Ecto.UUID.generate()
      mission_id = Ecto.UUID.generate()
      automation = automation_fixture(organization_id: org_id, mission_id: mission_id)

      on_exit(fn ->
        Application.delete_env(:cadence, :automation_repository)
        Application.delete_env(:cadence, :automation_execution_repository)
        Application.delete_env(:cadence, :event_publisher)
        InMemoryAutomationExecutionRepository.stop()
        InMemoryAutomationRepository.stop()
        FakeEventPublisher.stop()
      end)

      %{org_id: org_id, mission_id: mission_id, automation: automation}
    end

    test "create_execution/1 creates execution record", %{
      org_id: org_id,
      mission_id: mission_id,
      automation: automation
    } do
      {:ok, execution} =
        Automations.create_execution(%{
          automation_id: automation.id,
          organization_id: org_id,
          mission_id: mission_id,
          trigger_event: %{"type" => "alarm_fired", "severity" => "critical"}
        })

      assert execution.status == :pending
      assert execution.trigger_event["type"] == "alarm_fired"
    end

    test "update_execution_status/2 updates status", %{
      org_id: org_id,
      mission_id: mission_id,
      automation: automation
    } do
      {:ok, execution} =
        Automations.create_execution(%{
          automation_id: automation.id,
          organization_id: org_id,
          mission_id: mission_id,
          trigger_event: %{}
        })

      {:ok, updated} =
        Automations.update_execution_status(execution, %{
          status: :completed,
          completed_at: DateTime.utc_now(),
          action_result: %{"executed" => true}
        })

      assert updated.status == :completed
      assert updated.action_result["executed"] == true
    end

    test "list_executions/1 filters by automation", %{
      org_id: org_id,
      mission_id: mission_id,
      automation: automation
    } do
      {:ok, _} =
        Automations.create_execution(%{
          automation_id: automation.id,
          organization_id: org_id,
          mission_id: mission_id,
          trigger_event: %{}
        })

      executions = Automations.list_executions(automation_id: automation.id)
      assert length(executions) == 1
    end
  end

  # Fixture helper
  defp automation_fixture(opts) do
    org_id = Keyword.fetch!(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    procedure_id = Keyword.get(opts, :procedure_id, Ecto.UUID.generate())

    # Convert string trigger_type to atom if provided as string
    trigger_type = Keyword.get(opts, :trigger_type, :alarm_fired)

    trigger_type =
      if is_binary(trigger_type), do: String.to_atom(trigger_type), else: trigger_type

    action_type = Keyword.get(opts, :action_type, :execute_procedure)

    action_type =
      if is_binary(action_type), do: String.to_atom(action_type), else: action_type

    attrs =
      %{
        name: "Test Automation #{System.unique_integer([:positive])}",
        organization_id: org_id,
        mission_id: mission_id,
        trigger_type: trigger_type,
        trigger_conditions: Keyword.get(opts, :trigger_conditions, %{}),
        action_type: action_type,
        action_config: Keyword.get(opts, :action_config, %{"procedure_id" => procedure_id}),
        enabled: Keyword.get(opts, :enabled, true),
        cooldown_seconds: Keyword.get(opts, :cooldown_seconds, 0)
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    {:ok, automation} = Automations.create_automation(attrs)
    automation
  end
end
