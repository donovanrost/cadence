defmodule Cadence.Telemetry.Storage.QuestDB.ObservationReaderTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.Storage.QuestDB.ObservationReader

  test "builds canonical history query with tenant and source filters" do
    from_receipt = ~U[2026-06-17 12:00:00Z]
    to_receipt = ~U[2026-06-17 12:05:00Z]

    {sql, params} =
      ObservationReader.query("mission-1", "HK.counter",
        organization_id: "org-1",
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        source_binding_id: "default_flight_telemetry",
        spacecraft_id: "sc-1",
        from_receipt_time: from_receipt,
        to_receipt_time: to_receipt,
        order: :asc,
        limit: 250
      )

    assert sql =~ "SELECT sample_id, mission_id, spacecraft_id"
    assert sql =~ "FROM telemetry_observations"
    assert sql =~ "mission_id = $1"
    assert sql =~ "point_id = $2"
    assert sql =~ "realm = $3"
    refute sql =~ "validity_state ="
    assert sql =~ "organization_id = $4"
    assert sql =~ "spacecraft_id = $5"
    assert sql =~ "data_source_id = $6"
    assert sql =~ "binding_id = $7"
    assert sql =~ "receipt_time >= $8"
    assert sql =~ "receipt_time <= $9"
    assert sql =~ "ORDER BY receipt_time ASC, sample_id ASC"
    assert sql =~ "LIMIT 2500"

    assert params == [
             "mission-1",
             "HK.counter",
             "flight",
             "org-1",
             "sc-1",
             "managed_questdb_primary",
             "default_flight_telemetry",
             ~N[2026-06-17 12:00:00],
             ~N[2026-06-17 12:05:00]
           ]

    sql_text = ObservationReader.query_sql("mission-1", "HK.counter", organization_id: "org-1")
    assert sql_text =~ "mission_id = 'mission-1'"
    assert sql_text =~ "organization_id = 'org-1'"
  end

  test "builds generation-time history query with observed-at bounds and ordering" do
    from_observed_at = ~U[2026-06-17 12:00:00Z]
    to_observed_at = ~U[2026-06-17 12:05:00Z]

    {sql, params} =
      ObservationReader.query("mission-1", "HK.counter",
        organization_id: "org-1",
        realm: :replay,
        replay_run_id: "replay-run-1",
        data_source_id: "managed_questdb_replay",
        source_binding_id: "replay_telemetry",
        time_axis: :generation_time,
        from_observed_at: from_observed_at,
        to_observed_at: to_observed_at,
        order: :asc,
        limit: 250
      )

    assert sql =~ "observed_at >= $8"
    assert sql =~ "observed_at <= $9"
    assert sql =~ "ORDER BY observed_at ASC, receipt_time ASC, sample_id ASC"
    refute sql =~ "receipt_time >="
    refute sql =~ "receipt_time <="

    assert params == [
             "mission-1",
             "HK.counter",
             "replay",
             "org-1",
             "managed_questdb_replay",
             "replay_telemetry",
             "replay-run-1",
             ~N[2026-06-17 12:00:00],
             ~N[2026-06-17 12:05:00]
           ]
  end

  test "defaults to canonical flight reads and bounds invalid limit" do
    {sql, params} = ObservationReader.query("mission-1", "HK.counter", limit: "bad")

    refute sql =~ "validity_state ="
    assert sql =~ "LIMIT 1000"
    assert params == ["mission-1", "HK.counter", "flight"]
  end

  test "filters history, decimated history, and watermarks by source endpoint ids" do
    {history_sql, history_params} =
      ObservationReader.query("mission-1", "HK.counter",
        source_endpoint_ids: ["endpoint-a", "endpoint-b"]
      )

    assert history_sql =~ "(source_endpoint_id = $4 OR source_endpoint_id = $5)"
    assert history_params == ["mission-1", "HK.counter", "flight", "endpoint-a", "endpoint-b"]

    {decimated_sql, decimated_params} =
      ObservationReader.decimated_query("mission-1", "HK.counter",
        source_endpoint_ids: ["endpoint-a", "endpoint-b"]
      )

    assert decimated_sql =~ "(source_endpoint_id = $5 OR source_endpoint_id = $6)"

    assert decimated_params == [
             "mission-1",
             "HK.counter",
             "flight",
             "canonical",
             "endpoint-a",
             "endpoint-b"
           ]

    {watermark_sql, watermark_params} =
      ObservationReader.watermark_query("mission-1", "HK.counter",
        source_endpoint_ids: ["endpoint-a", "endpoint-b"]
      )

    assert watermark_sql =~ "(source_endpoint_id = $5 OR source_endpoint_id = $6)"

    assert watermark_params == [
             "mission-1",
             "HK.counter",
             "flight",
             "canonical",
             "endpoint-a",
             "endpoint-b"
           ]
  end

  test "filters history, decimated history, and watermarks by replay run identity" do
    {history_sql, history_params} =
      ObservationReader.query("mission-1", "HK.counter", replay_run_id: "replay-run-1")

    assert history_sql =~ "replay_run_id = $4"
    assert history_params == ["mission-1", "HK.counter", "flight", "replay-run-1"]

    {decimated_sql, decimated_params} =
      ObservationReader.decimated_query("mission-1", "HK.counter", replay_run_id: "replay-run-1")

    assert decimated_sql =~ "replay_run_id = $5"

    assert decimated_params == [
             "mission-1",
             "HK.counter",
             "flight",
             "canonical",
             "replay-run-1"
           ]

    {watermark_sql, watermark_params} =
      ObservationReader.watermark_query("mission-1", "HK.counter", replay_run_id: "replay-run-1")

    assert watermark_sql =~ "replay_run_id = $5"

    assert watermark_params == [
             "mission-1",
             "HK.counter",
             "flight",
             "canonical",
             "replay-run-1"
           ]
  end

  test "requires replay run identity for replay result reads" do
    exec_fun = fn _sql, _opts -> flunk("replay reads without replay_run_id must not query") end

    opts = [realm: :replay, exec_fun: exec_fun]

    assert {:error, {:missing_field, :replay_run_id}} =
             ObservationReader.sample_history_result("mission-1", "HK.counter", opts)

    assert [] = ObservationReader.sample_history("mission-1", "HK.counter", opts)

    assert {:error, {:missing_field, :replay_run_id}} =
             ObservationReader.decimated_history_result("mission-1", "HK.counter", opts)

    assert {:error, {:missing_field, :replay_run_id}} =
             ObservationReader.decimated_history("mission-1", "HK.counter", opts)

    assert {:error, {:missing_field, :replay_run_id}} =
             ObservationReader.sample_watermark_result("mission-1", "HK.counter", opts)
  end

  test "overfetches canonical candidates before applying the logical result limit" do
    exec_fun = fn sql, _opts ->
      assert sql =~ "LIMIT 100"

      {:ok,
       %{
         "columns" => Enum.map(ObservationReader.select_columns(), &%{"name" => &1}),
         "dataset" => [
           observation_row("sample-conflict", "obs-conflict", "obs-ident-1", 99, "conflict"),
           observation_row("sample-canonical", "obs-canonical", "obs-ident-2", 20, "canonical")
         ]
       }}
    end

    assert {:ok, %{samples: [sample], diagnostics: diagnostics}} =
             ObservationReader.sample_history_result("mission-1", "HK.counter",
               exec_fun: exec_fun,
               identity_states: [],
               limit: 1
             )

    assert sample.sample_id == "sample-canonical"
    assert sample.engineering_value == 20
    assert diagnostics.physical_candidate_count == 2
    assert diagnostics.logical_selected_count == 1
    assert diagnostics.requested_logical_limit == 1
    assert diagnostics.physical_candidate_limit == 100
    refute diagnostics.candidate_window_exhausted?
  end

  test "diagnoses exhausted canonical candidate windows" do
    exec_fun = fn sql, _opts ->
      assert sql =~ "LIMIT 2"

      {:ok,
       %{
         "columns" => Enum.map(ObservationReader.select_columns(), &%{"name" => &1}),
         "dataset" => [
           observation_row("sample-conflict-1", "obs-conflict-1", "obs-ident-1", 99, "conflict"),
           observation_row("sample-conflict-2", "obs-conflict-2", "obs-ident-2", 98, "conflict")
         ]
       }}
    end

    assert {:ok, %{samples: [], diagnostics: diagnostics}} =
             ObservationReader.sample_history_result("mission-1", "HK.counter",
               exec_fun: exec_fun,
               identity_states: [],
               limit: 1,
               candidate_limit: 2
             )

    assert diagnostics.physical_candidate_count == 2
    assert diagnostics.logical_selected_count == 0
    assert diagnostics.requested_logical_limit == 1
    assert diagnostics.physical_candidate_limit == 2
    assert diagnostics.candidate_window_exhausted?
  end

  test "supports explicit all-revision history queries" do
    {sql, params} =
      ObservationReader.query("mission-1", "HK.counter",
        organization_id: "org-1",
        view: :all_revisions
      )

    refute sql =~ "validity_state ="
    assert sql =~ "organization_id = $4"
    assert params == ["mission-1", "HK.counter", "flight", "org-1"]
  end

  test "supports explicit physical validity filters for noncanonical history queries" do
    {sql, params} =
      ObservationReader.query("mission-1", "HK.counter",
        organization_id: "org-1",
        validity_state: :conflict
      )

    assert sql =~ "validity_state = $4"
    assert sql =~ "organization_id = $5"
    assert sql =~ "LIMIT 100"
    assert params == ["mission-1", "HK.counter", "flight", "conflict", "org-1"]
  end

  test "builds native decimated history query with sample by bucket" do
    from_receipt = ~U[2026-06-17 12:00:00Z]
    to_receipt = ~U[2026-06-17 12:05:00Z]

    query_opts = [
      organization_id: "org-1",
      realm: :flight,
      data_source_id: "managed_questdb_primary",
      source_binding_id: "default_flight_telemetry",
      spacecraft_id: "sc-1",
      from_receipt_time: from_receipt,
      to_receipt_time: to_receipt,
      bucket_width_ms: 60_000
    ]

    {sql, params} = ObservationReader.decimated_query("mission-1", "HK.counter", query_opts)

    assert sql =~ "SELECT"
    assert sql =~ "observed_at AS bucket_start"
    assert sql =~ "min(coalesce(value_double, value_long)) AS bucket_min"
    assert sql =~ "max(coalesce(value_double, value_long)) AS bucket_max"
    assert sql =~ "avg(coalesce(value_double, value_long)) AS bucket_mean"
    assert sql =~ "count() AS sample_count"
    assert sql =~ "FROM telemetry_observations"
    assert sql =~ "mission_id = $1"
    assert sql =~ "receipt_time >= $9"
    assert sql =~ "receipt_time <= $10"
    assert sql =~ "value_kind IN ('double', 'long')"
    assert sql =~ "SAMPLE BY 60000ms ALIGN TO CALENDAR"

    assert params == [
             "mission-1",
             "HK.counter",
             "flight",
             "canonical",
             "org-1",
             "sc-1",
             "managed_questdb_primary",
             "default_flight_telemetry",
             ~N[2026-06-17 12:00:00],
             ~N[2026-06-17 12:05:00]
           ]

    rendered_sql = ObservationReader.decimated_query_sql("mission-1", "HK.counter", query_opts)

    assert rendered_sql =~ "receipt_time >= '2026-06-17T12:00:00Z'"
    assert rendered_sql =~ "receipt_time <= '2026-06-17T12:05:00Z'"
    refute rendered_sql =~ "managed_questdb_primary'0"

    sql_text =
      ObservationReader.decimated_query_sql("mission-1", "HK.counter",
        organization_id: "org-1",
        target_points: 300,
        from_receipt_time: from_receipt,
        to_receipt_time: to_receipt
      )

    assert sql_text =~ "mission_id = 'mission-1'"
    assert sql_text =~ "organization_id = 'org-1'"
    assert sql_text =~ "SAMPLE BY 1000ms ALIGN TO CALENDAR"
  end

  test "builds watermark query with tenant and source filters" do
    {sql, params} =
      ObservationReader.watermark_query("mission-1", "HK.counter",
        organization_id: "org-1",
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        source_binding_id: "default_flight_telemetry",
        spacecraft_id: "sc-1"
      )

    assert sql =~ "max(receipt_time) AS latest_receipt_time"
    assert sql =~ "min(receipt_time) AS retention_starts_at"
    assert sql =~ "count() AS sample_count"
    assert sql =~ "FROM telemetry_observations"
    assert sql =~ "mission_id = $1"
    assert sql =~ "point_id = $2"
    assert sql =~ "realm = $3"
    assert sql =~ "validity_state = $4"
    assert sql =~ "organization_id = $5"
    assert sql =~ "spacecraft_id = $6"
    assert sql =~ "data_source_id = $7"
    assert sql =~ "binding_id = $8"

    assert params == [
             "mission-1",
             "HK.counter",
             "flight",
             "canonical",
             "org-1",
             "sc-1",
             "managed_questdb_primary",
             "default_flight_telemetry"
           ]

    sql_text =
      ObservationReader.watermark_query_sql("mission-1", "HK.counter", organization_id: "org-1")

    assert sql_text =~ "mission_id = 'mission-1'"
    assert sql_text =~ "organization_id = 'org-1'"
  end

  test "maps QuestDB result rows back to telemetry samples" do
    result = %{
      "columns" => Enum.map(ObservationReader.select_columns(), &%{"name" => &1}),
      "dataset" => [
        [
          "sample-1",
          "mission-1",
          "sc-1",
          "HK.counter",
          "Counter",
          "packet-def-1",
          1,
          "packet-1",
          "evidence-1",
          "long",
          nil,
          42,
          nil,
          nil,
          ~s({"counts":42}),
          "good",
          ~N[2026-06-17 12:00:00],
          ~N[2026-06-17 12:00:03],
          ~s({"source":"station-a"}),
          "flight",
          "managed_questdb_primary",
          "default_flight_telemetry",
          "station-a",
          "replay-run-1",
          "obs-1",
          "obs-ident-1",
          "canonical"
        ]
      ]
    }

    assert [sample] = ObservationReader.samples_from_result(result)

    assert sample.sample_id == "sample-1"
    assert sample.mission_id == "mission-1"
    assert sample.spacecraft_id == "sc-1"
    assert sample.point_id == "HK.counter"
    assert sample.raw_value == %{"counts" => 42}
    assert sample.engineering_value == 42
    assert sample.quality_state == :good
    assert sample.generation_time == ~U[2026-06-17 12:00:00Z]
    assert sample.receipt_time == ~U[2026-06-17 12:00:03Z]

    assert sample.provenance == %{
             "source" => "station-a",
             "storage" => %{
               "binding_id" => "default_flight_telemetry",
               "data_source_id" => "managed_questdb_primary",
               "observation_id" => "obs-1",
               "observation_identity_id" => "obs-ident-1",
               "realm" => "flight",
               "replay_run_id" => "replay-run-1",
               "source_endpoint_id" => "station-a",
               "validity_state" => "canonical"
             }
           }
  end

  test "applies identity-state decisions to QuestDB sample history results" do
    exec_fun = fn sql, _opts ->
      assert sql =~ "FROM telemetry_observations"
      refute sql =~ "validity_state ="

      {:ok,
       %{
         "columns" => Enum.map(ObservationReader.select_columns(), &%{"name" => &1}),
         "dataset" => [
           observation_row("sample-canonical", "obs-canonical", "obs-ident-1", 20, "canonical"),
           observation_row("sample-conflict", "obs-conflict", "obs-ident-1", 99, "conflict")
         ]
       }}
    end

    assert {:ok, %{samples: [sample]}} =
             ObservationReader.sample_history_result("mission-1", "HK.counter",
               exec_fun: exec_fun,
               identity_states: [
                 %{
                   observation_identity_id: "obs-ident-1",
                   canonical_observation_id: "obs-conflict",
                   canonical_sample_id: "sample-conflict",
                   canonical_revision: 1,
                   decision_reason: "operator_selected_conflict_candidate",
                   payload: %{"decision" => %{"decision" => "mark_canonical"}}
                 }
               ],
               order: :asc,
               limit: 10
             )

    assert sample.sample_id == "sample-conflict"
    assert sample.engineering_value == 99
    assert sample.provenance["storage"]["validity_state"] == "canonical"

    assert sample.provenance["storage"]["decision_reason"] ==
             "operator_selected_conflict_candidate"
  end

  test "maps QuestDB decimated rows into bucket maps" do
    result = %{
      "columns" => Enum.map(ObservationReader.decimated_select_columns(), &%{"name" => &1}),
      "dataset" => [
        [
          ~N[2026-06-17 12:00:00],
          10.5,
          12.25,
          11.75,
          42,
          "good"
        ]
      ]
    }

    assert [bucket] = ObservationReader.decimated_buckets_from_result(result, 60_000)
    assert bucket.bucket_start == ~U[2026-06-17 12:00:00Z]
    assert DateTime.compare(bucket.bucket_end, ~U[2026-06-17 12:01:00Z]) == :eq
    assert bucket.min == 10.5
    assert bucket.max == 12.25
    assert bucket.mean == 11.75
    assert bucket.sample_count == 42
    assert bucket.worst_quality_state == :good
  end

  test "maps QuestDB watermark row into best-effort freshness" do
    result = %{
      "columns" => Enum.map(ObservationReader.watermark_select_columns(), &%{"name" => &1}),
      "dataset" => [
        [
          ~N[2026-06-17 12:05:00],
          ~N[2026-06-17 11:00:00],
          42
        ]
      ]
    }

    assert %{
             complete_through: ~U[2026-06-17 12:05:00Z],
             latest_receipt_time: ~U[2026-06-17 12:05:00Z],
             retention_starts_at: ~U[2026-06-17 11:00:00Z],
             sample_count: 42,
             confidence: :best_effort
           } = ObservationReader.watermark_from_result(result)
  end

  test "executes watermark query through configured exec function" do
    parent = self()

    exec_fun = fn sql, opts ->
      send(parent, {:questdb_exec, sql, opts})

      {:ok,
       %{
         "columns" => Enum.map(ObservationReader.watermark_select_columns(), &%{"name" => &1}),
         "dataset" => [[~N[2026-06-17 12:05:00], ~N[2026-06-17 11:00:00], 42]]
       }}
    end

    assert {:ok, %{confidence: :best_effort, sample_count: 42}} =
             ObservationReader.sample_watermark_result("mission-1", "HK.counter",
               exec_fun: exec_fun
             )

    assert_receive {:questdb_exec, sql, opts}
    assert sql =~ "max(receipt_time) AS latest_receipt_time"
    assert opts[:exec_fun] == exec_fun
  end

  test "executes decimated history query through configured exec function" do
    parent = self()

    exec_fun = fn sql, opts ->
      send(parent, {:questdb_exec, sql, opts})

      {:ok,
       %{
         "columns" => Enum.map(ObservationReader.decimated_select_columns(), &%{"name" => &1}),
         "dataset" => [
           [~N[2026-06-17 12:00:00], 10, 12, 11, 3, "good"]
         ]
       }}
    end

    assert {:ok,
            %{
              buckets: [%{mean: 11, sample_count: 3}],
              diagnostics: %{
                canonical_mode: :physical,
                aggregate_semantics: :physical_as_recorded,
                bucket_count: 1,
                bucket_width_ms: 60_000,
                effective_selection?: false
              }
            }} =
             ObservationReader.decimated_history_result("mission-1", "HK.counter",
               bucket_width_ms: 60_000,
               exec_fun: exec_fun
             )

    assert_receive {:questdb_exec, sql, opts}
    assert sql =~ "SAMPLE BY 60000ms"
    assert opts[:exec_fun] == exec_fun
  end

  test "unwraps decimated history buckets for plain callers" do
    exec_fun = fn _sql, _opts ->
      {:ok,
       %{
         "columns" => Enum.map(ObservationReader.decimated_select_columns(), &%{"name" => &1}),
         "dataset" => [
           [~N[2026-06-17 12:00:00], 10, 12, 11, 3, "good"]
         ]
       }}
    end

    assert {:ok, [%{mean: 11, sample_count: 3}]} =
             ObservationReader.decimated_history("mission-1", "HK.counter",
               bucket_width_ms: 60_000,
               exec_fun: exec_fun
             )
  end

  test "maps primitive engineering value kinds" do
    assert row_value("double", 1.5, nil, nil, nil) == 1.5
    assert row_value("bool", nil, nil, false, nil) == false
    assert row_value("string", nil, nil, nil, "safe") == "safe"
    assert row_value("nil", nil, nil, nil, nil) == nil
  end

  defp row_value(value_kind, value_double, value_long, value_bool, value_string) do
    row = %{
      value_kind: value_kind,
      value_double: value_double,
      value_long: value_long,
      value_bool: value_bool,
      value_string: value_string,
      raw_value_text: nil,
      quality_state: "good",
      generation_time: nil,
      receipt_time: ~N[2026-06-17 12:00:03]
    }

    row
    |> ObservationReader.sample_from_row()
    |> Map.fetch!(:engineering_value)
  end

  defp observation_row(sample_id, observation_id, observation_identity_id, value, validity_state) do
    [
      sample_id,
      "mission-1",
      "sc-1",
      "HK.counter",
      "Counter",
      "packet-def-1",
      1,
      "packet-" <> sample_id,
      "evidence-" <> sample_id,
      "long",
      nil,
      value,
      nil,
      nil,
      Jason.encode!(%{"counts" => value}),
      "good",
      ~N[2026-06-17 12:00:00],
      ~N[2026-06-17 12:00:03],
      "{}",
      "flight",
      "managed_questdb_primary",
      "default_flight_telemetry",
      "station-a",
      nil,
      observation_id,
      observation_identity_id,
      validity_state
    ]
  end
end
