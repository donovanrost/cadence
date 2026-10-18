defmodule Cadence.Telemetry.HistoryStorePhysicalSampleTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.HistoryStore.Noop
  alias Cadence.TestSupport.PhysicalSampleFixtures, as: Fixtures

  def fetch_sample(query, opts), do: Keyword.fetch!(opts, :reply).(query, opts)

  test "dispatches through the captured backend and keeps connection options separate from identity" do
    query = Fixtures.query()
    sample = Fixtures.sample()
    policy = HistoryStore.policy(module: __MODULE__, marker: :captured, timeout: 1)

    reply = fn actual, opts ->
      assert actual == query
      assert opts[:marker] == :captured
      assert opts[:timeout] == 2
      assert opts[:organization_id] == "cannot-override-query"
      {:ok, %{organization_id: query.organization_id, sample: sample}}
    end

    assert {:ok, ^sample} =
             TelemetryReads.fetch_sample(query,
               history_store_policy: policy,
               reply: reply,
               timeout: 2,
               organization_id: "cannot-override-query"
             )
  end

  test "unsupported backends never fall back to history or another backend" do
    assert {:error, {:unsupported_history_capability, Noop, :fetch_sample}} =
             HistoryStore.fetch_sample(HistoryStore.policy(module: Noop), Fixtures.query(), [])
  end

  test "rejects invalid queries before backend execution and rejects mismatched records" do
    query = Fixtures.query()
    policy = HistoryStore.policy(module: __MODULE__)

    assert {:error, :invalid_physical_sample_query} =
             HistoryStore.fetch_sample(policy, %{query | sample_id: ""}, [])

    for record <- [
          %{organization_id: "foreign", sample: Fixtures.sample()},
          %{organization_id: "org-physical", sample: Fixtures.sample(%{point_id: "other"})}
        ] do
      assert {:error, :physical_sample_context_mismatch} =
               HistoryStore.fetch_sample(policy, query, reply: fn _, _ -> {:ok, record} end)
    end

    assert {:error, :invalid_physical_sample_result} =
             HistoryStore.fetch_sample(policy, query,
               reply: fn _, _ -> {:ok, Fixtures.sample()} end
             )

    assert {:error, :offline} =
             HistoryStore.fetch_sample(policy, query, reply: fn _, _ -> {:error, :offline} end)
  end
end
