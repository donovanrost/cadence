defmodule Cadence.Telemetry.PhysicalSampleQuery do
  @moduledoc """
  Exact physical sample identity and the already-authorized read constraints.

  This is a server-side storage contract, not a browser query or authorization
  grant. Its caller must authorize the mission and resolve the source binding.
  Source identity is mandatory; selection views and history limits cannot turn
  this lookup into a latest/canonical/history read.
  """

  alias Cadence.Telemetry.Sample

  @identities [
    :organization_id,
    :mission_id,
    :point_id,
    :sample_id,
    :data_source_id,
    :source_binding_id
  ]
  @required @identities ++ [:realm]
  @optional_identities [:spacecraft_id, :replay_run_id]
  @times [:receipt_time, :from_receipt_time, :to_receipt_time, :from_observed_at, :to_observed_at]
  @optional @optional_identities ++ @times ++ [:source_endpoint_ids]
  @realms ["flight", "rehearsal", "replay", "simulation"]
  @enforce_keys @required
  defstruct @required ++ @optional

  @type t :: %__MODULE__{
          organization_id: binary(),
          mission_id: binary(),
          point_id: binary(),
          sample_id: binary(),
          data_source_id: binary(),
          source_binding_id: binary(),
          realm: binary(),
          spacecraft_id: binary() | nil,
          replay_run_id: binary() | nil,
          source_endpoint_ids: [binary()] | nil,
          receipt_time: DateTime.t() | nil,
          from_receipt_time: DateTime.t() | nil,
          to_receipt_time: DateTime.t() | nil,
          from_observed_at: DateTime.t() | nil,
          to_observed_at: DateTime.t() | nil
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_physical_sample_query}
  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    attrs = Map.update(attrs, :realm, nil, &realm/1)

    if valid_attrs?(attrs) do
      {:ok, struct!(__MODULE__, attrs)}
    else
      {:error, :invalid_physical_sample_query}
    end
  rescue
    _ -> {:error, :invalid_physical_sample_query}
  end

  def new(_attrs), do: {:error, :invalid_physical_sample_query}

  @spec validate(t()) :: :ok | {:error, :invalid_physical_sample_query}
  def validate(%__MODULE__{} = query) do
    case new(Map.from_struct(query)) do
      {:ok, ^query} -> :ok
      _ -> {:error, :invalid_physical_sample_query}
    end
  end

  def validate(_query), do: {:error, :invalid_physical_sample_query}

  @doc "Checks the returned row using the backend's authoritative tenant identity."
  @spec matches?(t(), Sample.t(), binary() | nil) :: boolean()
  def matches?(%__MODULE__{} = query, %Sample{} = sample, organization_id) do
    query.organization_id == organization_id and
      query.mission_id == sample.mission_id and query.point_id == sample.point_id and
      query.sample_id == sample.sample_id and
      (is_nil(query.spacecraft_id) or query.spacecraft_id == sample.spacecraft_id) and
      source_matches?(sample, query) and
      time_matches?(sample, query)
  rescue
    _ -> false
  end

  def matches?(_query, _sample, _organization_id), do: false

  defp valid_attrs?(attrs) do
    Enum.all?(Map.keys(attrs), &(&1 in (@required ++ @optional))) and
      valid_identity_attrs?(attrs) and endpoints?(Map.get(attrs, :source_endpoint_ids)) and
      valid_time_attrs?(attrs)
  end

  defp valid_identity_attrs?(attrs) do
    Enum.all?(@identities, &identity?(Map.get(attrs, &1))) and
      Enum.all?(@optional_identities, &optional_identity?(Map.get(attrs, &1))) and
      Map.get(attrs, :realm) in @realms and replay_context?(attrs)
  end

  defp valid_time_attrs?(attrs) do
    Enum.all?(@times, &datetime?(Map.get(attrs, &1))) and
      ordered?(attrs, :from_receipt_time, :to_receipt_time) and
      ordered?(attrs, :from_observed_at, :to_observed_at)
  end

  defp identity?(value) when is_binary(value) do
    byte_size(value) in 1..256 and String.valid?(value) and
      not String.match?(value, ~r/[\x00-\x1f\x7f]/u)
  end

  defp identity?(_value), do: false
  defp optional_identity?(nil), do: true
  defp optional_identity?(value), do: identity?(value)

  defp realm(value) when value in [:flight, :rehearsal, :replay, :simulation],
    do: Atom.to_string(value)

  defp realm(value), do: value
  defp replay_context?(%{realm: "replay"} = attrs), do: identity?(Map.get(attrs, :replay_run_id))
  defp replay_context?(attrs), do: is_nil(Map.get(attrs, :replay_run_id))

  defp endpoints?(nil), do: true

  defp endpoints?(ids) when is_list(ids),
    do: length(ids) in 1..100 and Enum.all?(ids, &identity?/1) and Enum.uniq(ids) == ids

  defp endpoints?(_ids), do: false

  defp datetime?(nil), do: true

  defp datetime?(%DateTime{calendar: Calendar.ISO} = value) do
    case DateTime.from_iso8601(DateTime.to_iso8601(value)) do
      {:ok, parsed, _offset} -> DateTime.compare(value, parsed) == :eq
      _ -> false
    end
  end

  defp datetime?(_value), do: false

  defp ordered?(attrs, from, to) do
    case {Map.get(attrs, from), Map.get(attrs, to)} do
      {%DateTime{} = first, %DateTime{} = last} -> DateTime.compare(first, last) != :gt
      _ -> true
    end
  end

  defp source_matches?(sample, query) do
    storage = value(sample.provenance, :storage)
    binding = value(storage, :binding_id) || value(storage, :source_binding_id)

    query.realm == realm(value(storage, :realm)) and
      query.data_source_id == value(storage, :data_source_id) and
      query.source_binding_id == binding and
      query.replay_run_id == value(storage, :replay_run_id) and
      (is_nil(query.source_endpoint_ids) or
         value(storage, :source_endpoint_id) in query.source_endpoint_ids)
  end

  defp value(map, key) when is_map(map), do: Map.get(map, Atom.to_string(key), Map.get(map, key))
  defp value(_map, _key), do: nil

  defp time_matches?(sample, query) do
    observed_at = sample.generation_time || sample.receipt_time

    not is_nil(sample.receipt_time) and datetime?(sample.receipt_time) and
      datetime?(sample.generation_time) and
      equal_time?(sample.receipt_time, query.receipt_time) and
      within?(sample.receipt_time, query.from_receipt_time, query.to_receipt_time) and
      within?(observed_at, query.from_observed_at, query.to_observed_at)
  end

  defp equal_time?(_actual, nil), do: true
  defp equal_time?(actual, expected), do: DateTime.compare(actual, expected) == :eq

  defp within?(actual, from, to) do
    (is_nil(from) or DateTime.compare(actual, from) != :lt) and
      (is_nil(to) or DateTime.compare(actual, to) != :gt)
  end
end
