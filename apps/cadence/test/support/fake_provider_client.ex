defmodule Cadence.TestSupport.FakeProviderClient do
  @moduledoc false

  @behaviour Cadence.Contacts.ProviderClient

  @impl true
  def search_opportunities(_profile, params, opts) do
    run_observer(opts, :on_search, params)

    resolve_response(opts, :search_response, fn ->
      {:ok, %{"data" => [Map.put(params, "id", "opportunity-alpha")]}}
    end)
  end

  @impl true
  def reserve_contact(_profile, attrs, opts) do
    run_observer(opts, :on_reserve, attrs)

    resolve_response(opts, :reserve_response, fn ->
      {:ok,
       %{
         "id" => "provider-reservation-alpha",
         "provider_contact_ref" => "provider-contact-alpha",
         "status" => "confirmed",
         "provider_status" => "scheduled",
         "starts_at" => attrs["starts_at"],
         "ends_at" => attrs["ends_at"],
         "provider_evidence" => attrs
       }}
    end)
  end

  @impl true
  def describe_contact(_profile, provider_contact_id, opts) do
    run_observer(opts, :on_describe, provider_contact_id)

    resolve_response(opts, :describe_response, fn ->
      now = DateTime.utc_now()

      {:ok,
       %{
         "id" => provider_contact_id,
         "provider_contact_ref" => provider_contact_id,
         "status" => "confirmed",
         "provider_status" => "scheduled",
         "starts_at" => DateTime.to_iso8601(now),
         "ends_at" => now |> DateTime.add(600) |> DateTime.to_iso8601(),
         "provider_evidence" => %{}
       }}
    end)
  end

  @impl true
  def cancel_contact(_profile, provider_contact_id, opts) do
    run_observer(opts, :on_cancel, provider_contact_id)

    resolve_response(opts, :cancel_response, fn ->
      now = DateTime.utc_now()

      {:ok,
       %{
         "id" => provider_contact_id,
         "provider_contact_ref" => provider_contact_id,
         "status" => "canceled",
         "provider_status" => "canceled",
         "starts_at" => DateTime.to_iso8601(now),
         "ends_at" => now |> DateTime.add(600) |> DateTime.to_iso8601(),
         "provider_evidence" => %{}
       }}
    end)
  end

  @impl true
  def find_contact_by_idempotency_key(_profile, idempotency_key, opts) do
    run_observer(opts, :on_recover, idempotency_key)
    resolve_response(opts, :recover_response, fn -> {:error, :provider_contact_not_found} end)
  end

  @impl true
  def events(_profile, cursor, opts) do
    resolve_response(opts, :events_response, fn ->
      {:ok, %{"data" => [], "next_cursor" => cursor}}
    end)
  end

  defp run_observer(opts, key, value) do
    case Keyword.get(opts, key) do
      fun when is_function(fun, 1) -> fun.(value)
      _other -> :ok
    end
  end

  defp resolve_response(opts, key, default) do
    case Keyword.get(opts, key) do
      fun when is_function(fun, 0) -> fun.()
      fun when is_function(fun, 1) -> fun.(opts)
      nil -> default.()
      response -> response
    end
  end
end
