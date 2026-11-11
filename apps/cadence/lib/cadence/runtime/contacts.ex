defmodule Cadence.Runtime.Contacts do
  @moduledoc "Public data-plane command and observation boundary for realized Contacts."

  alias Cadence.Runtime
  alias Cadence.Runtime.{ContactBacklog, ProcessNamespace, RealizedContactRuntimeSpec}

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
