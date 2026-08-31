defmodule CadenceWeb.FrontendReleasePublisherWireTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag timeout: 120_000

  @path "/api/cadence/frontend-release/v1/releases"
  @token "frontend-release-publisher-test-token"
  @max_body_bytes 140_000_000

  setup do
    previous_publisher_config =
      Application.get_env(:cadence_web, :frontend_release_publisher)

    Application.put_env(
      :cadence_web,
      :frontend_release_publisher,
      token_sha256: :crypto.hash(:sha256, @token)
    )

    server =
      start_supervised!(
        {Bandit, plug: CadenceWeb.Endpoint, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    on_exit(fn ->
      restore_config(:frontend_release_publisher, previous_publisher_config)
    end)

    {:ok, port: port}
  end

  test "real HTTP/1.1 accepts valid chunked framing", %{port: port} do
    response =
      raw_request(
        port,
        common_headers() ++ [{"transfer-encoding", "chunked"}],
        "1\r\n{\r\n1\r\n}\r\n0\r\n\r\n"
      )

    assert response_status(response) == 400
  end

  test "real HTTP/1.1 rejects an over-limit chunked body", %{port: port} do
    body = String.duplicate("x", @max_body_bytes + 1)
    framing = Integer.to_string(byte_size(body), 16) <> "\r\n" <> body <> "\r\n0\r\n\r\n"

    response = raw_request(port, common_headers() ++ [{"transfer-encoding", "chunked"}], framing)

    assert response_status(response) == 413
  end

  test "real HTTP/1.1 rejects truncated chunk framing", %{port: port} do
    response =
      raw_request(
        port,
        common_headers() ++ [{"transfer-encoding", "chunked"}],
        "2\r\n{}\r\n"
      )

    assert response == {:error, :closed}
  end

  test "real HTTP/1.1 rejects duplicate, conflicting, and transfer framing headers", %{
    port: port
  } do
    requests = [
      common_headers() ++ [{"content-length", "0"}, {"content-length", "0"}],
      common_headers() ++ [{"content-length", "0"}, {"content-length", "1"}],
      common_headers() ++ [{"content-length", "0"}, {"transfer-encoding", "chunked"}]
    ]

    responses = Enum.map(requests, &raw_request(port, &1, ""))

    assert Enum.all?(responses, &(response_status(&1) == 400))
  end

  test "real HTTP/1.1 preflight rejects without waiting for the declared body", %{port: port} do
    response =
      raw_request(
        port,
        [
          {"host", "localhost"},
          {"authorization", "Bearer wrong-token"},
          {"content-type", "application/json"},
          {"content-length", Integer.to_string(@max_body_bytes)},
          {"connection", "close"}
        ],
        ""
      )

    assert response_status(response) == 401
  end

  defp common_headers do
    [
      {"host", "localhost"},
      {"authorization", "Bearer " <> @token},
      {"content-type", "application/json"},
      {"connection", "close"}
    ]
  end

  defp raw_request(port, headers, body) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)

    request = [
      "POST ",
      @path,
      " HTTP/1.1\r\n",
      Enum.map(headers, fn {name, value} -> [name, ": ", value, "\r\n"] end),
      "\r\n",
      body
    ]

    :ok = :gen_tcp.send(socket, request)
    :ok = :gen_tcp.shutdown(socket, :write)
    response = recv_headers(socket, <<>>)
    :ok = :gen_tcp.close(socket)
    response
  end

  defp recv_headers(socket, buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      {_, _} ->
        {:ok, buffer}

      :nomatch ->
        case :gen_tcp.recv(socket, 0, 10_000) do
          {:ok, data} -> recv_headers(socket, buffer <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp response_status({:ok, response}) do
    response
    |> String.split("\r\n", parts: 2)
    |> hd()
    |> String.split(" ")
    |> Enum.at(1)
    |> String.to_integer()
  end

  defp restore_config(key, nil), do: Application.delete_env(:cadence_web, key)
  defp restore_config(key, value), do: Application.put_env(:cadence_web, key, value)
end
