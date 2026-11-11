defmodule Cadence.ProviderAdapters.Adapter do
  @moduledoc """
  ABI for one path-local provider adapter runtime.
  """

  alias Cadence.ActionRequests.ProviderRequest

  @callback child_spec(keyword()) :: Supervisor.child_spec()
  @callback uplink_session(pid()) :: {:ok, map()} | {:error, term()}
  @callback snapshot(pid()) :: {:ok, map()} | {:error, term()}
  @callback quiesce(pid()) :: {:ok, map()} | {:error, term()}
  @callback deliver_uplink(pid(), ProviderRequest.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Drops the connection to `peer` because qualification couldn't verify it, and keeps
  accepting (DECISIONS #67). `{:error, :peer_not_connected}` when `peer` isn't the current one.
  """
  @callback drop_unverified_peer(pid(), binary(), term()) :: :ok | {:error, term()}

  @optional_callbacks drop_unverified_peer: 3
end
