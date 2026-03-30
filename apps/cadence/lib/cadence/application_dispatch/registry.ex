defmodule Cadence.ApplicationDispatch.Registry do
  @moduledoc """
  Compatibility wrapper around the first-party capability registry for dispatch.
  """

  alias Cadence.Capabilities.Registry, as: CapabilityRegistry

  @type t :: CapabilityRegistry.t()

  @spec default() :: t()
  defdelegate default(), to: CapabilityRegistry

  @spec fetch(t(), atom()) :: {:ok, module()} | :error
  defdelegate fetch(registry, handler_key), to: CapabilityRegistry
end
