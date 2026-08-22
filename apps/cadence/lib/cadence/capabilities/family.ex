defmodule Cadence.Capabilities.Family do
  @moduledoc """
  Behaviour implemented by registered first-party capability families.
  """

  alias Cadence.Capabilities.{Descriptor, ValidationContext}

  @callback descriptor() :: Descriptor.t()
  @callback validate_config(term(), ValidationContext.t()) :: :ok | {:error, term()}
  @callback build_instance(term(), term()) :: {:ok, term()} | {:error, term()}
end
