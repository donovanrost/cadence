defmodule Cadence.Contacts.ProviderClient do
  @moduledoc """
  Control-plane boundary for external ground-station scheduling providers.

  This is deliberately separate from `Cadence.ProviderAdapters.Adapter`, which
  owns path-local byte I/O only after a contact has been realized.

  The optional `events/3` callback is a provisional Stage 2 seam for adapters
  that support durable event cursors or webhooks. Stage 1 convergence uses
  `describe_contact/3` against durable reservation rows instead.
  """

  alias Cadence.Contacts.ProviderProfile

  @typedoc """
  Provider-neutral reservation shape returned by adapters.

  `status` is one of Cadence's canonical lifecycle strings. The adapter keeps
  its native value in `provider_status` and the bounded original payload in
  `provider_evidence`.
  """
  @type reservation_result :: %{required(binary()) => term()}

  @callback search_opportunities(ProviderProfile.t(), map(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback reserve_contact(ProviderProfile.t(), map(), keyword()) ::
              {:ok, reservation_result()} | {:error, term()}
  @callback describe_contact(ProviderProfile.t(), binary(), keyword()) ::
              {:ok, reservation_result()} | {:error, term()}
  @callback cancel_contact(ProviderProfile.t(), binary(), keyword()) ::
              {:ok, reservation_result()} | {:error, term()}
  @callback find_contact_by_idempotency_key(ProviderProfile.t(), binary(), keyword()) ::
              {:ok, reservation_result()} | {:error, term()}
  @callback events(ProviderProfile.t(), non_neg_integer(), keyword()) ::
              {:ok, map()} | {:error, term()}

  @optional_callbacks find_contact_by_idempotency_key: 3, events: 3
end
