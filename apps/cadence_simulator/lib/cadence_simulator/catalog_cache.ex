defmodule CadenceSimulator.CatalogCache do
  @moduledoc """
  Compiles each catalog revision once per simulator application lifetime.

  Immutable encoder and dynamics plans live in the BEAM literal area, so streams
  share the plans and keep their own packet sequences and command state.
  """

  use GenServer

  alias CadenceSimulator.{CatalogDatabase, PacketEncoder}
  alias CadenceSimulator.Providers.DatabaseDynamics

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def fetch(opts, provider) do
    with {:ok, content, artifact_name} <- source(opts) do
      kind = if provider == DatabaseDynamics, do: :database, else: :encoder
      key = {__MODULE__, kind, artifact_name, :crypto.hash(:sha256, content)}

      fetch_compiled(key, content)
    end
  end

  defp fetch_compiled(key, content) do
    case :persistent_term.get(key, nil) do
      nil ->
        with :ok <- GenServer.call(__MODULE__, {:compile, key, content}, :infinity) do
          {:ok, :persistent_term.get(key)}
        end

      catalog ->
        {:ok, catalog}
    end
  end

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, MapSet.new()}
  end

  @impl true
  def handle_call({:compile, {_module, kind, artifact_name, _digest} = key, content}, _from, keys) do
    if :persistent_term.get(key, nil) do
      {:reply, :ok, MapSet.put(keys, key)}
    else
      case compile(kind, content, artifact_name) do
        {:ok, catalog} ->
          :persistent_term.put(key, catalog)
          {:reply, :ok, MapSet.put(keys, key)}

        {:error, reason} ->
          {:reply, {:error, reason}, keys}
      end
    end
  end

  @impl true
  def terminate(_reason, keys) do
    Enum.each(keys, &:persistent_term.erase/1)
  end

  defp source(opts) do
    cond do
      content = opts[:definitions_content] ->
        {:ok, content, "simulator-catalog.yaml"}

      path = opts[:definitions_path] ->
        case File.read(path) do
          {:ok, content} -> {:ok, content, Path.basename(path)}
          {:error, reason} -> {:error, {:load_error, path, reason}}
        end

      true ->
        {:error, :missing_definitions}
    end
  end

  defp compile(:database, content, artifact_name) do
    with {:ok, database, document} <-
           CatalogDatabase.load_yaml_with_document(content, %{artifact_name: artifact_name}),
         {:ok, dynamics} <- DatabaseDynamics.prepare_catalog(database),
         {:ok, encoder} <- PacketEncoder.from_document(document) do
      {:ok, {encoder, dynamics}}
    else
      {:error, reason} -> {:error, {:failed_to_load_definitions, reason}}
    end
  end

  defp compile(:encoder, content, _artifact_name) do
    with {:ok, encoder} <- PacketEncoder.load_string(content), do: {:ok, {encoder, nil}}
  end
end
