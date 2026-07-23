defmodule Cadence.Runtime.Contacts do
  @moduledoc "Public data-plane command and observation boundary for realized Contacts."

  alias Cadence.Runtime
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  @spec start(RealizedContactRuntimeSpec.t()) :: {:ok, pid()} | {:error, term()}
  def start(%RealizedContactRuntimeSpec{} = spec), do: Runtime.start_realized_contact(spec)

  @spec stop(binary(), binary()) :: :ok | {:error, term()}
  def stop(mission_id, realized_contact_id),
    do: Runtime.stop_realized_contact(mission_id, realized_contact_id)

  @spec stop_sync(binary(), binary()) :: :ok | {:error, term()}
  def stop_sync(mission_id, realized_contact_id),
    do: Runtime.stop_realized_contact_sync(mission_id, realized_contact_id)

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
