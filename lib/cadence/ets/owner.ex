defmodule Cadence.ETS.Owner do
  @moduledoc false

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  def ensure_named_table(table_name, options) when is_atom(table_name) and is_list(options) do
    GenServer.call(__MODULE__, {:ensure_named_table, table_name, options})
  end

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:ensure_named_table, table_name, options}, _from, state) do
    {:reply, do_ensure_named_table(table_name, options), state}
  end

  defp do_ensure_named_table(table_name, options) do
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, options)
        :ok

      _ref ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
