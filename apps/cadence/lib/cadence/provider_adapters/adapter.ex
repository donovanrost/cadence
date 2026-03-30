defmodule Cadence.ProviderAdapters.Adapter do
  @moduledoc """
  ABI for one path-local provider adapter runtime.
  """

  alias Cadence.ActionRequests.ProviderRequest

  @callback child_spec(keyword()) :: Supervisor.child_spec()
  @callback snapshot(pid()) :: {:ok, map()} | {:error, term()}
  @callback deliver_uplink(pid(), ProviderRequest.t()) :: {:ok, map()} | {:error, term()}
end
