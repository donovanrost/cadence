defmodule Cadence.Control.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      [
        {Registry, keys: :unique, name: Cadence.Control.Registry},
        {DynamicSupervisor, strategy: :one_for_one, name: Cadence.Control.MissionSupervisor},
        Cadence.Control.MissionRecovery,
        Cadence.Control.ContactFactConsumer,
        Cadence.Control.RuntimeFactConsumer
      ] ++
        command_dispatcher_children() ++
        command_verifier_scheduler_children() ++
        contact_scheduler_global_safety_children() ++
        provider_reservation_reconciler_children() ++
        provider_event_ingestion_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp contact_scheduler_global_safety_children do
    config = Application.get_env(:cadence, :contact_scheduler_global_safety, [])

    if Keyword.get(config, :enabled, false) do
      [{Cadence.Contacts.Scheduler, config}]
    else
      []
    end
  end

  defp provider_reservation_reconciler_children do
    config = Application.get_env(:cadence, :provider_reservation_reconciler, [])

    if Keyword.get(config, :enabled, true) do
      [{Cadence.Contacts.ProviderReservationReconciler, Keyword.delete(config, :enabled)}]
    else
      []
    end
  end

  defp provider_event_ingestion_children do
    config = Application.get_env(:cadence, :provider_event_ingestion, [])

    if Keyword.get(config, :enabled, true) do
      [
        {Cadence.GroundNetworks.ProviderEventIngestionSupervisor,
         Keyword.delete(config, :enabled)}
      ]
    else
      []
    end
  end

  defp command_dispatcher_children do
    config = Application.get_env(:cadence, :command_dispatcher, [])

    if Keyword.get(config, :enabled, true) do
      [{Cadence.Commanding.DispatchSupervisor, config}]
    else
      []
    end
  end

  defp command_verifier_scheduler_children do
    config = Application.get_env(:cadence, :command_verifier_scheduler, [])

    if Keyword.get(config, :enabled, true) do
      [{Cadence.Commanding.VerifierScheduler, config}]
    else
      []
    end
  end
end
