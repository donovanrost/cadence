defmodule Cadence.Runtime.Contacts do
  @moduledoc "Public data-plane command and observation boundary for realized Contacts."

  alias Cadence.IngressJournal.FileSystem, as: JournalFileSystem
  alias Cadence.IngressJournal.Volume, as: JournalVolume
  alias Cadence.ProviderAdapters.TCPSocket
  alias Cadence.Runtime

  alias Cadence.Runtime.{
    Cluster,
    ContactBacklog,
    ProcessNamespace,
    ProfileAcceptor,
    RealizedContactRuntimeSpec
  }

  @spec start(RealizedContactRuntimeSpec.t()) :: {:ok, pid()} | {:error, term()}
  def start(%RealizedContactRuntimeSpec{} = spec), do: Runtime.start_realized_contact(spec)

  @spec stop(binary(), binary()) :: :ok | {:error, term()}
  def stop(mission_id, realized_contact_id),
    do: Runtime.stop_realized_contact(mission_id, realized_contact_id)

  @spec stop_sync(binary(), binary()) :: :ok | {:error, term()}
  def stop_sync(mission_id, realized_contact_id),
    do: Runtime.stop_realized_contact_sync(mission_id, realized_contact_id)

  @doc "Quiesces and waits however long the drain takes (DECISIONS #71: contact settlers only)."
  @spec quiesce(binary(), binary()) :: :ok | {:error, term()}
  def quiesce(mission_id, realized_contact_id),
    do: Runtime.quiesce_realized_contact(mission_id, realized_contact_id)

  @doc "Stops without quiescing; the ingress journal keeps what it hasn't stored (#71)."
  @spec terminate(binary(), binary()) :: :ok | {:error, term()}
  def terminate(mission_id, realized_contact_id),
    do: Runtime.terminate_realized_contact(mission_id, realized_contact_id)

  @doc "What the running contact hasn't stored yet: `%{journals, persistence_errors}` (#71)."
  @spec backlog(binary(), binary()) :: map()
  def backlog(mission_id, realized_contact_id),
    do: ContactBacklog.read(ProcessNamespace.default(), mission_id, realized_contact_id)

  @doc "What the contact's journal consumers gave up at the end (`ContactBacklog.incomplete_at_end/3`)."
  @spec incomplete_at_end(binary(), binary()) :: [map()]
  def incomplete_at_end(mission_id, realized_contact_id),
    do:
      ContactBacklog.incomplete_at_end(
        ProcessNamespace.default(),
        mission_id,
        realized_contact_id
      )

  @doc "Whether downlink ingress is journaled to disk (DECISIONS #71 holds only when it is)."
  @spec journal_enabled?() :: boolean()
  def journal_enabled?, do: JournalFileSystem.configured_policy().enabled?

  @doc "The mission's realized contacts with an ingress journal on disk (replay, #71)."
  @spec journaled_ids(binary()) :: MapSet.t(binary())
  def journaled_ids(mission_id) do
    policy = JournalFileSystem.configured_policy()

    case {policy.enabled?, Keyword.get(policy.file_system_opts, :base_path)} do
      {true, base_path} when is_binary(base_path) ->
        base_path
        |> JournalFileSystem.stored_streams()
        |> Enum.filter(&(&1.mission_id == mission_id))
        |> MapSet.new(& &1.realized_contact_id)

      _off ->
        MapSet.new()
    end
  end

  @doc """
  The disk the ingress journal lives on (ux U66): `{:ok, %{size_bytes, used_bytes, percent}}`,
  or `:unknown` when the journal is off or the disk can't be read (callers then don't act).
  """
  @spec journal_volume(keyword()) :: {:ok, map()} | :unknown
  def journal_volume(opts \\ []) do
    case journal_base_path() do
      nil -> :unknown
      base_path -> JournalVolume.usage(base_path, opts)
    end
  end

  @doc "Every stored journal stream on that disk, largest first, with its bytes (all missions)."
  @spec journal_volume_streams() :: [map()]
  def journal_volume_streams do
    case journal_base_path() do
      nil -> []
      base_path -> JournalVolume.streams(base_path)
    end
  end

  @doc "The mission's stored ingress journal streams on disk (reclaim, #71 follow-up)."
  @spec stored_journals(binary()) :: [map()]
  def stored_journals(mission_id) do
    case journal_base_path() do
      nil ->
        []

      base_path ->
        base_path
        |> JournalFileSystem.stored_stream_directories()
        |> Enum.filter(&(&1.context.mission_id == mission_id))
    end
  end

  @doc """
  The mission's shared-listener adapters (#87) and their refusal state (ux U50), from each profile
  acceptor's registrations, cluster-wide: `[%{realized_contact_id, path_id, provider_binding_id,
  connected?, refusals, second_connections_refused, shared_with}]`. `refusals` is the adapter's
  refusal window (nil until a refusal opens one); `shared_with` the other contacts registered on
  the same listener. Starts nothing; an adapter or acceptor that has gone is left out.
  """
  @spec listener_refusals(binary()) :: [map()]
  def listener_refusals(mission_id) do
    ProcessNamespace.default()
    |> Cluster.select([
      {{{:profile_acceptor, mission_id, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.flat_map(fn {profile_id, acceptor} -> acceptor_refusals(profile_id, acceptor) end)
  end

  @doc "`listener_refusals/1` for one contact (its settler reads it at LOS)."
  @spec listener_refusals(binary(), binary()) :: [map()]
  def listener_refusals(mission_id, realized_contact_id) do
    mission_id
    |> listener_refusals()
    |> Enum.filter(&(&1.realized_contact_id == realized_contact_id))
  end

  defp acceptor_refusals(profile_id, acceptor) do
    registrations = ProfileAcceptor.registrations(acceptor)
    contacts = registrations |> Enum.map(& &1.realized_contact_id) |> Enum.uniq()

    for registration <- registrations,
        {:ok, state} <- [adapter_refusals(registration.adapter)] do
      Map.merge(state, %{
        realized_contact_id: registration.realized_contact_id,
        path_id: registration.path_id,
        provider_binding_id: profile_id,
        shared_with: List.delete(contacts, registration.realized_contact_id)
      })
    end
  end

  defp adapter_refusals(adapter) do
    TCPSocket.refusals(adapter)
  catch
    :exit, _gone -> :error
  end

  @doc "Whether any ingress journal of the contact is open (a runtime or a replay writes it)."
  @spec journal_open?(binary(), binary()) :: boolean()
  # Cluster-wide (api-ops): a journal open on another node must keep its directory too.
  def journal_open?(mission_id, realized_contact_id) do
    key = {:provider_ingress_journal, mission_id, realized_contact_id, :_, :_}
    Cluster.select(ProcessNamespace.default(), [{{key, :_, :_}, [], [true]}]) != []
  end

  @spec stored_journal_drain(map()) ::
          {:drained, non_neg_integer()} | {:not_drained, term(), non_neg_integer()}
  def stored_journal_drain(%{directory: directory, stream_id: stream_id}),
    do: JournalFileSystem.stored_stream_drain(directory, stream_id)

  @spec reclaim_stored_journal(map()) :: :ok | {:error, term()}
  def reclaim_stored_journal(%{directory: directory}) do
    case journal_base_path() do
      nil -> {:error, :ingress_journal_disabled}
      base_path -> JournalFileSystem.reclaim_stored_stream(base_path, directory)
    end
  end

  defp journal_base_path do
    policy = JournalFileSystem.configured_policy()

    case {policy.enabled?, Keyword.get(policy.file_system_opts, :base_path)} do
      {true, base_path} when is_binary(base_path) -> base_path
      _off -> nil
    end
  end

  @spec running_ids(binary()) :: [binary()]
  def running_ids(mission_id), do: Runtime.running_realized_contact_ids(mission_id)

  @spec running?(binary(), binary()) :: boolean()
  def running?(mission_id, realized_contact_id),
    do: Runtime.realized_contact_running?(mission_id, realized_contact_id)

  @spec snapshot(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def snapshot(mission_id, realized_contact_id),
    do: Runtime.realized_contact_snapshot(mission_id, realized_contact_id)

  @spec path_snapshot(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def path_snapshot(mission_id, realized_contact_id, path_id),
    do: Runtime.path_runtime_snapshot(mission_id, realized_contact_id, path_id)
end
