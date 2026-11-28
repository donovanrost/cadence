defmodule Cadence.Runtime.PartitionOwner.ScidRoutesCacheTest do
  @moduledoc """
  #1078 P5 slice E1b-1: a craft's SCID is edited through the spacecraft API with no activation, and
  a relay's set through a reviewed change, so a partition's routes are read again: a relay's on a
  clock, any other endpoint's on a slow clock and sooner after a batch was refused (the sign a stale
  SCID shows), never on every batch.
  """
  use ExUnit.Case, async: false

  alias Cadence.Protocol.ScidRoutes
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.PartitionOwner.ScidRoutesCache

  @key PartitionKey.new(%{affinity: :source_endpoint, value: "endpoint-1"})
  @activation %{organization_id: "org", mission_id: "mission"}

  defmodule Builder do
    @moduledoc false
    # The craft's SCID and relay set as the test last "edited" them; counts the reads.
    def build(_org, _mission, endpoint) do
      send(:persistent_term.get({__MODULE__, :owner}), {:built, endpoint})
      {scid, origins} = :persistent_term.get({__MODULE__, :craft})
      ScidRoutes.new(endpoint, "sc", scid, origins)
    end
  end

  setup do
    previous = Application.get_env(:cadence, :scid_routes)
    :persistent_term.put({Builder, :owner}, self())
    edit(7, [])

    on_exit(fn ->
      :persistent_term.erase({Builder, :owner})
      :persistent_term.erase({Builder, :craft})

      if previous,
        do: Application.put_env(:cadence, :scid_routes, previous),
        else: Application.delete_env(:cadence, :scid_routes)
    end)
  end

  defp configure(settings),
    do: Application.put_env(:cadence, :scid_routes, [module: Builder] ++ settings)

  defp edit(scid, origins), do: :persistent_term.put({Builder, :craft}, {scid, origins})
  defp refused(frames \\ 1), do: %{scid_check: %{refused: %{99 => frames}}}

  test "a refused batch re-reads the routes after retry_ms, so an edited SCID decodes" do
    configure(refresh_ms: 60_000, idle_refresh_ms: 300_000, retry_ms: 0)
    cache = ScidRoutesCache.build(@activation, @key)
    assert_received {:built, "endpoint-1"}
    assert ScidRoutes.classify(cache.routes, 11) == :mismatch

    # The craft's SCID is fixed (no activation). Nothing was refused yet: the routes are kept.
    edit(11, [])
    assert {%{own_scid: 7}, ^cache} = ScidRoutesCache.current(cache, @activation, @key)
    refute_received {:built, _}

    # The batch with SCID 11 was refused: the next one reads again and decodes.
    cache = ScidRoutesCache.note_refusals(cache, refused())
    {routes, cache} = ScidRoutesCache.current(cache, @activation, @key)

    assert_received {:built, "endpoint-1"}
    assert ScidRoutes.classify(routes, 11) == :direct
    refute cache.refused?
  end

  test "a foreign stream doesn't read on every batch: the retry waits retry_ms" do
    configure(refresh_ms: 60_000, idle_refresh_ms: 300_000, retry_ms: 60_000)
    cache = ScidRoutesCache.build(@activation, @key)
    assert_received {:built, _}

    cache = ScidRoutesCache.note_refusals(cache, refused())
    assert {_routes, ^cache} = ScidRoutesCache.current(cache, @activation, @key)
    refute_received {:built, _}
  end

  test "a non-relay endpoint with nothing refused is only read on the idle clock" do
    configure(refresh_ms: 0, idle_refresh_ms: 300_000, retry_ms: 0)
    cache = ScidRoutesCache.build(@activation, @key)
    assert_received {:built, _}

    for _batch <- 1..20,
        do: assert({_routes, ^cache} = ScidRoutesCache.current(cache, @activation, @key))

    refute_received {:built, _}

    configure(refresh_ms: 0, idle_refresh_ms: 0, retry_ms: 0)
    edit(9, [])
    assert {%{own_scid: 9}, _} = ScidRoutesCache.current(cache, @activation, @key)
  end

  test "a relay's routes are re-read on the relay clock, so an edited set takes effect" do
    configure(refresh_ms: 0, idle_refresh_ms: 300_000, retry_ms: 300_000)
    edit(11, [{"sc-a", 21, :active}])
    cache = ScidRoutesCache.build(@activation, @key)
    assert ScidRoutes.classify(cache.routes, 22) == :mismatch

    edit(11, [{"sc-a", 21, :active}, {"sc-b", 22, :active}])
    {routes, _cache} = ScidRoutesCache.current(cache, @activation, @key)

    assert ScidRoutes.classify(routes, 22) == {:relayed, "sc-b"}
  end

  test "a batch that refused nothing leaves the cache as it was" do
    cache = ScidRoutesCache.build(@activation, @key)

    assert ScidRoutesCache.note_refusals(cache, %{scid_check: %{refused: %{}}}) == cache
    assert ScidRoutesCache.note_refusals(cache, %{scid_check: nil}) == cache
    assert ScidRoutesCache.note_refusals(cache, %{}) == cache
  end

  test "with no module, or a builder that raises, nothing is refused" do
    Application.delete_env(:cadence, :scid_routes)
    refute ScidRoutes.checks?(ScidRoutesCache.build(@activation, @key).routes)

    Application.put_env(:cadence, :scid_routes, module: __MODULE__.Raising)
    refute ScidRoutes.checks?(ScidRoutesCache.build(@activation, @key).routes)
  end

  defmodule Raising do
    @moduledoc false
    def build(_org, _mission, _endpoint), do: raise("registry unavailable")
  end
end
