defmodule Cadence.Jobs.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Jobs.Dispatcher
  alias Cadence.Jobs.Runner

  @worker_supervisor_child_id Cadence.Jobs.WorkerSupervisor
  @dispatcher_child_id Dispatcher

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> Supervisor.start_link(__MODULE__, opts)
      name -> Supervisor.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec quiesce(Supervisor.supervisor()) :: {:ok, map()} | {:error, :noproc}
  def quiesce(supervisor \\ __MODULE__) do
    with pid when is_pid(pid) <- GenServer.whereis(supervisor),
         dispatcher when is_pid(dispatcher) <- dispatcher_pid(pid) do
      Dispatcher.quiesce(dispatcher)
    else
      _missing_process -> {:error, :noproc}
    end
  end

  @impl true
  def init(opts) do
    worker_supervisor_name =
      Keyword.get(opts, :worker_supervisor_name, Cadence.Jobs.WorkerSupervisor)

    worker_supervisor_opts =
      [strategy: :one_for_one]
      |> maybe_put_name(worker_supervisor_name)

    worker_supervisor =
      worker_supervisor_name || {:supervisor_child, self(), @worker_supervisor_child_id}

    dispatcher_opts =
      opts
      |> Keyword.take([:safety_poll_interval_ms, :max_concurrency])
      |> Keyword.put(:name, Keyword.get(opts, :dispatcher_name, Dispatcher.default_name()))
      |> Keyword.put(:worker_supervisor, worker_supervisor)
      |> Keyword.put(:runner, Keyword.get(opts, :runner, Runner.default()))

    children = [
      Supervisor.child_spec({DynamicSupervisor, worker_supervisor_opts},
        id: @worker_supervisor_child_id
      ),
      Supervisor.child_spec({Dispatcher, dispatcher_opts}, id: @dispatcher_child_id)
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp dispatcher_pid(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {@dispatcher_child_id, pid, :worker, _modules} when is_pid(pid) -> pid
      _child -> nil
    end)
  end

  defp maybe_put_name(opts, nil), do: opts
  defp maybe_put_name(opts, name), do: Keyword.put(opts, :name, name)
end
