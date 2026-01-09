defmodule Cadence.TestSupport do
  @moduledoc """
  Helpers for bootstrapping test runtime.
  """

  def start_full_app do
    case Application.ensure_all_started(:cadence) do
      {:ok, _} -> :ok
      {:error, {:already_started, _app}} -> :ok
      {:error, _} = error -> error
    end
  end

  def enable_in_memory_adapters do
    previous = %{
      alarm_repository: Application.get_env(:cadence, :alarm_repository),
      automation_execution_repository:
        Application.get_env(:cadence, :automation_execution_repository),
      automation_repository: Application.get_env(:cadence, :automation_repository),
      commands_repository: Application.get_env(:cadence, :commands_repository),
      dashboard_layout_repository: Application.get_env(:cadence, :dashboard_layout_repository),
      event_recorder: Application.get_env(:cadence, :event_recorder),
      execution_operations: Application.get_env(:cadence, :execution_operations),
      interface_repository: Application.get_env(:cadence, :interface_repository),
      membership_repository: Application.get_env(:cadence, :membership_repository),
      missions_repository: Application.get_env(:cadence, :missions_repository),
      notification_repository: Application.get_env(:cadence, :notification_repository),
      organization_repository: Application.get_env(:cadence, :organization_repository),
      procedure_repository: Application.get_env(:cadence, :procedure_repository),
      queue_repository: Application.get_env(:cadence, :queue_repository),
      schedule_repository: Application.get_env(:cadence, :schedule_repository),
      settings_repository: Application.get_env(:cadence, :settings_repository),
      target_interface_repository: Application.get_env(:cadence, :target_interface_repository),
      target_repository: Application.get_env(:cadence, :target_repository),
      token_repository: Application.get_env(:cadence, :token_repository),
      user_repository: Application.get_env(:cadence, :user_repository),
      email_sender: Application.get_env(:cadence, :email_sender),
      event_publisher: Application.get_env(:cadence, :event_publisher),
      password_hasher: Application.get_env(:cadence, :password_hasher)
    }

    start_if_needed(Cadence.Test.Adapters.InMemoryAlarmRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryAutomationExecutionRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryAutomationRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryCommandsRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryDashboardLayoutRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryEventRecorder)
    start_if_needed(Cadence.Test.Adapters.InMemoryInterfaceRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryMembershipRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryMissionsRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryNotificationRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryOrganizationRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryProcedureRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryQueueRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryScheduleRepository)
    start_if_needed(Cadence.Test.Adapters.InMemorySettingsRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryTargetInterfaceRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryTargetRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryTokenRepository)
    start_if_needed(Cadence.Test.Adapters.InMemoryUserRepository)
    start_if_needed(Cadence.Test.Adapters.FakeEmailSender)
    start_if_needed(Cadence.Test.Adapters.FakeEventPublisher)
    start_if_needed(Cadence.Test.Adapters.FakePasswordHasher)

    Application.put_env(
      :cadence,
      :alarm_repository,
      Cadence.Test.Adapters.InMemoryAlarmRepository
    )

    Application.put_env(
      :cadence,
      :automation_execution_repository,
      Cadence.Test.Adapters.InMemoryAutomationExecutionRepository
    )

    Application.put_env(
      :cadence,
      :automation_repository,
      Cadence.Test.Adapters.InMemoryAutomationRepository
    )

    Application.put_env(
      :cadence,
      :commands_repository,
      Cadence.Test.Adapters.InMemoryCommandsRepository
    )

    Application.put_env(
      :cadence,
      :dashboard_layout_repository,
      Cadence.Test.Adapters.InMemoryDashboardLayoutRepository
    )

    Application.put_env(:cadence, :event_recorder, Cadence.Test.Adapters.InMemoryEventRecorder)

    Application.put_env(
      :cadence,
      :execution_operations,
      Cadence.Test.Adapters.InMemoryProcedureRepository
    )

    Application.put_env(
      :cadence,
      :interface_repository,
      Cadence.Test.Adapters.InMemoryInterfaceRepository
    )

    Application.put_env(
      :cadence,
      :membership_repository,
      Cadence.Test.Adapters.InMemoryMembershipRepository
    )

    Application.put_env(
      :cadence,
      :missions_repository,
      Cadence.Test.Adapters.InMemoryMissionsRepository
    )

    Application.put_env(
      :cadence,
      :notification_repository,
      Cadence.Test.Adapters.InMemoryNotificationRepository
    )

    Application.put_env(
      :cadence,
      :organization_repository,
      Cadence.Test.Adapters.InMemoryOrganizationRepository
    )

    Application.put_env(
      :cadence,
      :procedure_repository,
      Cadence.Test.Adapters.InMemoryProcedureRepository
    )

    Application.put_env(
      :cadence,
      :queue_repository,
      Cadence.Test.Adapters.InMemoryQueueRepository
    )

    Application.put_env(
      :cadence,
      :schedule_repository,
      Cadence.Test.Adapters.InMemoryScheduleRepository
    )

    Application.put_env(
      :cadence,
      :settings_repository,
      Cadence.Test.Adapters.InMemorySettingsRepository
    )

    Application.put_env(
      :cadence,
      :target_interface_repository,
      Cadence.Test.Adapters.InMemoryTargetInterfaceRepository
    )

    Application.put_env(
      :cadence,
      :target_repository,
      Cadence.Test.Adapters.InMemoryTargetRepository
    )

    Application.put_env(
      :cadence,
      :token_repository,
      Cadence.Test.Adapters.InMemoryTokenRepository
    )

    Application.put_env(:cadence, :user_repository, Cadence.Test.Adapters.InMemoryUserRepository)
    Application.put_env(:cadence, :email_sender, Cadence.Test.Adapters.FakeEmailSender)
    Application.put_env(:cadence, :event_publisher, Cadence.Test.Adapters.FakeEventPublisher)
    Application.put_env(:cadence, :password_hasher, Cadence.Test.Adapters.FakePasswordHasher)

    fn ->
      stop_in_memory_adapters()
      restore_env(previous)
    end
  end

  def stop_in_memory_adapters do
    stop_if_needed(Cadence.Test.Adapters.InMemoryAlarmRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryAutomationExecutionRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryAutomationRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryCommandsRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryDashboardLayoutRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryEventRecorder)
    stop_if_needed(Cadence.Test.Adapters.InMemoryInterfaceRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryMembershipRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryMissionsRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryNotificationRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryOrganizationRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryProcedureRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryQueueRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryScheduleRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemorySettingsRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryTargetInterfaceRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryTargetRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryTokenRepository)
    stop_if_needed(Cadence.Test.Adapters.InMemoryUserRepository)
    stop_if_needed(Cadence.Test.Adapters.FakeEmailSender)
    stop_if_needed(Cadence.Test.Adapters.FakeEventPublisher)
    stop_if_needed(Cadence.Test.Adapters.FakePasswordHasher)

    :ok
  end

  defp start_if_needed(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        maybe_start_module(module)

      _ ->
        :ok
    end
  end

  defp maybe_start_module(module) do
    if function_exported?(module, :start_link, 0) do
      handle_start_result(module.start_link())
    else
      :ok
    end
  end

  defp handle_start_result({:ok, _pid}), do: :ok
  defp handle_start_result({:error, {:already_started, _pid}}), do: :ok
  defp handle_start_result(_), do: :ok

  defp stop_if_needed(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        pid = Process.whereis(module)

        if is_pid(pid) and function_exported?(module, :stop, 0) do
          try do
            module.stop()
          catch
            :exit, _ -> :ok
          end
        end

        :ok

      _ ->
        :ok
    end
  end

  defp restore_env(previous) do
    Enum.each(previous, fn {key, value} ->
      if is_nil(value) do
        Application.delete_env(:cadence, key)
      else
        Application.put_env(:cadence, key, value)
      end
    end)
  end
end
