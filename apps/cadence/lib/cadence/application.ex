defmodule Cadence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Cadence.IngressArchive
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, RuntimeHealth}

  @impl true
  def start(_type, _args) do
    children =
      [
        Cadence.Repo,
        {Phoenix.PubSub, name: Cadence.PubSub},
        Cadence.Telemetry.Profiler,
        RuntimeHealth
      ] ++
        ingress_archive_children() ++
        protocol_record_archive_children() ++
        telemetry_backend_children() ++
        [Cadence.Runtime.Supervisor] ++
        command_dispatcher_children() ++
        command_verifier_scheduler_children() ++
        contact_scheduler_global_safety_children() ++ background_job_children()

    opts = [strategy: :one_for_one, name: Cadence.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        case Cadence.ensure_bootstrap_admin() do
          {:ok, _user} ->
            {:ok, pid}

          {:error, :bootstrap_admin_disabled} ->
            {:ok, pid}

          {:error, reason} ->
            Supervisor.stop(pid)
            {:error, reason}
        end

      other ->
        other
    end
  end

  defp contact_scheduler_global_safety_children do
    contact_scheduler_config = Application.get_env(:cadence, :contact_scheduler_global_safety, [])

    if Keyword.get(contact_scheduler_config, :enabled, false) do
      [{Cadence.Contacts.Scheduler, contact_scheduler_config}]
    else
      []
    end
  end

  defp command_dispatcher_children do
    command_dispatcher_config = Application.get_env(:cadence, :command_dispatcher, [])

    if Keyword.get(command_dispatcher_config, :enabled, true) do
      [{Cadence.Commanding.DispatchSupervisor, command_dispatcher_config}]
    else
      []
    end
  end

  defp command_verifier_scheduler_children do
    command_verifier_scheduler_config =
      Application.get_env(:cadence, :command_verifier_scheduler, [])

    if Keyword.get(command_verifier_scheduler_config, :enabled, true) do
      [{Cadence.Commanding.VerifierScheduler, command_verifier_scheduler_config}]
    else
      []
    end
  end

  defp background_job_children do
    if Application.get_env(:cadence, :start_background_jobs, true) do
      [{Cadence.Jobs.Supervisor, Application.get_env(:cadence, :background_jobs, [])}]
    else
      []
    end
  end

  defp telemetry_backend_children do
    [
      CurrentValueStore.child_spec(),
      HistoryStore.child_spec()
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp ingress_archive_children do
    [IngressArchive.child_spec()]
    |> Enum.reject(&is_nil/1)
  end

  defp protocol_record_archive_children do
    [RecordArchive.child_spec()]
    |> Enum.reject(&is_nil/1)
  end
end
