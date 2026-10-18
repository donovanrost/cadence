defmodule Cadence.Telemetry.HistoryStorePhysicalSampleETSTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.HistoryStore.ETS
  alias Cadence.TestSupport.PhysicalSampleFixtures, as: Fixtures

  @backend_opts [name: __MODULE__, table_name: __MODULE__, config_table_name: __MODULE__.Config]

  setup do
    start_supervised!({ETS, @backend_opts})
    %{policy: HistoryStore.policy([module: ETS] ++ @backend_opts)}
  end

  test "retrieves an older superseded physical sample without a history limit or selection view",
       %{policy: policy} do
    original = Fixtures.sample()

    newer =
      Fixtures.sample(%{
        sample_id: "newer",
        receipt_time: DateTime.add(original.receipt_time, 30)
      })

    assert :ok = HistoryStore.persist_samples(policy, [original, newer])
    assert {:ok, ^original} = HistoryStore.fetch_sample(policy, Fixtures.query(), [])

    assert {:error, :not_found} =
             HistoryStore.fetch_sample(policy, Fixtures.query(%{sample_id: "missing"}), [])
  end

  test "checks tenant and scope before counting candidate records", %{policy: policy} do
    original = Fixtures.sample()

    foreign = %{
      original
      | receipt_time: DateTime.add(original.receipt_time, -1),
        provenance: put_in(original.provenance, ["storage", "organization_id"], "foreign")
    }

    assert :ok = HistoryStore.persist_samples(policy, [foreign, original])
    assert {:ok, ^original} = HistoryStore.fetch_sample(policy, Fixtures.query(), [])

    assert {:error, :not_found} =
             HistoryStore.fetch_sample(
               policy,
               Fixtures.query(%{organization_id: "missing-org"}),
               []
             )

    assert {:error, :not_found} =
             HistoryStore.fetch_sample(
               policy,
               Fixtures.query(%{source_endpoint_ids: ["other"]}),
               []
             )
  end

  test "reports ambiguous sample ids and can narrow them by exact receipt microsecond", %{
    policy: policy
  } do
    original = Fixtures.sample()
    later = %{original | receipt_time: DateTime.add(original.receipt_time, 1, :microsecond)}
    assert :ok = HistoryStore.persist_samples(policy, [original, later])

    assert {:error, :ambiguous_physical_sample} =
             HistoryStore.fetch_sample(policy, Fixtures.query(), [])

    assert {:ok, ^original} =
             HistoryStore.fetch_sample(
               policy,
               Fixtures.query(%{receipt_time: original.receipt_time}),
               []
             )
  end

  test "records without stored tenant evidence cannot satisfy a scoped physical read", %{
    policy: policy
  } do
    for provenance <- [nil, %{}, %{"storage" => nil}] do
      assert :ok =
               HistoryStore.persist_samples(policy, [Fixtures.sample(%{provenance: provenance})])

      assert {:error, :not_found} = HistoryStore.fetch_sample(policy, Fixtures.query(), [])
    end
  end
end
