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

  describe "IPv6 forms that embed, translate or route to reserved space" do
    for {label, address} <- [
          {"IPv4-compatible ::7f00:1", {0, 0, 0, 0, 0, 0, 0x7F00, 1}},
          {"site-local fec0::1", {0xFEC0, 0, 0, 0, 0, 0, 0, 1}},
          {"IPv4-translated ::ffff:0:a00:1", {0, 0, 0, 0, 0xFFFF, 0, 0x0A00, 1}},
          {"local-use NAT64 64:ff9b:1::1", {0x64, 0xFF9B, 1, 0, 0, 0, 0, 1}},
          {"well-known NAT64 of 10.0.0.1", {0x64, 0xFF9B, 0, 0, 0, 0, 0x0A00, 1}},
          {"6to4 2002:a00:1::1", {0x2002, 0x0A00, 1, 0, 0, 0, 0, 1}},
          {"Teredo 2001::1", {0x2001, 0, 0, 0, 0, 0, 0, 1}},
          {"IPv6 metadata fd00:ec2::254", {0xFD00, 0xEC2, 0, 0, 0, 0, 0, 0x254}}
        ] do
      test "#{label} is refused" do
        refute OutboundGuard.allowed?(unquote(Macro.escape(address)), [])
      end
    end

    test "a public IPv6 address is allowed" do
      assert OutboundGuard.allowed?({0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111}, [])
    end
  end

  describe "the allowlist is validated (never an off-switch)" do
    for cidr <- ["0.0.0.0/0", "::/0", "10.0.0.0/7", "2400::/16"] do
      test "#{cidr} is too wide" do
        assert_raise ArgumentError, ~r/wider than/, fn ->
          OutboundGuard.parse_allow!([unquote(cidr)])
        end
      end
    end

    for cidr <- ["169.254.169.254/32", "169.254.0.0/16", "fe80::/64", "fd00:ec2::254/128"] do
      test "#{cidr} can never be allowed" do
        assert_raise ArgumentError, ~r/link-local or metadata/, fn ->
          OutboundGuard.parse_allow!([unquote(cidr)])
        end
      end
    end

    for cidr <- ["10.0.0", "10.0.0.0/33", "not-an-address/8", "10.0.0.0/x"] do
      test "#{inspect(cidr)} is malformed" do
        assert_raise ArgumentError, fn -> OutboundGuard.parse_allow!([unquote(cidr)]) end
      end
    end

    test "IPv4 inside IPv6 is judged as that IPv4, whatever the allowlist" do
      allow = OutboundGuard.parse_allow!(["10.43.0.0/16", "2606:4700::/32"])
      refute OutboundGuard.allowed?({0, 0, 0, 0, 0, 0xFFFF, 0xA9FE, 0xA9FE}, allow)
      refute OutboundGuard.allowed?({0x64, 0xFF9B, 0, 0, 0, 0, 0xA9FE, 0xA9FE}, allow)
      # ...and an allowed IPv4 range admits its mapped form too.
      assert OutboundGuard.allowed?({0, 0, 0, 0, 0, 0xFFFF, 0x0A2B, 0x0709}, allow)
    end

    for cidr <- ["::ffff:0:0/96", "::ffff:a9fe:0/112", "64:ff9b::/96", "2002::/32", "::/96"] do
      test "#{cidr} (IPv4 carried in IPv6) can't be allowed" do
        assert_raise ArgumentError, fn -> OutboundGuard.parse_allow!([unquote(cidr)]) end
      end
    end

    test "even a hand-built allow entry can't re-allow metadata" do
      refute OutboundGuard.allowed?({169, 254, 169, 254}, [{{169, 254, 169, 254}, 32}])
    end

    test "IPv6 loopback ::1/128 is still allowable (dev's simulator)" do
      assert [{{0, 0, 0, 0, 0, 0, 0, 1}, 128}] = OutboundGuard.parse_allow!(["::1/128"])
    end

    test "the environment's configured list validates" do
      assert :ok = OutboundGuard.validate_config!()
    end
  end

  describe "the injectable transport sits behind the check" do
    test "a refused address never reaches :send" do
      send_fun = fn _opts -> flunk("sent a refused request") end

      assert {:error, {:outbound_address_denied, "10.0.0.5"}} =
               OutboundGuard.request([url: "http://10.0.0.5/x"], send: send_fun, allow: [])
    end

    test "an allowed request reaches :send already rewritten" do
      OutboundGuard.request([url: "https://provider.example/x"],
        resolver: resolver(%{"provider.example" => [{93, 184, 216, 34}]}),
        send: capture(),
        allow: []
      )

      assert_received {:sent, opts}
      assert opts[:url] == "https://93.184.216.34/x"
    end

    test "a non-HTTP URL is refused without naming it" do
      assert {:error, {:outbound_address_denied, :unsupported_url}} =
               OutboundGuard.request([url: "file:///etc/passwd"], send: capture(), allow: [])
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

    test "an allowlist admits exactly its ranges" do
      allow = OutboundGuard.parse_allow!(["127.0.0.1/32", "10.43.0.0/16"])
      assert OutboundGuard.allowed?({127, 0, 0, 1}, allow)
      assert OutboundGuard.allowed?({10, 43, 7, 9}, allow)
      refute OutboundGuard.allowed?({10, 44, 0, 1}, allow)
      refute OutboundGuard.allowed?({169, 254, 169, 254}, allow)
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

  describe "over TLS (api's review: Mint's :hostname drives SNI and verification, not the IP)" do
    test "a certificate for the provider's name verifies against the checked address" do
      %{port: port, cacerts: cacerts} = tls_server!("provider.test")

      assert {:ok, %Req.Response{status: 200}} =
               OutboundGuard.request(
                 [
                   url: "https://provider.test:#{port}/provider/v1/account",
                   retry: false,
                   connect_options: [transport_opts: [cacerts: cacerts]]
                 ],
                 resolver: fn "provider.test" -> {:ok, [{127, 0, 0, 1}]} end,
                 allow: ["127.0.0.1/32"]
               )
    end

    test "a certificate for another name fails, though the address is the same" do
      %{port: port, cacerts: cacerts} = tls_server!("other.test")

      assert {:error, %Req.TransportError{reason: reason}} =
               OutboundGuard.request(
                 [
                   url: "https://provider.test:#{port}/provider/v1/account",
                   retry: false,
                   connect_options: [transport_opts: [cacerts: cacerts]]
                 ],
                 resolver: fn "provider.test" -> {:ok, [{127, 0, 0, 1}]} end,
                 allow: ["127.0.0.1/32"]
               )

      # The client refused the certificate by name (not a cipher or protocol failure).
      assert inspect(reason) =~ "hostname_check_failed"
    end
  end

  # A one-request TLS server whose certificate names `dns_name`, from OTP's test PKI.
  defp tls_server!(dns_name) do
    san = {:Extension, {2, 5, 29, 17}, false, [dNSName: String.to_charlist(dns_name)]}

    %{server_config: server, client_config: client} =
      :public_key.pkix_test_data(%{
        server_chain: %{
          root: [key: {:rsa, 2048, 65_537}, digest: :sha256],
          intermediates: [],
          peer: [key: {:rsa, 2048, 65_537}, digest: :sha256, extensions: [san]]
        },
        client_chain: %{
          root: [key: {:rsa, 2048, 65_537}, digest: :sha256],
          intermediates: [],
          peer: [key: {:rsa, 2048, 65_537}, digest: :sha256]
        }
      })

    {:ok, listen} =
      :ssl.listen(0, server ++ [ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

    {:ok, {_ip, port}} = :ssl.sockname(listen)

    owner = self()

    server_pid =
      spawn(fn ->
        with {:ok, socket} <- :ssl.transport_accept(listen, 5_000),
             {:ok, tls} <- :ssl.handshake(socket, 5_000),
             {:ok, _request} <- :ssl.recv(tls, 0, 5_000) do
          :ssl.send(tls, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok")
          :ssl.close(tls)
        end

        send(owner, :tls_served)
      end)

    :ok = :ssl.controlling_process(listen, server_pid)
    on_exit(fn -> :ssl.close(listen) end)
    %{port: port, cacerts: Keyword.fetch!(client, :cacerts)}
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
