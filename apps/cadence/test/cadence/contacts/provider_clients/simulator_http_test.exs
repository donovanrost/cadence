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

    success = fn opts ->
      send(self(), {:request, opts})
      {:ok, %Req.Response{status: 201, body: %{"data" => %{"id" => "reservation-alpha"}}}}
    end

    assert {:ok, %{"id" => "reservation-alpha"}} =
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

    assert {:error, {:provider_http_error, 409, %{"error" => %{"code" => "conflict"}}}} =
             SimulatorHTTP.cancel_contact(profile, "reservation-alpha", req_request: failure)
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
end
