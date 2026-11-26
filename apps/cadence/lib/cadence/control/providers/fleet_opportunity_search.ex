defmodule Cadence.Control.Providers.FleetOpportunitySearch do
  @moduledoc false

  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Control.Providers
  alias Cadence.GroundNetworks.Opportunity

  @spacecraft_per_batch 16

  @doc """
  Searches exact windows using the provider's declared spacecraft limit. Split
  a truncated multi-spacecraft page until every
  spacecraft has a complete page or can get its normal single-spacecraft limit.
  """
  def search(routes_by_window, providers, concurrency, opts) do
    {valid, invalid} =
      Enum.split_with(routes_by_window, fn {{starts_at, ends_at}, _routes} ->
        ProviderScheduling.validate_window(starts_at, ends_at, opts) == :ok
      end)

    configured =
      valid
      |> Enum.flat_map(fn {_window, routes} -> Enum.map(routes, &provider_key/1) end)
      |> Enum.uniq()
      |> Map.new(fn key -> {key, Providers.prepare_search(Map.fetch!(providers, key), opts)} end)

    batches =
      Enum.flat_map(valid, fn {window, routes} ->
        routes
        |> Enum.group_by(&{provider_key(&1), &1.service_profile_ref})
        |> Enum.flat_map(&prepare_group(&1, configured, opts, window))
      end)

    batches
    |> Task.async_stream(&search_group(&1, opts),
      max_concurrency: concurrency,
      timeout: :infinity
    )
    |> Enum.zip_reduce(batches, invalid_responses(invalid, opts), &receive_group/3)
  end

  defp invalid_responses(invalid, opts) do
    Map.new(invalid, fn {{starts_at, ends_at} = window, routes} ->
      error = ProviderScheduling.validate_window(starts_at, ends_at, opts)
      {window, Map.new(routes, &{&1.route_key, error})}
    end)
  end

  defp provider_key(route), do: {route.provider_id, route.provider_version}

  defp prepare_group({{key, _service}, routes}, configured, opts, window) do
    search = Map.fetch!(configured, key)
    {batch_size, page_size} = limits(search, opts)

    routes
    |> Enum.group_by(& &1.provider_spacecraft_ref)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.chunk_every(batch_size)
    |> Enum.map(&{window, search, &1, page_size})
  end

  defp limits(
         {:ok,
          %{
            capabilities: %{
              search: %{spacecraft_batch_limit: spacecraft_limit, page_size_limit: page_size}
            }
          }},
         _opts
       )
       when spacecraft_limit > 1 do
    {min(@spacecraft_per_batch, spacecraft_limit), page_size}
  end

  defp limits(_search, opts), do: {1, ProviderScheduling.result_limit(opts)}

  defp search_group({_window, {:error, reason}, spacecraft, _page_size}, _opts) do
    project_error(spacecraft, {:error, reason})
  end

  defp search_group({{from, to}, {:ok, search}, spacecraft, page_size}, opts) do
    limit = ProviderScheduling.result_limit(opts)
    search_page(search, spacecraft, page_size, from, to, limit)
  end

  defp search_page(search, [{ref, routes}], _page_size, from, to, limit) do
    case request(search, [ref], hd(routes), from, to, limit) do
      {:ok, response} -> project_results(routes, response, from, to, limit)
      error -> project_error([{ref, routes}], error)
    end
  end

  defp search_page(search, spacecraft, page_size, from, to, limit) do
    {_ref, [route | _]} = hd(spacecraft)
    refs = Enum.map(spacecraft, &elem(&1, 0))

    with {:ok, response} <- request(search, refs, route, from, to, page_size),
         {:ok, by_spacecraft} <- index_complete_page(response, refs) do
      project_page(spacecraft, by_spacecraft, response, from, to, min(limit, page_size))
    else
      :incomplete -> split_page(search, spacecraft, page_size, from, to, limit)
      error -> project_error(spacecraft, error)
    end
  end

  defp index_complete_page(%{data: data, truncated: false, next_cursor: nil}, refs)
       when is_list(data) do
    if Enum.all?(data, &match?(%Opportunity{}, &1)) do
      by_spacecraft = Enum.group_by(data, & &1.spacecraft_ref)

      if Enum.all?(Map.keys(by_spacecraft), &(&1 in refs)),
        do: {:ok, by_spacecraft},
        else: :incomplete
    else
      :incomplete
    end
  end

  defp index_complete_page(_response, _refs), do: :incomplete

  defp project_page(spacecraft, by_spacecraft, response, from, to, limit) do
    Enum.flat_map(spacecraft, fn {ref, routes} ->
      opportunities = Map.get(by_spacecraft, ref, [])

      slice = %{
        response
        | data: Enum.take(opportunities, limit),
          truncated: length(opportunities) > limit
      }

      project_results(routes, slice, from, to, limit)
    end)
  end

  defp split_page(search, spacecraft, page_size, from, to, limit) do
    {left, right} = Enum.split(spacecraft, div(length(spacecraft), 2))

    search_page(search, left, page_size, from, to, limit) ++
      search_page(search, right, page_size, from, to, limit)
  end

  defp request(search, refs, route, from, to, page_size) do
    search.request.(%{
      "spacecraft_refs" => refs,
      "ground_station_refs" => [],
      "service_profile_ref" => route.service_profile_ref["id"],
      "starts_at" => DateTime.to_iso8601(from),
      "ends_at" => DateTime.to_iso8601(to),
      "page_size" => page_size,
      "cursor" => nil
    })
  end

  defp project_results(routes, response, from, to, limit) do
    Enum.map(
      routes,
      &{&1.route_key, ProviderScheduling.search_result(response, &1, from, to, limit)}
    )
  end

  defp project_error(spacecraft, error) do
    Enum.flat_map(spacecraft, fn {_ref, routes} ->
      Enum.map(routes, &{&1.route_key, error})
    end)
  end

  defp receive_group({:ok, results}, {window, _search, _spacecraft, _page_size}, acc) do
    collect_results(acc, window, results)
  end

  defp receive_group({:exit, _reason}, {window, _search, spacecraft, _page_size}, acc) do
    collect_results(acc, window, project_error(spacecraft, {:error, :search_worker_exit}))
  end

  defp collect_results(acc, window, results) do
    Map.update(acc, window, Map.new(results), &Enum.into(results, &1))
  end
end
