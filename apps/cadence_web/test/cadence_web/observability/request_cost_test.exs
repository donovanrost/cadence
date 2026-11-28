defmodule CadenceWeb.Observability.RequestCostTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias CadenceWeb.Observability.RequestCost

  @query_event [:cadence, :repo, :query]

  test "counts native query, decode and queue times from the request and nested tasks" do
    conn =
      RequestCost.measure(conn(:get, "/health/ready"), :test, fn conn ->
        query(query_time: 1_000, decode_time: 500, queue_time: 250)

        Task.async(fn ->
          Task.async(fn -> query(query_time: 2_000, queue_time: 750) end) |> Task.await()
        end)
        |> Task.await()

        # Work without a callers chain does not belong to the request.
        parent = self()

        spawn(fn ->
          query(query_time: 3_000)
          send(parent, :query_finished)
        end)

        assert_receive :query_finished
        send_resp(conn, 200, "")
      end)

    assert %{queries: 2, db_ms: 3.5, queue_ms: 1.0, wall_ms: wall_ms} =
             conn.private.cadence_request_cost

    assert wall_ms >= 0
    assert get_resp_header(conn, "x-cadence-db") == []

    query(query_time: 4_000)

    fresh_conn = RequestCost.measure(conn(:get, "/health/ready"), :test, &send_resp(&1, 200, ""))
    assert %{queries: 0, db_ms: +0.0, queue_ms: +0.0} = fresh_conn.private.cadence_request_cost
  end

  test "includes metrics in a development response header" do
    conn =
      RequestCost.measure(conn(:get, "/api/v1/missions/example"), :dev, fn conn ->
        query(query_time: 1_000, queue_time: 500)
        send_resp(conn, 200, "")
      end)

    assert ["queries=1; db_ms=1.0; queue_ms=0.5; wall_ms=" <> _] =
             get_resp_header(conn, "x-cadence-db")
  end

  test "measures the endpoint's unmatched route response" do
    conn =
      :get
      |> conn("/unmatched-request-cost-test")
      |> CadenceWeb.Endpoint.call(CadenceWeb.Endpoint.init([]))

    assert conn.status == 404
    assert %{queries: 0, db_ms: +0.0, queue_ms: +0.0} = conn.private.cadence_request_cost
  end

  defp query(measurements) do
    measurements =
      Map.new(measurements, fn {key, us} ->
        {key, System.convert_time_unit(us, :microsecond, :native)}
      end)

    total_time = measurements |> Map.values() |> Enum.sum()

    :telemetry.execute(@query_event, Map.put(measurements, :total_time, total_time), %{
      query: "SELECT 1",
      repo: Cadence.Repo,
      result: {:ok, nil},
      source: nil,
      type: :ecto_sql_query
    })
  end
end
