defmodule Cadence.Telemetry.PhysicalSampleQueryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.PhysicalSampleQuery
  alias Cadence.TestSupport.PhysicalSampleFixtures, as: Fixtures

  test "requires exact tenant, mission, point, physical id and source identity" do
    attrs = Fixtures.attrs()
    assert {:ok, query} = PhysicalSampleQuery.new(attrs)
    assert :ok = PhysicalSampleQuery.validate(query)

    for key <- Map.keys(attrs),
        invalid <- [nil, "", [], %{}, "bad\0id", String.duplicate("é", 129)] do
      assert {:error, :invalid_physical_sample_query} =
               PhysicalSampleQuery.new(Map.put(attrs, key, invalid))
    end

    for key <- [:limit, :order, :selection_view, :validity_state, :source_endpoint_id, :dataset] do
      assert {:error, :invalid_physical_sample_query} =
               PhysicalSampleQuery.new(Map.put(attrs, key, "ignored?"))
    end

    assert {:error, :invalid_physical_sample_query} =
             PhysicalSampleQuery.validate(%{query | point_id: ""})
  end

  test "does not erase empty endpoint scopes, alias conflicts, or replay identity" do
    for endpoints <- [
          [],
          ["endpoint", ""],
          ["endpoint", "endpoint"],
          Enum.map(1..101, &to_string/1)
        ] do
      assert {:error, :invalid_physical_sample_query} =
               PhysicalSampleQuery.new(Fixtures.attrs(%{source_endpoint_ids: endpoints}))
    end

    assert {:error, :invalid_physical_sample_query} =
             PhysicalSampleQuery.new(Fixtures.attrs(%{binding_id: "conflict"}))

    assert {:error, :invalid_physical_sample_query} =
             PhysicalSampleQuery.new(Fixtures.attrs(%{realm: :replay}))

    assert {:error, :invalid_physical_sample_query} =
             PhysicalSampleQuery.new(Fixtures.attrs(%{replay_run_id: "run"}))

    assert {:ok, %{realm: "replay", replay_run_id: "run"}} =
             PhysicalSampleQuery.new(Fixtures.attrs(%{realm: :replay, replay_run_id: "run"}))
  end

  test "matches actual identities and both clocks without canonical selection" do
    sample = Fixtures.sample()

    query =
      Fixtures.query(%{
        spacecraft_id: sample.spacecraft_id,
        source_endpoint_ids: ["endpoint-physical"],
        receipt_time: sample.receipt_time,
        from_observed_at: sample.generation_time,
        to_observed_at: sample.generation_time
      })

    assert PhysicalSampleQuery.matches?(query, sample, "org-physical")
    refute PhysicalSampleQuery.matches?(query, sample, "other-org")

    for key <- [
          :mission_id,
          :point_id,
          :sample_id,
          :spacecraft_id,
          :data_source_id,
          :source_binding_id
        ] do
      refute PhysicalSampleQuery.matches?(Map.put(query, key, "other"), sample, "org-physical")
    end

    refute PhysicalSampleQuery.matches?(%{query | realm: "simulation"}, sample, "org-physical")

    refute PhysicalSampleQuery.matches?(
             %{query | source_endpoint_ids: ["other"]},
             sample,
             "org-physical"
           )

    refute PhysicalSampleQuery.matches?(
             %{query | receipt_time: DateTime.add(sample.receipt_time, 1, :microsecond)},
             sample,
             "org-physical"
           )

    refute PhysicalSampleQuery.matches?(
             %{query | from_observed_at: sample.receipt_time},
             sample,
             "org-physical"
           )

    fallback = %{sample | generation_time: nil}

    assert PhysicalSampleQuery.matches?(
             Fixtures.query(%{from_observed_at: sample.receipt_time}),
             fallback,
             "org-physical"
           )
  end

  test "rejects malformed and reversed time constraints" do
    for attrs <- [
          %{receipt_time: "2026-09-08T12:00:00Z"},
          %{receipt_time: %{~U[2026-09-08 12:00:00Z] | month: 99}},
          %{
            from_receipt_time: ~U[2026-09-08 12:01:00Z],
            to_receipt_time: ~U[2026-09-08 12:00:00Z]
          },
          %{from_observed_at: ~U[2026-09-08 12:01:00Z], to_observed_at: ~U[2026-09-08 12:00:00Z]}
        ] do
      assert {:error, :invalid_physical_sample_query} =
               PhysicalSampleQuery.new(Fixtures.attrs(attrs))
    end
  end
end
