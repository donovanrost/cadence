defmodule Cadence.ETS do
  @moduledoc false

  alias Cadence.ETS.Owner, as: ETSOwner

  @spec ensure_named_table(atom(), [term()]) :: :ok
  def ensure_named_table(table_name, options) when is_atom(table_name) and is_list(options) do
    case Process.whereis(ETSOwner) do
      nil ->
        ensure_named_table_locally(table_name, options)

      _pid ->
        ETSOwner.ensure_named_table(table_name, options)
    end
  end

  defp ensure_named_table_locally(table_name, options) do
    case :ets.whereis(table_name) do
      :undefined ->
        try do
          :ets.new(table_name, options)
          :ok
        rescue
          ArgumentError -> :ok
        end

      _ref ->
        :ok
    end
  end
end
