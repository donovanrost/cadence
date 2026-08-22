defmodule Cadence.GroundNetworks.ProviderCapabilities do
  @moduledoc "Validated provider capability document."

  alias Cadence.GroundNetworks.Validation

  @confirmation %{"immediate" => :immediate, "asynchronous" => :asynchronous}
  @idempotency %{"native" => :native, "client_reference" => :client_reference, "none" => :none}
  @recovery %{"client_reference" => :client_reference, "none" => :none}
  @event_semantics %{"at_least_once" => :at_least_once, "best_effort" => :best_effort}

  @type t :: %__MODULE__{
          contract_version: binary(),
          provider: map(),
          operations: map(),
          reservation: map(),
          events: map(),
          search: map(),
          delivery: map(),
          evidence: map()
        }

  defstruct [
    :contract_version,
    provider: %{},
    operations: %{},
    reservation: %{},
    events: %{},
    search: %{},
    delivery: %{},
    evidence: %{}
  ]

  @spec from_external(map()) :: {:ok, t()} | {:error, term()}
  def from_external(document) when is_map(document) do
    document = Validation.sanitize(document)

    with {:ok, contract_version} <- Validation.required_string(document, "contract_version"),
         {:ok, provider} <- Validation.object(document, "provider"),
         {:ok, operations} <- Validation.object(document, "operations"),
         {:ok, reservation} <- Validation.object(document, "reservation"),
         {:ok, events} <- Validation.object(document, "events"),
         {:ok, search} <- Validation.object(document, "search"),
         {:ok, delivery} <- Validation.object(document, "delivery"),
         {:ok, normalized_operations} <- normalize_operations(operations),
         {:ok, normalized_reservation} <- normalize_reservation(reservation),
         {:ok, normalized_events} <- normalize_events(events),
         {:ok, normalized_search} <- normalize_search(search),
         {:ok, normalized_delivery} <- normalize_delivery(delivery) do
      {:ok,
       %__MODULE__{
         contract_version: contract_version,
         provider: provider,
         operations: normalized_operations,
         reservation: normalized_reservation,
         events: normalized_events,
         search: normalized_search,
         delivery: normalized_delivery,
         evidence: document
       }}
    end
  end

  def from_external(_document), do: Validation.malformed(:capabilities)

  @spec supports?(t(), atom()) :: boolean()
  def supports?(%__MODULE__{} = capabilities, operation),
    do: Map.get(capabilities.operations, operation, false)

  defp normalize_operations(operations) do
    keys = [
      :opportunity_search,
      :contact_reservation,
      :contact_modification,
      :contact_cancellation,
      :inventory_discovery,
      :delivery_profile_provisioning
    ]

    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      wire_key = Atom.to_string(key)

      case Validation.boolean(operations, wire_key) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp normalize_reservation(reservation) do
    with {:ok, confirmation} <- Validation.member(reservation, "confirmation", @confirmation),
         {:ok, idempotency} <- Validation.member(reservation, "idempotency", @idempotency),
         {:ok, recovery} <- Validation.member(reservation, "recovery", @recovery) do
      {:ok, %{confirmation: confirmation, idempotency: idempotency, recovery: recovery}}
    end
  end

  defp normalize_events(events) do
    with {:ok, polling} <- Validation.boolean(events, "polling"),
         {:ok, webhooks} <- Validation.boolean(events, "webhooks"),
         {:ok, semantics} <-
           Validation.member(events, "delivery_semantics", @event_semantics) do
      {:ok, %{polling: polling, webhooks: webhooks, delivery_semantics: semantics}}
    end
  end

  defp normalize_search(search) do
    with {:ok, spacecraft_limit} <- Validation.positive_integer(search, "spacecraft_batch_limit"),
         {:ok, station_limit} <- Validation.positive_integer(search, "station_batch_limit"),
         {:ok, page_limit} <- Validation.positive_integer(search, "page_size_limit") do
      {:ok,
       %{
         spacecraft_batch_limit: spacecraft_limit,
         station_batch_limit: station_limit,
         page_size_limit: page_limit
       }}
    end
  end

  defp normalize_delivery(delivery) do
    with {:ok, kinds} <- Validation.string_list(delivery, "kinds"),
         {:ok, protocols} <- Validation.string_list(delivery, "protocols"),
         {:ok, directions} <- Validation.string_list(delivery, "directions") do
      {:ok, %{kinds: kinds, protocols: protocols, directions: directions}}
    end
  end
end
