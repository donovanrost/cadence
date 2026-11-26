defmodule Cadence.Persistence.IdentityTextCollationTest do
  use Cadence.DataCase, async: true

  test "identity text columns use bytewise database collation" do
    %{rows: columns} =
      Repo.query!("""
      SELECT table_name, column_name, collation_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND data_type IN ('text', 'character varying')
        AND (column_name ~ '(_id|_key)$' OR column_name IN ('slug', 'key'))
        AND collation_name IS DISTINCT FROM 'C'
      ORDER BY table_name, column_name
      """)

    assert columns == []
  end

  test "cursor indexes inherit bytewise collation from identity columns" do
    %{rows: indexes} =
      Repo.query!("""
      SELECT index_rel.relname,
        bool_and(coll.collname = 'C') FILTER (WHERE index_key.collation_oid <> 0)
      FROM pg_index index_row
      JOIN pg_class index_rel ON index_rel.oid = index_row.indexrelid
      CROSS JOIN LATERAL unnest(index_row.indcollation) AS index_key(collation_oid)
      LEFT JOIN pg_collation coll ON coll.oid = index_key.collation_oid
      WHERE index_rel.relname IN (
        'mission_spacecraft_name_cursor_idx',
        'telemetry_latest_limit_states_active_order_idx'
      )
      GROUP BY index_rel.relname
      ORDER BY index_rel.relname
      """)

    assert indexes == [
             ["mission_spacecraft_name_cursor_idx", true],
             ["telemetry_latest_limit_states_active_order_idx", true]
           ]
  end
end
