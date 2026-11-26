defmodule Cadence.ContactPlanning.FleetOptimizer.SelectionIndex do
  @moduledoc false

  alias Cadence.ContactPlanning.FleetOptimizer.Constraints

  @bucket_seconds 3_600
  @max_indexed_buckets 48

  defstruct by_requirement: %{},
            by_spacecraft: %{},
            by_route_spacecraft: %{},
            by_resource: %{},
            by_resource_bucket: %{},
            long_resources: %{},
            provider_counts: %{},
            provider_costs: %{},
            order: %{},
            next_order: 0,
            count: 0,
            known_cost: 0

  @type t :: %__MODULE__{}

  def new, do: %__MODULE__{}

  def add(index, snapshot, requirement) do
    requirement_key = requirement_key(snapshot)
    route_spacecraft = snapshot.route_binding_document["spacecraft_id"]
    resource = Constraints.resource_key(snapshot)
    provider = Constraints.provider_id(snapshot)
    cost = known_cost(snapshot)

    index
    |> Map.update!(:by_requirement, &prepend(&1, requirement_key, snapshot))
    |> Map.update!(:by_spacecraft, &prepend(&1, requirement.spacecraft_id, snapshot))
    |> Map.update!(:by_route_spacecraft, &prepend(&1, route_spacecraft, snapshot))
    |> Map.update!(:by_resource, &prepend(&1, resource, snapshot))
    |> put_resource_buckets(resource, snapshot, :add)
    |> Map.update!(:provider_counts, &Map.update(&1, provider, 1, fn count -> count + 1 end))
    |> Map.update!(:provider_costs, &Map.update(&1, provider, cost, fn sum -> sum + cost end))
    |> Map.update!(
      :order,
      &Map.put(&1, snapshot.contact_opportunity_snapshot_id, index.next_order)
    )
    |> Map.update!(:next_order, &(&1 + 1))
    |> Map.update!(:count, &(&1 + 1))
    |> Map.update!(:known_cost, &(&1 + cost))
  end

  def remove(index, snapshot, requirement) do
    requirement_key = requirement_key(snapshot)
    route_spacecraft = snapshot.route_binding_document["spacecraft_id"]
    resource = Constraints.resource_key(snapshot)
    provider = Constraints.provider_id(snapshot)
    cost = known_cost(snapshot)

    index
    |> Map.update!(:by_requirement, &delete(&1, requirement_key, snapshot))
    |> Map.update!(:by_spacecraft, &delete(&1, requirement.spacecraft_id, snapshot))
    |> Map.update!(:by_route_spacecraft, &delete(&1, route_spacecraft, snapshot))
    |> Map.update!(:by_resource, &delete(&1, resource, snapshot))
    |> put_resource_buckets(resource, snapshot, :remove)
    |> Map.update!(:provider_counts, &Map.update!(&1, provider, fn count -> count - 1 end))
    |> Map.update!(:provider_costs, &Map.update!(&1, provider, fn sum -> sum - cost end))
    |> Map.update!(:order, &Map.delete(&1, snapshot.contact_opportunity_snapshot_id))
    |> Map.update!(:count, &(&1 - 1))
    |> Map.update!(:known_cost, &(&1 - cost))
  end

  def for_requirement(index, requirement),
    do:
      Map.get(index.by_requirement, {requirement.contact_requirement_id, requirement.version}, [])

  def for_spacecraft(index, spacecraft_id),
    do: Map.get(index.by_spacecraft, spacecraft_id, [])

  def for_route_spacecraft(index, spacecraft_id),
    do: Map.get(index.by_route_spacecraft, spacecraft_id, [])

  def overlapping_resource(index, resource, snapshot) do
    overlaps? = &Constraints.overlap?(snapshot, &1)
    long = Map.get(index.long_resources, resource, [])

    case {bucket_keys(resource, snapshot), long} do
      {:long, _} ->
        Enum.filter(Map.get(index.by_resource, resource, []), overlaps?)

      {[key], []} ->
        Enum.filter(Map.get(index.by_resource_bucket, key, []), overlaps?)

      {keys, long} ->
        (Enum.flat_map(keys, &Map.get(index.by_resource_bucket, &1, [])) ++ long)
        |> Enum.filter(overlaps?)
        |> Enum.uniq_by(& &1.contact_opportunity_snapshot_id)
        |> Enum.sort_by(&(-index.order[&1.contact_opportunity_snapshot_id]))
    end
  end

  def provider_count(index, provider), do: Map.get(index.provider_counts, provider, 0)
  def provider_cost(index, provider), do: Map.get(index.provider_costs, provider, 0)

  defp put_resource_buckets(index, resource, snapshot, operation) do
    case bucket_keys(resource, snapshot) do
      :long ->
        Map.update!(index, :long_resources, &update_bucket(&1, resource, snapshot, operation))

      keys ->
        Enum.reduce(keys, index, fn key, index ->
          Map.update!(index, :by_resource_bucket, &update_bucket(&1, key, snapshot, operation))
        end)
    end
  end

  defp update_bucket(map, key, snapshot, :add), do: prepend(map, key, snapshot)
  defp update_bucket(map, key, snapshot, :remove), do: delete(map, key, snapshot)

  defp bucket_keys(resource, snapshot) do
    first = div(DateTime.to_unix(snapshot.starts_at), @bucket_seconds)
    last = div(DateTime.to_unix(snapshot.ends_at) - 1, @bucket_seconds)

    if last - first >= @max_indexed_buckets do
      :long
    else
      Enum.map(first..last, &{resource, &1})
    end
  end

  defp prepend(map, key, snapshot), do: Map.update(map, key, [snapshot], &[snapshot | &1])

  defp delete(map, key, snapshot) do
    id = snapshot.contact_opportunity_snapshot_id

    Map.update!(
      map,
      key,
      &Enum.reject(&1, fn current -> current.contact_opportunity_snapshot_id == id end)
    )
  end

  defp requirement_key(snapshot),
    do: {snapshot.contact_requirement_id, snapshot.contact_requirement_version}

  defp known_cost(snapshot) do
    case Constraints.cost(snapshot) do
      {:known, micros, _currency} -> micros
      :unknown -> 0
    end
  end
end
