defmodule Cadence.Telemetry.EffectiveSelection do
  @moduledoc """
  Applies read-side telemetry selection using durable identity-state decisions.

  Physical observation rows keep their original provenance. Canonical read
  models overlay the current observation identity state so an operator/system
  decision can promote a row without mutating immutable history.
  """

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.SelectionPolicy

  @noncanonical_decisions ["mark_conflict", "mark_superseded", "mark_advisory"]

  @spec selected_samples([Sample.t()], [map() | struct()], keyword()) :: [Sample.t()]
  def selected_samples(samples, identity_states, opts)
      when is_list(samples) and is_list(identity_states) and is_list(opts) do
    case SelectionPolicy.validity_state_filter(opts) do
      :canonical -> canonical_samples(samples, identity_states)
      _other -> SelectionPolicy.selected_samples(samples, opts)
    end
  end

  @spec selected_sample(Sample.t(), [map() | struct()], keyword()) :: Sample.t() | nil
  def selected_sample(%Sample{} = sample, identity_states, opts)
      when is_list(identity_states) and is_list(opts) do
    selected_samples([sample], identity_states, opts)
    |> List.first()
  end

  defp canonical_samples(samples, identity_states) do
    identity_index = identity_index(identity_states)

    samples
    |> Enum.flat_map(fn %Sample{} = sample ->
      case effective_canonical_sample(sample, identity_index) do
        %Sample{} = effective_sample -> [effective_sample]
        nil -> []
      end
    end)
  end

  defp identity_index(identity_states) do
    decision_states = Enum.filter(identity_states, &explicit_decision?/1)

    canonical_states_by_sample_id =
      decision_states
      |> Enum.filter(&canonical_state_selectable?/1)
      |> Map.new(&{attr(&1, :canonical_sample_id), &1})

    known_identity_ids =
      decision_states
      |> Enum.map(&attr(&1, :observation_identity_id))
      |> Enum.filter(&present?/1)
      |> MapSet.new()

    %{
      canonical_states_by_sample_id: canonical_states_by_sample_id,
      known_identity_ids: known_identity_ids
    }
  end

  defp effective_canonical_sample(%Sample{} = sample, identity_index) do
    with nil <- Map.get(identity_index.canonical_states_by_sample_id, sample.sample_id),
         true <- known_identity_sample?(sample, identity_index) do
      nil
    else
      identity_state when is_map(identity_state) or is_struct(identity_state) ->
        canonical_effective_sample(sample, identity_state)

      false ->
        if SelectionPolicy.selected_sample?(sample, []), do: sample
    end
  end

  defp known_identity_sample?(%Sample{} = sample, identity_index) do
    case storage_provenance_value(sample, :observation_identity_id) do
      nil -> false
      identity_id -> MapSet.member?(identity_index.known_identity_ids, identity_id)
    end
  end

  defp canonical_state_selectable?(identity_state) do
    present?(attr(identity_state, :canonical_sample_id)) and
      not exclusion_decision?(identity_state)
  end

  defp explicit_decision?(identity_state) do
    identity_state
    |> decision_name()
    |> present?()
  end

  defp exclusion_decision?(identity_state) do
    case decision_name(identity_state) do
      decision when decision in @noncanonical_decisions -> true
      _other -> false
    end
  end

  defp decision_name(identity_state) do
    identity_state
    |> attr(:payload)
    |> ensure_map()
    |> map_value(:decision)
    |> ensure_map()
    |> map_value(:decision)
  end

  defp canonical_effective_sample(%Sample{} = sample, identity_state) do
    storage =
      sample
      |> storage_provenance()
      |> Map.merge(%{
        "observation_identity_id" => attr(identity_state, :observation_identity_id),
        "observation_id" => attr(identity_state, :canonical_observation_id),
        "validity_state" => "canonical",
        "revision" => attr(identity_state, :canonical_revision),
        "decision_reason" => attr(identity_state, :decision_reason)
      })

    provenance =
      sample.provenance
      |> ensure_map()
      |> Map.put("storage", storage)

    %Sample{sample | provenance: provenance}
  end

  defp storage_provenance_value(%Sample{} = sample, key) do
    sample
    |> storage_provenance()
    |> map_value(key)
  end

  defp storage_provenance(%Sample{provenance: provenance}) do
    provenance
    |> ensure_map()
    |> map_value(:storage)
    |> ensure_map()
  end

  defp attr(%_{} = struct, key), do: struct |> Map.from_struct() |> attr(key)

  defp attr(map, key) when is_map(map), do: map_value(map, key)
  defp attr(_value, _key), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp present?(value), do: is_binary(value) and value != ""
end
