defmodule Cadence.Comms.TransportKind do
  @moduledoc """
  Behaviour for transport-kind specific configuration.
  """

  alias Cadence.Comms.Transport
  alias Cadence.Contacts.ProviderProfile

  @callback normalize_config(map()) :: {:ok, map()} | {:error, term()}
  @callback validate_config(map()) :: :ok | {:error, term()}
  @callback display_summary(map()) :: map()
  @callback materialize_provider_profile(Transport.t()) ::
              {:ok, ProviderProfile.t()} | {:error, term()}
end
