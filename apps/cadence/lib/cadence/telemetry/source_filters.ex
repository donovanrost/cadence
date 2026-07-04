defmodule Cadence.Telemetry.SourceFilters do
  @moduledoc """
  Normalizes telemetry source filters shared by read-side stores.

  Public callers use `:source_binding_id` in dashboard-facing contracts while
  storage layers persist the same identity as `:binding_id`.
  """

  alias Cadence.Telemetry.Sample

  @type t :: %{
          optional(:realm) => binary(),
          optional(:data_source_id) => binary(),
          optional(:binding_id) => binary(),
          optional(:replay_run_id) => binary(),
          optional(:source_endpoint_ids) => [binary()]
        }

  @spec normalize(keyword()) :: t()
  def normalize(opts) when is_list(opts) do
    %{}
    |> put_if_present(:realm, Keyword.get(opts, :realm))
    |> put_if_present(:data_source_id, Keyword.get(opts, :data_source_id))
    |> put_if_present(
      :binding_id,
      Keyword.get(opts, :binding_id) || Keyword.get(opts, :source_binding_id)
    )
    |> put_if_present(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> put_source_endpoint_ids(opts)
  end

  @spec any?(keyword()) :: boolean()
  def any?(opts) when is_list(opts), do: map_size(normalize(opts)) > 0

  @spec sample_matches?(Sample.t(), keyword()) :: boolean()
  def sample_matches?(%Sample{} = sample, opts) when is_list(opts) do
    storage = storage_provenance(sample)
    filters = normalize(opts)

    matches?(storage, :realm, Map.get(filters, :realm)) and
      matches?(storage, :data_source_id, Map.get(filters, :data_source_id)) and
      matches_binding?(storage, Map.get(filters, :binding_id)) and
      matches?(storage, :replay_run_id, Map.get(filters, :replay_run_id)) and
      matches_source_endpoint?(storage, Map.get(filters, :source_endpoint_ids))
  end

  @spec filter_samples([Sample.t()], keyword()) :: [Sample.t()]
  def filter_samples(samples, opts) when is_list(samples) and is_list(opts) do
    Enum.filter(samples, &sample_matches?(&1, opts))
  end

  @spec binding_id(keyword()) :: binary() | nil
  def binding_id(opts) when is_list(opts) do
    opts
    |> normalize()
    |> Map.get(:binding_id)
  end

  @spec replay_run_id(keyword()) :: binary() | nil
  def replay_run_id(opts) when is_list(opts) do
    opts
    |> normalize()
    |> Map.get(:replay_run_id)
  end

  @spec sample_identity(Sample.t()) :: %{
          realm: binary(),
          data_source_id: binary(),
          binding_id: binary(),
          replay_run_id: binary()
        }
  def sample_identity(%Sample{} = sample) do
    storage = storage_provenance(sample)

    %{
      realm: source_value(storage, :realm) || "",
      data_source_id: source_value(storage, :data_source_id) || "",
      binding_id:
        source_value(storage, :binding_id) || source_value(storage, :source_binding_id) || "",
      replay_run_id: source_value(storage, :replay_run_id) || ""
    }
  end

  @spec sample_key(Sample.t()) :: {binary(), binary(), binary()}
  def sample_key(%Sample{} = sample) do
    identity = sample_identity(sample)
    {identity.realm, identity.data_source_id, identity.binding_id}
  end

  defp put_if_present(filters, _key, nil), do: filters
  defp put_if_present(filters, _key, ""), do: filters
  defp put_if_present(filters, key, value), do: Map.put(filters, key, to_string(value))

  defp put_source_endpoint_ids(filters, opts) do
    opts
    |> Keyword.get(:source_endpoint_ids, Keyword.get(opts, :source_endpoint_id))
    |> source_endpoint_ids()
    |> case do
      [] -> filters
      ids -> Map.put(filters, :source_endpoint_ids, ids)
    end
  end

  defp source_endpoint_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&source_endpoint_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp source_endpoint_ids(nil), do: []
  defp source_endpoint_ids(id), do: source_endpoint_ids([id])

  defp source_endpoint_id(id) when is_binary(id) do
    id = String.trim(id)
    if id == "", do: nil, else: id
  end

  defp source_endpoint_id(id) when is_atom(id) and not is_nil(id),
    do: id |> Atom.to_string() |> source_endpoint_id()

  defp source_endpoint_id(_id), do: nil

  defp source_value(storage, key) do
    case provenance_value(storage, key) do
      nil -> nil
      "" -> nil
      value -> to_string(value)
    end
  end

  defp storage_provenance(%Sample{provenance: provenance}) when is_map(provenance) do
    provenance_value(provenance, :storage) || %{}
  end

  defp storage_provenance(%Sample{}), do: %{}

  defp matches?(_storage, _key, nil), do: true

  defp matches?(storage, key, expected) do
    storage
    |> provenance_value(key)
    |> compare(expected)
  end

  defp matches_binding?(_storage, nil), do: true

  defp matches_binding?(storage, expected) do
    (provenance_value(storage, :binding_id) || provenance_value(storage, :source_binding_id))
    |> compare(expected)
  end

  defp matches_source_endpoint?(_storage, nil), do: true
  defp matches_source_endpoint?(_storage, []), do: true

  defp matches_source_endpoint?(storage, expected_ids) when is_list(expected_ids) do
    storage
    |> provenance_value(:source_endpoint_id)
    |> case do
      nil -> false
      actual -> to_string(actual) in expected_ids
    end
  end

  defp compare(nil, _expected), do: false
  defp compare(actual, expected), do: to_string(actual) == expected

  defp provenance_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp provenance_value(_value, _key), do: nil
end
