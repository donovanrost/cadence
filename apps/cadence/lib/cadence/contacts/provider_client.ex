defmodule Cadence.Contacts.ProviderClient do
  @moduledoc """
  Control-plane boundary for external ground-station scheduling providers.

  This is deliberately separate from `Cadence.ProviderAdapters.Adapter`, which
  owns path-local byte I/O only after a contact has been realized.
  """

  alias Cadence.Contacts.ProviderProfile

  @callback search_opportunities(ProviderProfile.t(), map(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback reserve_contact(ProviderProfile.t(), map(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback describe_contact(ProviderProfile.t(), binary(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback cancel_contact(ProviderProfile.t(), binary(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback events(ProviderProfile.t(), non_neg_integer(), keyword()) ::
              {:ok, map()} | {:error, term()}
end
