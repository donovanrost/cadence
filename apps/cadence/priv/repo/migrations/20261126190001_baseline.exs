defmodule Cadence.Repo.Migrations.Baseline do
  use Ecto.Migration

  @baseline_sql Path.expand("../baseline.sql", __DIR__)

  def up do
    if schema_exists?() do
      raise "Cadence schema already exists; run dev/stack reset (#718)"
    end

    Ecto.Adapters.SQL.query!(repo(), File.read!(@baseline_sql), [],
      query_type: :text,
      timeout: :infinity,
      log: false
    )
  end

  def down do
    raise "Cadence baseline cannot be rolled back; run dev/stack reset (#718)"
  end

  defp schema_exists? do
    sql = """
    SELECT EXISTS (SELECT 1 FROM public.schema_migrations)
        OR EXISTS (
          SELECT 1 FROM pg_catalog.pg_tables
          WHERE schemaname = 'public' AND tablename <> 'schema_migrations'
        )
    """

    Ecto.Adapters.SQL.query!(repo(), sql).rows == [[true]]
  end
end
