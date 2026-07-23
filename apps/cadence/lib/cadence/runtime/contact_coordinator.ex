defmodule Cadence.Runtime.ContactCoordinator do
  @moduledoc """
  Mission-scoped coordinator for one realized contact runtime.
  """

  use GenServer

  alias Cadence.Contacts.DownlinkObservation
  alias Cadence.Runtime.ContactPathSpec
  alias Cadence.Runtime.DownlinkCombiner
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.PathCoordinator
  alias Cadence.Runtime.PathRuntime
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  @type state :: %{
          realized_contact: RealizedContactRuntimeSpec.t(),
          path_ids: [binary()],
          paths: %{required(binary()) => ContactPathSpec.t()}
        }

  def start_link(opts) when is_list(opts) do
    %RealizedContactRuntimeSpec{} = realized_contact = Keyword.fetch!(opts, :realized_contact)

    GenServer.start_link(
      __MODULE__,
      opts,
      name:
        MissionRuntime.realized_contact_coordinator_name(
          realized_contact.mission_id,
          realized_contact.realized_contact_id
        )
    )
  end

  @spec snapshot(pid()) :: {:ok, map()} | {:error, term()}
  def snapshot(contact_runtime) do
    GenServer.call(contact_runtime, :snapshot)
  end

  @spec path_snapshot(pid(), binary()) :: {:ok, map()} | {:error, term()}
  def path_snapshot(contact_runtime, path_id) when is_binary(path_id) do
    GenServer.call(contact_runtime, {:path_snapshot, path_id})
  end

  @spec handle_transport_event(pid(), binary(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_transport_event(contact_runtime, path_id, transport_binding_id, event, opts \\ [])
      when is_binary(path_id) and is_binary(transport_binding_id) and is_list(opts) do
    GenServer.call(
      contact_runtime,
      {:handle_transport_event, path_id, transport_binding_id, event, opts},
      Keyword.get(opts, :call_timeout, 5_000)
    )
  end

  @spec handle_control_input(pid(), binary(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_control_input(
        contact_runtime,
        path_id,
        transport_binding_id,
        control_input,
        opts \\ []
      )
      when is_binary(path_id) and is_binary(transport_binding_id) and is_list(opts) do
    GenServer.call(
      contact_runtime,
      {:handle_control_input, path_id, transport_binding_id, control_input, opts}
    )
  end

  @spec advance_time(pid(), DateTime.t()) :: :ok | {:error, term()}
  def advance_time(contact_runtime, %DateTime{} = target_time) do
    GenServer.call(contact_runtime, {:advance_time, target_time})
  end

  @impl true
  def init(opts) do
    %RealizedContactRuntimeSpec{} = realized_contact = Keyword.fetch!(opts, :realized_contact)

    with :ok <- validate_realized_contact(realized_contact),
         {:ok, path_ids} <- start_path_runtimes(realized_contact) do
      {:ok,
       %{
         realized_contact: realized_contact,
         path_ids: path_ids,
         paths: Map.new(realized_contact.paths, &{&1.path_id, &1})
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    with {:ok, path_snapshots} <- collect_path_snapshots(state.realized_contact, state.path_ids),
         {:ok, downlink_combiner} <- downlink_combiner_snapshot(state.realized_contact) do
      snapshot = %{
        realized_contact_id: state.realized_contact.realized_contact_id,
        mission_id: state.realized_contact.mission_id,
        source_endpoint_refs: state.realized_contact.source_endpoint_refs,
        contact_intents: Enum.map(state.realized_contact.contact_intents, &Atom.to_string/1),
        clock_mode: state.realized_contact.clock_mode,
        initial_time: state.realized_contact.initial_time,
        metadata: state.realized_contact.metadata,
        path_count: length(path_snapshots),
        paths: path_snapshots,
        downlink_combiner: downlink_combiner
      }

      {:reply, {:ok, snapshot}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:path_snapshot, path_id}, _from, state) do
    reply =
      with {:ok, path_runtime} <-
             path_runtime(
               state.realized_contact.mission_id,
               state.realized_contact.realized_contact_id,
               path_id
             ) do
        PathCoordinator.snapshot(path_runtime)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_transport_event, path_id, transport_binding_id, event, opts},
        _from,
        state
      ) do
    reply =
      with {:ok, path_runtime} <-
             path_runtime(
               state.realized_contact.mission_id,
               state.realized_contact.realized_contact_id,
               path_id
             ),
           {:ok, path_outputs} <-
             PathCoordinator.handle_transport_event(
               path_runtime,
               transport_binding_id,
               event,
               opts
             ),
           {:ok, combiner_outputs} <-
             maybe_handle_downlink_observation(state, path_id, event, opts) do
        {:ok, path_outputs ++ combiner_outputs}
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_control_input, path_id, transport_binding_id, control_input, opts},
        _from,
        state
      ) do
    reply =
      with {:ok, path_runtime} <-
             path_runtime(
               state.realized_contact.mission_id,
               state.realized_contact.realized_contact_id,
               path_id
             ) do
        PathCoordinator.handle_control_input(
          path_runtime,
          transport_binding_id,
          control_input,
          opts
        )
      end

    {:reply, reply, state}
  end

  def handle_call({:advance_time, %DateTime{} = target_time}, _from, state) do
    reply =
      Enum.reduce_while(state.path_ids, :ok, fn path_id, :ok ->
        with {:ok, path_runtime} <-
               path_runtime(
                 state.realized_contact.mission_id,
                 state.realized_contact.realized_contact_id,
                 path_id
               ),
             :ok <- PathCoordinator.advance_time(path_runtime, target_time) do
          {:cont, :ok}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    {:reply, reply, state}
  end

  defp start_path_runtimes(%RealizedContactRuntimeSpec{} = realized_contact) do
    Enum.reduce_while(realized_contact.paths, {:ok, []}, fn %ContactPathSpec{} = path,
                                                            {:ok, acc} ->
      child_spec =
        Supervisor.child_spec(
          {PathRuntime,
           mission_id: realized_contact.mission_id,
           realized_contact_id: realized_contact.realized_contact_id,
           path: path,
           clock_mode: realized_contact.clock_mode,
           initial_time: realized_contact.initial_time || DateTime.utc_now()},
          id: {:path_runtime, realized_contact.realized_contact_id, path.path_id}
        )

      case DynamicSupervisor.start_child(
             MissionRuntime.path_supervisor_name(
               realized_contact.mission_id,
               realized_contact.realized_contact_id
             ),
             child_spec
           ) do
        {:ok, _path_runtime} ->
          {:cont, {:ok, acc ++ [path.path_id]}}

        {:error, {:already_started, _path_runtime}} ->
          {:cont, {:ok, acc ++ [path.path_id]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp collect_path_snapshots(%RealizedContactRuntimeSpec{} = realized_contact, path_ids) do
    Enum.reduce_while(path_ids, {:ok, []}, fn path_id, {:ok, acc} ->
      with {:ok, path_runtime} <-
             path_runtime(
               realized_contact.mission_id,
               realized_contact.realized_contact_id,
               path_id
             ),
           {:ok, snapshot} <- PathCoordinator.snapshot(path_runtime) do
        {:cont, {:ok, acc ++ [snapshot]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp path_runtime(mission_id, realized_contact_id, path_id) do
    case Registry.lookup(
           Cadence.Runtime.Registry,
           {:path_coordinator, mission_id, realized_contact_id, path_id}
         ) do
      [{path_runtime, _value}] -> {:ok, path_runtime}
      [] -> {:error, {:path_runtime_not_running, path_id}}
    end
  end

  defp downlink_combiner_snapshot(%RealizedContactRuntimeSpec{} = realized_contact) do
    with {:ok, downlink_combiner} <-
           downlink_combiner(realized_contact.mission_id, realized_contact.realized_contact_id) do
      DownlinkCombiner.snapshot(downlink_combiner)
    end
  end

  defp downlink_combiner(mission_id, realized_contact_id) do
    case Registry.lookup(
           Cadence.Runtime.Registry,
           {:downlink_combiner, mission_id, realized_contact_id}
         ) do
      [{downlink_combiner, _value}] -> {:ok, downlink_combiner}
      [] -> {:error, :downlink_combiner_not_running}
    end
  end

  defp maybe_handle_downlink_observation(state, path_id, event, opts) do
    case Map.fetch(state.paths, path_id) do
      {:ok, %ContactPathSpec{direction: :downlink} = path} ->
        with {:ok, observation} <-
               DownlinkObservation.from_transport_event(
                 state.realized_contact.mission_id,
                 state.realized_contact.realized_contact_id,
                 path,
                 event,
                 opts
               ),
             {:ok, downlink_combiner} <-
               downlink_combiner(
                 state.realized_contact.mission_id,
                 state.realized_contact.realized_contact_id
               ) do
          DownlinkCombiner.handle_observation(downlink_combiner, observation)
        else
          {:error, :not_downlink_observation} -> {:ok, []}
          {:error, reason} -> {:error, reason}
        end

      _other ->
        {:ok, []}
    end
  end

  defp validate_realized_contact(%RealizedContactRuntimeSpec{paths: []}),
    do: {:error, :realized_contact_requires_at_least_one_path}

  defp validate_realized_contact(%RealizedContactRuntimeSpec{
         paths: paths,
         contact_intents: contact_intents
       }) do
    with :ok <- validate_unique_path_ids(paths),
         :ok <- validate_selected_path_presence(paths),
         :ok <- validate_contact_intents(paths, contact_intents),
         :ok <- validate_uplink_selection(paths),
         :ok <- validate_downlink_selection(paths) do
      validate_transport_binding_ids(paths)
    end
  end

  defp validate_unique_path_ids(paths) do
    path_ids = Enum.map(paths, & &1.path_id)

    if length(path_ids) == MapSet.size(MapSet.new(path_ids)) do
      :ok
    else
      {:error, :duplicate_realized_contact_path_id}
    end
  end

  defp validate_selected_path_presence(paths) do
    if Enum.any?(paths, &(&1.selection_role == :selected)) do
      :ok
    else
      {:error, :realized_contact_requires_selected_path}
    end
  end

  defp validate_contact_intents(paths, contact_intents) do
    with :ok <- validate_telemetry_downlink_intent(paths, contact_intents) do
      validate_command_window_intent(paths, contact_intents)
    end
  end

  defp validate_telemetry_downlink_intent(paths, contact_intents) do
    if :telemetry_downlink in contact_intents and not selected_direction?(paths, :downlink) do
      {:error, :realized_contact_requires_selected_downlink_path}
    else
      :ok
    end
  end

  defp validate_command_window_intent(paths, contact_intents) do
    if :command_window in contact_intents and not selected_direction?(paths, :uplink) do
      {:error, :realized_contact_requires_selected_uplink_path}
    else
      :ok
    end
  end

  defp selected_direction?(paths, direction) do
    Enum.any?(paths, &(&1.direction == direction and &1.selection_role == :selected))
  end

  defp validate_uplink_selection(paths) do
    selected_uplink_paths =
      Enum.filter(paths, fn path ->
        path.direction == :uplink and path.selection_role == :selected
      end)

    case length(selected_uplink_paths) do
      count when count <= 1 -> :ok
      _count -> {:error, :realized_contact_has_multiple_selected_uplink_paths}
    end
  end

  defp validate_downlink_selection(paths) do
    selected_downlink_paths =
      Enum.filter(paths, fn path ->
        path.direction == :downlink and path.selection_role == :selected
      end)

    case length(selected_downlink_paths) do
      count when count <= 1 -> :ok
      _count -> {:error, :realized_contact_has_multiple_selected_downlink_paths}
    end
  end

  defp validate_transport_binding_ids(paths) do
    paths
    |> Enum.reduce_while(:ok, fn path, :ok ->
      transport_binding_ids = Enum.map(path.transport_bindings, & &1.transport_binding_id)

      if length(transport_binding_ids) == MapSet.size(MapSet.new(transport_binding_ids)) do
        {:cont, :ok}
      else
        {:halt, {:error, {:duplicate_transport_binding_id, path.path_id}}}
      end
    end)
  end
end
