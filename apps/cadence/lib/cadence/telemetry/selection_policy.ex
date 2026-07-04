defmodule Cadence.Telemetry.SelectionPolicy do
  @moduledoc """
  Normalizes telemetry read selection policy across latest and history reads.

  The default operational view is `:canonical`: only canonical observations feed
  ordinary dashboard/latest reads. Broader views may inspect all recorded
  revisions, but callers must opt into that behavior explicitly.
  """

  alias Cadence.Telemetry.Sample

  @type view :: :canonical | :as_recorded | :all_revisions | :recomputed
  @type validity_state :: :canonical | :duplicate | :conflict | :superseded | :advisory

  @views [:canonical, :as_recorded, :all_revisions, :recomputed]
  @validity_states [:canonical, :duplicate, :conflict, :superseded, :advisory]

  @spec view(keyword()) :: view()
  def view(opts) when is_list(opts) do
    opts
    |> first_present([:selection_view, :view, :data_management_view], :canonical)
    |> normalize_view()
  end

  @spec validity_state_filter(keyword()) :: validity_state() | nil
  def validity_state_filter(opts) when is_list(opts) do
    case Keyword.fetch(opts, :validity_state) do
      {:ok, value} ->
        normalize_optional_validity_state(value)

      :error ->
        default_validity_state_filter(view(opts))
    end
  end

  @spec query_opts(keyword()) :: keyword()
  def query_opts(opts) when is_list(opts) do
    case validity_state_filter(opts) do
      nil -> Keyword.delete(opts, :validity_state)
      validity_state -> Keyword.put(opts, :validity_state, validity_state)
    end
  end

  @spec selected_sample?(Sample.t(), keyword()) :: boolean()
  def selected_sample?(%Sample{} = sample, opts) when is_list(opts) do
    case validity_state_filter(opts) do
      nil ->
        true

      :canonical ->
        sample_validity_state(sample) in [nil, :canonical]

      validity_state ->
        sample_validity_state(sample) == validity_state
    end
  end

  @spec selected_samples([Sample.t()], keyword()) :: [Sample.t()]
  def selected_samples(samples, opts) when is_list(samples) and is_list(opts) do
    Enum.filter(samples, &selected_sample?(&1, opts))
  end

  @spec sample_validity_state(Sample.t()) :: validity_state() | nil
  def sample_validity_state(%Sample{provenance: provenance}) when is_map(provenance) do
    provenance
    |> storage_provenance()
    |> provenance_value(:validity_state)
    |> normalize_optional_validity_state()
  end

  def sample_validity_state(%Sample{}), do: nil

  defp default_validity_state_filter(:canonical), do: :canonical
  defp default_validity_state_filter(_view), do: nil

  defp normalize_view(value) when value in @views, do: value

  defp normalize_view(value) when is_binary(value) do
    Enum.find(@views, &(Atom.to_string(&1) == value)) || :canonical
  end

  defp normalize_view(_value), do: :canonical

  defp normalize_optional_validity_state(nil), do: nil
  defp normalize_optional_validity_state(value) when value in @validity_states, do: value

  defp normalize_optional_validity_state(value) when is_binary(value) do
    Enum.find(@validity_states, &(Atom.to_string(&1) == value))
  end

  defp normalize_optional_validity_state(_value), do: nil

  defp storage_provenance(provenance) do
    provenance_value(provenance, :storage) || %{}
  end

  defp provenance_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp provenance_value(_value, _key), do: nil

  defp first_present(opts, keys, default) do
    Enum.find_value(keys, default, fn key ->
      case Keyword.get(opts, key) do
        nil -> false
        "" -> false
        value -> value
      end
    end)
  end
end
