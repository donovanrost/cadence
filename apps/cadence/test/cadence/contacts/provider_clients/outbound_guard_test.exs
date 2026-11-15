defmodule Cadence.Contacts.ProviderClients.OutboundGuardTest do
  @moduledoc """
  Provider HTTP calls never reach the platform's own network (api-ops' security sweep, 11-15):
  resolved before connecting, sent to the checked address, reserved ranges refused unless the
  environment allows them, redirects off.
  """
  use ExUnit.Case, async: true

  alias Cadence.Contacts.ProviderClients.OutboundGuard

  defp resolver(map), do: fn host -> Map.fetch(map, host) |> wrap() end
  defp wrap({:ok, addresses}), do: {:ok, addresses}
  defp wrap(:error), do: {:error, :nxdomain}

  defp capture do
    fn opts ->
      send(self(), {:sent, opts})
      {:ok, %Req.Response{status: 200}}
    end
  end

  describe "reserved and private addresses are refused" do
    for {label, address} <- [
          {"loopback", {127, 0, 0, 1}},
          {"RFC1918 10/8", {10, 1, 2, 3}},
          {"RFC1918 172.16/12", {172, 20, 0, 1}},
          {"RFC1918 192.168/16", {192, 168, 1, 1}},
          {"link-local and cloud metadata", {169, 254, 169, 254}},
          {"carrier-grade NAT", {100, 100, 100, 200}},
          {"unspecified", {0, 0, 0, 0}},
          {"IPv6 loopback", {0, 0, 0, 0, 0, 0, 0, 1}},
          {"IPv6 unique local", {0xFD00, 0xEC2, 0, 0, 0, 0, 0, 0x254}},
          {"IPv6 link-local", {0xFE80, 0, 0, 0, 0, 0, 0, 1}},
          {"IPv4-mapped private", {0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 0x0001}}
        ] do
      test "#{label}" do
        assert {:error, {:outbound_address_denied, "provider.example"}} =
                 OutboundGuard.request([url: "https://provider.example/provider/v1/account"],
                   resolver: resolver(%{"provider.example" => [unquote(Macro.escape(address))]}),
                   allow: [],
                   send: capture()
                 )

        refute_received {:sent, _}
      end
    end

    test "a literal private address in the URL is refused without a lookup" do
      assert {:error, {:outbound_address_denied, "10.0.0.5"}} =
               OutboundGuard.request([url: "http://10.0.0.5:4101/provider/v1/account"],
                 allow: [],
                 send: capture()
               )

      refute_received {:sent, _}
    end

    test "a name with ANY reserved answer is refused (no picking the public one)" do
      assert {:error, {:outbound_address_denied, "mixed.example"}} =
               OutboundGuard.request([url: "https://mixed.example/x"],
                 resolver: resolver(%{"mixed.example" => [{93, 184, 216, 34}, {10, 0, 0, 1}]}),
                 allow: [],
                 send: capture()
               )
    end

    test "an unresolvable name isn't sent" do
      assert {:error, {:outbound_address_unresolved, "nowhere.example"}} =
               OutboundGuard.request([url: "https://nowhere.example/x"],
                 resolver: resolver(%{}),
                 send: capture()
               )

      refute_received {:sent, _}
    end
  end

  describe "an allowed address" do
    test "connects to the CHECKED address, keeps the name for Host/TLS, and follows no redirects" do
      assert {:ok, %Req.Response{status: 200}} =
               OutboundGuard.request(
                 [url: "https://provider.example:8443/provider/v1/account?x=1", method: :get],
                 resolver: resolver(%{"provider.example" => [{93, 184, 216, 34}]}),
                 allow: [],
                 send: capture()
               )

      assert_received {:sent, opts}
      assert opts[:url] == "https://93.184.216.34:8443/provider/v1/account?x=1"
      assert opts[:connect_options][:hostname] == "provider.example"
      assert opts[:redirect] == false
      assert opts[:method] == :get
    end

    test "an IPv6 address is bracketed in the URL" do
      OutboundGuard.request([url: "https://v6.example/x"],
        resolver: resolver(%{"v6.example" => [{0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111}]}),
        allow: [],
        send: capture()
      )

      assert_received {:sent, opts}
      assert opts[:url] == "https://[2606:4700::1111]/x"
    end

    test "an environment's explicit allowlist admits its range (dev's simulator on loopback)" do
      assert {:ok, _} =
               OutboundGuard.request([url: "http://127.0.0.1:4101/provider/v1/account"],
                 allow: ["127.0.0.1/32"],
                 send: capture()
               )

      assert_received {:sent, opts}
      assert opts[:url] == "http://127.0.0.1:4101/provider/v1/account"

      # The allowlist names a range; the rest of the reserved space stays refused.
      assert {:error, {:outbound_address_denied, _}} =
               OutboundGuard.request([url: "http://10.0.0.5/x"],
                 allow: ["127.0.0.1/32"],
                 send: capture()
               )
    end

    test "the configured allowlist is the default (test and dev allow loopback only)" do
      assert OutboundGuard.allowed?({127, 0, 0, 1}, ["127.0.0.1/32", "::1/128"])
      refute OutboundGuard.allowed?({169, 254, 169, 254}, ["127.0.0.1/32", "::1/128"])
      assert OutboundGuard.allowed?({10, 43, 7, 9}, ["10.43.0.0/16"])
      refute OutboundGuard.allowed?({10, 44, 0, 1}, ["10.43.0.0/16"])
    end
  end

  describe "over a real socket (loopback, allowed as on dev)" do
    # A one-request HTTP/1.1 server on a raw socket (this app has no Plug): it answers 200 with
    # the request's Host header, or a 302 toward cloud metadata for /redirect.
    setup do
      {:ok, listen} =
        :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listen)
      server = spawn_link(fn -> serve(listen) end)
      :ok = :gen_tcp.controlling_process(listen, server)
      on_exit(fn -> :gen_tcp.close(listen) end)
      %{port: port}
    end

    test "the request reaches the checked address and still names the host", c do
      assert {:ok, %Req.Response{status: 200, body: host}} =
               OutboundGuard.request(
                 [url: "http://localhost:#{c.port}/provider/v1/account", retry: false],
                 resolver: fn "localhost" -> {:ok, [{127, 0, 0, 1}]} end,
                 allow: ["127.0.0.1/32"]
               )

      assert host == "localhost:#{c.port}"
    end

    test "a redirect is answered, never followed (here, toward cloud metadata)", c do
      assert {:ok, %Req.Response{status: 302}} =
               OutboundGuard.request([url: "http://127.0.0.1:#{c.port}/redirect", retry: false],
                 allow: ["127.0.0.1/32"]
               )
    end
  end

  defp serve(listen) do
    {:ok, socket} = :gen_tcp.accept(listen)
    {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
    [request_line | headers] = String.split(request, "\r\n")

    host = Enum.find_value(headers, "", &host_header/1)

    response =
      if String.contains?(request_line, "/redirect"),
        do:
          "HTTP/1.1 302 Found\r\nlocation: http://169.254.169.254/latest/meta-data/\r\n" <>
            "content-length: 0\r\nconnection: close\r\n\r\n",
        else:
          "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ncontent-length: #{byte_size(host)}" <>
            "\r\nconnection: close\r\n\r\n" <> host

    :ok = :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp host_header(line) do
    case String.split(line, ":", parts: 2) do
      [name, value] -> if String.downcase(name) == "host", do: String.trim(value)
      _other -> nil
    end
  end
end
