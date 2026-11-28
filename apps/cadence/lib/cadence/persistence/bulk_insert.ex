defmodule Cadence.Persistence.BulkInsert do
  @moduledoc false

  alias Cadence.Repo
  alias Ecto.Changeset

  @batch_size 500

  @doc "Inserts a bounded batch using one array per varying column and one bind per shared value."
  def insert!(schema, rows, shared \\ []) do
    shared_fields = Keyword.keys(shared)
    fields = schema.__schema__(:fields) -- shared_fields
    columns = Enum.map(fields, &column_values(rows, &1))
    params = columns ++ Enum.map(Keyword.values(shared), &postgres_value/1)
    table = schema.__schema__(:source)

    Repo.query!(insert_sql(table, schema, fields, shared_fields), params, source: table).num_rows
  end

  # For caller-assigned keys. The changeset supplies casts, defaults and validation before SQL.
  def changesets(schema, changesets, opts \\ []) do
    fields = schema.__schema__(:fields)
    now = DateTime.utc_now()

    with {:ok, rows} <- rows(changesets, fields, now) do
      count =
        rows
        |> Enum.reverse()
        |> Enum.chunk_every(@batch_size)
        |> Enum.reduce(0, fn chunk, count ->
          {inserted, nil} = Repo.insert_all(schema, chunk, opts)
          count + inserted
        end)

      {:ok, count}
    end
  end

  defp rows(changesets, fields, now) do
    Enum.reduce_while(changesets, {:ok, []}, fn changeset, {:ok, rows} ->
      case Changeset.apply_action(changeset, :insert) do
        {:ok, row} ->
          row =
            row
            |> Map.take(fields)
            |> Map.replace_lazy(:inserted_at, &(&1 || now))
            |> Map.replace_lazy(:updated_at, &(&1 || now))

          {:cont, {:ok, [row | rows]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp insert_sql(table, schema, fields, shared_fields) do
    arrays =
      fields
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {field, index} ->
        "$#{index}::#{column_type(schema, field)}[]"
      end)

    shared =
      shared_fields
      |> Enum.with_index(length(fields) + 1)
      |> Enum.map_join(fn {field, index} -> ", $#{index}::#{column_type(schema, field)}" end)

    columns = Enum.join(fields ++ shared_fields, ", ")
    "INSERT INTO #{table} (#{columns}) SELECT batch.*#{shared} FROM unnest(#{arrays}) AS batch"
  end

  defp column_values(rows, field),
    do: Enum.map(rows, &postgres_value(Map.fetch!(&1, field)))

  defp postgres_value(%DateTime{} = value), do: DateTime.to_naive(value)
  defp postgres_value(value), do: value

  defp column_type(schema, field) do
    case schema.__schema__(:type, field) do
      :string -> "text"
      :integer -> "bigint"
      :float -> "double precision"
      :boolean -> "boolean"
      :map -> "jsonb"
      :utc_datetime_usec -> "timestamp"
    end
  end
end
