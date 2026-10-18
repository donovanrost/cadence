defmodule CadenceWeb.Plugs.FrontendReleaseRequestBodyTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias CadenceWeb.FrontendReleasePublisherTestAdapter
  alias CadenceWeb.Plugs.FrontendReleaseRequestBody

  @path "/api/cadence/frontend-release/v1/releases"
  @upload_path "/api/cadence/frontend-release/v1/objects/sha256:" <> String.duplicate("a", 64)
  @max_envelope_bytes 4_000_000

  test "accepts a bounded envelope and retains the exact bytes" do
    body = "bounded-release-envelope"

    conn = body_conn(body, [{"content-length", Integer.to_string(byte_size(body))}])
    result = FrontendReleaseRequestBody.call(conn, [])

    assert {:ok, ^body} = FrontendReleaseRequestBody.raw_body(result)
    assert result.body_params == %{}
    assert_receive {:frontend_release_publisher_read, _, _}
  end

  test "rejects one byte over the body limit before reading a declared body" do
    conn =
      body_conn("", [{"content-length", Integer.to_string(@max_envelope_bytes + 1)}])

    result = FrontendReleaseRequestBody.call(conn, [])

    assert result.status == 413
    assert result.resp_body == ~s({"error":{"code":"oversized_input"}})
    refute_receive {:frontend_release_publisher_read, _, _}
  end

  test "rejects short and long bodies against Content-Length" do
    short = body_conn("short", [{"content-length", "10"}])
    long = body_conn("0123456789", [{"content-length", "5"}])

    assert FrontendReleaseRequestBody.call(short, []).status == 400
    assert FrontendReleaseRequestBody.call(long, []).status == 400
  end

  test "rejects malformed, long, duplicate, and conflicting Content-Length headers" do
    requests = [
      body_conn("", [{"content-length", "not-a-length"}]),
      body_conn("", [{"content-length", String.duplicate("1", 33)}]),
      body_conn("", [{"content-length", "0"}, {"content-length", "0"}]),
      body_conn("", [{"content-length", "1"}, {"content-length", "2"}])
    ]

    results = Enum.map(requests, &FrontendReleaseRequestBody.call(&1, []))

    assert Enum.all?(results, &(&1.status == 400))
    refute_receive {:frontend_release_publisher_read, _, _}
  end

  test "rejects Content-Length and transfer-encoding conflicts without reading" do
    requests = [
      body_conn("", [{"content-length", "0"}, {"transfer-encoding", "chunked"}]),
      body_conn("", [{"transfer-encoding", "gzip"}]),
      body_conn("", [{"transfer-encoding", "chunked"}, {"transfer-encoding", "chunked"}])
    ]

    results = Enum.map(requests, &FrontendReleaseRequestBody.call(&1, []))

    assert Enum.all?(results, &(&1.status == 400))
    refute_receive {:frontend_release_publisher_read, _, _}
  end

  test "accepts a body terminated by the adapter without Content-Length" do
    body = "bounded-body"
    result = FrontendReleaseRequestBody.call(body_conn(body, []), [])

    assert {:ok, ^body} = FrontendReleaseRequestBody.raw_body(result)
  end

  test "maps explicit adapter read errors to malformed transport" do
    conn =
      Plug.Test.conn(:post, @path, "")
      |> put_req_header("content-type", "application/json")
      |> replace_adapter(
        FrontendReleasePublisherTestAdapter.responses([{:error, :closed}], self())
      )

    result = FrontendReleaseRequestBody.call(conn, [])

    assert result.status == 400
    assert result.resp_body == ~s({"error":{"code":"malformed_body"}})
  end

  test "does not mask adapter programming exceptions or throws" do
    for response <- [{:raise, RuntimeError}, {:throw, :adapter_fault}] do
      conn =
        Plug.Test.conn(:post, @path, "")
        |> put_req_header("content-type", "application/json")
        |> replace_adapter(FrontendReleasePublisherTestAdapter.responses([response], self()))

      assert_raise_or_throw(response, fn -> FrontendReleaseRequestBody.call(conn, []) end)
    end
  end

  test "cleans the staged upload file after a successful handoff" do
    body = "staged-artifact"
    result = FrontendReleaseRequestBody.call(upload_conn(body), [])

    assert {:ok, file_path} = FrontendReleaseRequestBody.staged_artifact_path(result)
    assert File.read!(file_path) == body
    assert File.exists?(file_path)

    _ = FrontendReleaseRequestBody.cleanup_staged_artifact(result)
    refute File.exists?(file_path)
  end

  test "cleans a staged upload after rejection and disconnect" do
    before = staged_residue()

    rejected =
      upload_conn("", [{"content-length", "100000001"}])
      |> FrontendReleaseRequestBody.call([])

    disconnected =
      Plug.Test.conn(:put, @upload_path, "")
      |> put_req_header("content-type", "application/octet-stream")
      |> replace_adapter(
        FrontendReleasePublisherTestAdapter.responses([{:error, :closed}], self())
      )
      |> FrontendReleaseRequestBody.call([])

    assert rejected.status == 413
    assert disconnected.status == 400
    assert staged_residue() == before
  end

  test "cleans a staged upload after an adapter exception while propagating it" do
    before = staged_residue()

    conn =
      Plug.Test.conn(:put, @upload_path, "")
      |> put_req_header("content-type", "application/octet-stream")
      |> replace_adapter(
        FrontendReleasePublisherTestAdapter.responses([{:raise, RuntimeError}], self())
      )

    assert_raise RuntimeError, fn -> FrontendReleaseRequestBody.call(conn, []) end
    assert staged_residue() == before
  end

  defp body_conn(body, headers) do
    Plug.Test.conn(:post, @path, "")
    |> then(&replace_adapter(&1, FrontendReleasePublisherTestAdapter.body(body, self())))
    |> put_headers(headers)
  end

  defp upload_conn(body, headers \\ []) do
    Plug.Test.conn(:put, @upload_path, "")
    |> then(&replace_adapter(&1, FrontendReleasePublisherTestAdapter.body(body, self())))
    |> put_req_header("content-type", "application/octet-stream")
    |> put_headers(headers)
  end

  defp staged_residue do
    Path.wildcard(Path.join(System.tmp_dir!(), ".cadence_frontend_release_*"))
    |> Enum.sort()
  end

  defp put_headers(conn, headers),
    do: %{conn | req_headers: conn.req_headers ++ headers}

  defp replace_adapter(conn, adapter_state),
    do: %{conn | adapter: {FrontendReleasePublisherTestAdapter, adapter_state}}

  defp assert_raise_or_throw({:raise, exception}, fun), do: assert_raise(exception, fun)

  defp assert_raise_or_throw({:throw, value}, fun) do
    assert catch_throw(fun.()) == value
  end
end
