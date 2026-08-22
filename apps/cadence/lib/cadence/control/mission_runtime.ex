defmodule Cadence.Control.MissionRuntime do
  @moduledoc false

  use Supervisor

  alias Cadence.Control.ProcessNamespace
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace

  def start_link(mission_id) when is_binary(mission_id) do
    start_link([], mission_id)
  end

  def start_link(runtime_opts, mission_id) when is_list(runtime_opts) and is_binary(mission_id) do
    runtime_opts = normalize_contact_scheduler_options(runtime_opts)
    process_namespace = process_namespace(runtime_opts)

    Supervisor.start_link(__MODULE__, {mission_id, runtime_opts},
      name: runtime_name(process_namespace, mission_id)
    )
  end

  @impl true
  def init({mission_id, runtime_opts}) do
    runtime_opts = normalize_contact_scheduler_options(runtime_opts)
    process_namespace = process_namespace(runtime_opts)
    runtime_process_namespace = runtime_process_namespace(runtime_opts)

    children =
      [
        {Cadence.Control.MissionRuntimeReconciler,
         reconciler_opts(runtime_opts,
           mission_id: mission_id,
           process_namespace: process_namespace,
           runtime_process_namespace: runtime_process_namespace
         )},
        contact_scheduler_child(runtime_opts, process_namespace, mission_id)
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  def init(mission_id) when is_binary(mission_id), do: init({mission_id, []})

  @spec runtime_name(binary()) :: {:via, Registry, {module(), term()}}
  def runtime_name(mission_id), do: runtime_name(ProcessNamespace.default(), mission_id)

  @spec runtime_name(ProcessNamespace.t(), binary()) :: {:via, Registry, {atom(), term()}}
  def runtime_name(%ProcessNamespace{} = process_namespace, mission_id),
    do: ProcessNamespace.via(process_namespace, {:mission_control_runtime, mission_id})

  @spec contact_scheduler_name(binary()) :: {:via, Registry, {module(), term()}}
  def contact_scheduler_name(mission_id),
    do: contact_scheduler_name(ProcessNamespace.default(), mission_id)

  @spec contact_scheduler_name(ProcessNamespace.t(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def contact_scheduler_name(%ProcessNamespace{} = process_namespace, mission_id),
    do: ProcessNamespace.via(process_namespace, {:contact_scheduler, mission_id})

  @spec reconciler_name(binary()) :: {:via, Registry, {module(), term()}}
  def reconciler_name(mission_id), do: reconciler_name(ProcessNamespace.default(), mission_id)

  @spec reconciler_name(ProcessNamespace.t(), binary()) :: {:via, Registry, {atom(), term()}}
  def reconciler_name(%ProcessNamespace{} = process_namespace, mission_id) do
    ProcessNamespace.via(process_namespace, {:mission_runtime_reconciler, mission_id})
  end

  defp contact_scheduler_child(runtime_opts, process_namespace, mission_id) do
    if Keyword.fetch!(runtime_opts, :start_contact_scheduler?) do
      {Cadence.Contacts.Scheduler,
       runtime_opts
       |> Keyword.fetch!(:contact_scheduler_opts)
       |> Keyword.put(:mission_id, mission_id)
       |> Keyword.put(:process_namespace, process_namespace)
       |> Keyword.put(:name, contact_scheduler_name(process_namespace, mission_id))}
    end
  end

  defp normalize_contact_scheduler_options(runtime_opts) do
    case {
      Keyword.fetch(runtime_opts, :start_contact_scheduler?),
      Keyword.fetch(runtime_opts, :contact_scheduler_opts)
    } do
      {{:ok, _enabled?}, {:ok, _scheduler_opts}} ->
        runtime_opts

      _incomplete ->
        config = Application.get_env(:cadence, :contact_scheduler, [])

        runtime_opts
        |> Keyword.put_new(:start_contact_scheduler?, Keyword.get(config, :enabled, true))
        |> Keyword.put(
          :contact_scheduler_opts,
          Keyword.merge(config, Keyword.get(runtime_opts, :contact_scheduler_opts, []))
        )
    end
  end

  defp reconciler_opts(runtime_opts, required_opts) do
    runtime_opts
    |> Keyword.get(:reconciler_opts, [])
    |> Keyword.merge(required_opts)
  end

  defp process_namespace(runtime_opts) do
    Keyword.get_lazy(runtime_opts, :process_namespace, &ProcessNamespace.default/0)
  end

  defp runtime_process_namespace(runtime_opts) do
    Keyword.get_lazy(
      runtime_opts,
      :runtime_process_namespace,
      &RuntimeProcessNamespace.default/0
    )
  end
end
