defmodule Cadence.TestSupport.FakeProviderClient do
  @moduledoc false

  @behaviour Cadence.Contacts.ProviderClient

  @impl true
  def search_opportunities(_profile, params, _opts) do
    {:ok, %{"data" => [Map.put(params, "id", "opportunity-alpha")]}}
  end

  @impl true
  def reserve_contact(_profile, attrs, _opts) do
    {:ok,
     attrs
     |> Map.put("id", "provider-reservation-alpha")
     |> Map.put("provider_contact_ref", "provider-contact-alpha")}
  end

  @impl true
  def describe_contact(_profile, provider_contact_id, _opts),
    do: {:ok, %{"id" => provider_contact_id, "status" => "scheduled"}}

  @impl true
  def cancel_contact(_profile, provider_contact_id, _opts),
    do: {:ok, %{"id" => provider_contact_id, "status" => "canceled"}}

  @impl true
  def events(_profile, cursor, _opts), do: {:ok, %{"data" => [], "next_cursor" => cursor}}
end
