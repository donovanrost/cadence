defmodule Cadence.Contacts.ProviderClients.SimulatorHTTPTest do
  use ExUnit.Case, async: true

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.Contacts.ProviderProfile

  test "search sends provider run scope and bearer authentication" do
    profile = profile()

    req_request = fn opts ->
      send(self(), {:request, opts})
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"data" => []}}}}
    end

    assert {:ok, %{"data" => []}} =
             SimulatorHTTP.search_opportunities(
               profile,
               %{"starts_at" => "2026-07-12T00:00:00Z", "ends_at" => "2026-07-12T01:00:00Z"},
               req_request: req_request
             )

    assert_received {:request, opts}
    assert opts[:method] == :post
    assert opts[:url] == "http://simulator.test/v1/contact-opportunities/search"
    assert opts[:json]["run_id"] == "run-alpha"
    assert {"authorization", "Bearer secret"} in opts[:headers]
  end

  test "reservation sends an idempotency key and returns structured provider errors" do
    profile = profile()
    reservation = provider_reservation("scheduled")

    success = fn opts ->
      send(self(), {:request, opts})
      {:ok, %Req.Response{status: 201, body: %{"data" => reservation}}}
    end

    assert {:ok,
            %{
              "id" => "reservation-alpha",
              "provider_contact_ref" => "provider-contact-alpha",
              "status" => "confirmed",
              "provider_status" => "scheduled"
            }} =
             SimulatorHTTP.reserve_contact(profile, %{"spacecraft_id" => "SC-001"},
               idempotency_key: "cadence-alpha",
               req_request: success
             )

    assert_received {:request, opts}
    assert {"idempotency-key", "cadence-alpha"} in opts[:headers]

    assert opts[:json]["data_plane"] == %{
             "host" => "cadence.test",
             "port" => 4100
           }

    failure = fn _opts ->
      {:ok,
       %Req.Response{
         status: 409,
         body: %{"error" => %{"code" => "conflict", "detail" => "antenna unavailable"}}
       }}
    end

    assert {:error,
            {:provider_rejected, 409,
             %{
               "error" => %{"code" => "conflict", "detail" => "antenna unavailable"}
             }}} =
             SimulatorHTTP.cancel_contact(profile, "reservation-alpha", req_request: failure)
  end

  test "normalizes provider lifecycle states and validates required evidence" do
    expected = %{
      "pending" => "pending",
      "scheduled" => "confirmed",
      "acquiring" => "confirmed",
      "active" => "active",
      "completed" => "completed",
      "rejected" => "rejected",
      "canceled" => "canceled",
      "failed" => "failed",
      "terminated_early" => "failed"
    }

    Enum.each(expected, fn {provider_status, canonical_status} ->
      assert {:ok, %{"status" => ^canonical_status, "provider_status" => ^provider_status}} =
               SimulatorHTTP.normalize_reservation(provider_reservation(provider_status))
    end)

    assert {:error, {:unsupported_provider_status, "invented"}} =
             SimulatorHTTP.normalize_reservation(provider_reservation("invented"))

    assert {:error, {:malformed_provider_response, :ends_at}} =
             SimulatorHTTP.normalize_reservation(
               Map.put(provider_reservation("scheduled"), "ends_at", "invalid")
             )
  end

  test "classifies rate limits, unavailable endpoints, and ambiguous request failures" do
    rate_limited = fn _opts ->
      {:ok, %Req.Response{status: 429, body: %{"error" => %{"code" => "rate_limited"}}}}
    end

    assert {:error, {:provider_rejected, 429, _evidence}} =
             SimulatorHTTP.describe_contact(profile(), "reservation-alpha",
               req_request: rate_limited
             )

    unavailable = fn _opts -> {:error, %Req.TransportError{reason: :econnrefused}} end

    assert {:error, {:provider_unavailable, _reason}} =
             SimulatorHTTP.describe_contact(profile(), "reservation-alpha",
               req_request: unavailable
             )

    uncertain = fn _opts -> {:error, %Req.TransportError{reason: :timeout}} end

    assert {:error, {:provider_request_uncertain, _reason}} =
             SimulatorHTTP.describe_contact(profile(), "reservation-alpha",
               req_request: uncertain
             )
  end

  test "recovers a reservation by idempotency key" do
    req_request = fn opts ->
      send(self(), {:request, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"data" => [provider_reservation("scheduled")]}
       }}
    end

    assert {:ok, %{"id" => "reservation-alpha", "status" => "confirmed"}} =
             SimulatorHTTP.find_contact_by_idempotency_key(
               profile(),
               "cadence-alpha",
               req_request: req_request
             )

    assert_received {:request, opts}
    assert opts[:params] == %{"idempotency_key" => "cadence-alpha"}
  end

  test "event polling preserves the provider cursor envelope" do
    req_request = fn opts ->
      send(self(), {:request, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"data" => [%{"id" => "event-2"}], "next_cursor" => 2}
       }}
    end

    assert {:ok, %{"data" => [%{"id" => "event-2"}], "next_cursor" => 2}} =
             SimulatorHTTP.events(profile(), 1, req_request: req_request)

    assert_received {:request, opts}
    assert opts[:params] == %{cursor: 1}
  end

  defp profile do
    ProviderProfile.new(%{
      mission_id: "mission-alpha",
      adapter_key: :tcp_socket,
      configuration: %{
        "port" => 4100,
        "scheduling" => %{
          "client" => "simulator_http",
          "base_url" => "http://simulator.test",
          "api_token" => "secret",
          "delivery_host" => "cadence.test",
          "run_id" => "run-alpha"
        }
      }
    })
  end

  defp provider_reservation(status) do
    %{
      "id" => "reservation-alpha",
      "provider_contact_ref" => "provider-contact-alpha",
      "status" => status,
      "starts_at" => "2026-07-12T00:00:00Z",
      "ends_at" => "2026-07-12T01:00:00Z"
    }
  end
end
