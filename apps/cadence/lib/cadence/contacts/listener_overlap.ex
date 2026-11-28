defmodule Cadence.Contacts.ListenerOverlap do
  @moduledoc """
  U58 (b), #361: a pass that will lose its start because another pass of the mission holds a
  station listener that takes one connection at a time. It's flagged before it costs telemetry,
  on the plan, Book a pass offers and booked passes. Advisory only: booking is never refused.

  It uses the runtime's own rule, not a copy (domain):
  - **Which listeners.** A path's listen bindings (`Comms.ListenClaims.endpoint/1`: listen mode,
    a fixed port) that bind their own socket (`ProviderAdapters.TCPSocket.own_listener?/2`). A
    shared-listener downlink (#87) registers with the profile's acceptor and never contends.
  - **When two collide.** `ListenClaims.overlaps?/2`: the same port, and the same host or a
    wildcard.
  - **Across missions it can't happen.** The port is the node's, but `ListenClaims` refuses
    another mission's listen endpoint at save (`guard/3`) and at start (`check_paths/2`), so only
    passes of one mission can contend. Nothing outside the mission is named.
  - **The interval.** The runtime binds when the scheduler starts the contact (at `starts_at`;
    no lead), and releases when its runtime stops at `ends_at`. The settler then retries a pass
    that couldn't start (`Scheduler.retry_starts/1`), so the later pass binds as the earlier one
    lets go.
  - **The loser.** The later start loses, from its start to the earlier pass's end, capped at its
    own end. On an equal start the runtime's winner is a race, so both read `loses: "either"`.

  `overlaps/1` takes passes `%{id, starts_at, ends_at, listeners}` (listeners from `listeners/1`)
  and answers, per id, nil or the overlap costing it the most seconds:
  `%{with: other_id, seconds | nil, loses: "this" | "other" | "either", direction, listener:
  %{host, port}, count}`. It names the pass's OWN loss first (`this`, then `either`, most seconds),
  and only when it loses nothing the costliest it causes (`other`). `count` is how many other
  passes it overlaps (1 when single). `seconds` is nil when neither pass has an end.
  """

  alias Cadence.Comms.ListenClaims
  alias Cadence.Contacts.{ContactRuntimeConfig, PathTemplateStore, ScheduledContact}
  alias Cadence.ProviderAdapters.TCPSocket

  @type listener :: %{host: binary(), port: pos_integer(), direction: :uplink | :downlink}
  @type pass :: %{
          required(:id) => term(),
          required(:starts_at) => DateTime.t(),
          required(:ends_at) => DateTime.t() | nil,
          required(:listeners) => [listener()],
          optional(atom()) => term()
        }

  @doc "The own listeners a pass's paths bind (`[%{host, port, direction}]`, unique)."
  @spec listeners([map()]) :: [listener()]
  def listeners(paths) when is_list(paths) do
    for path <- paths,
        binding <- Map.get(path, :provider_bindings) || [],
        configuration = Map.get(binding, :configuration),
        endpoint = ListenClaims.endpoint(configuration),
        endpoint != nil,
        direction = Map.get(path, :direction),
        TCPSocket.own_listener?(configuration, direction),
        uniq: true,
        do: Map.put(endpoint, :direction, direction)
  end

  @doc """
  `overlaps/1` for booked passes: each scheduled contact's paths resolved as the runtime resolves
  them (`ContactRuntimeConfig.resolve_paths/1`; the runtime starts every path of a contact, so
  every path's listeners count). A contact whose paths can't be resolved has no listeners here.
  Keyed by `scheduled_contact_id`.
  """
  @spec for_scheduled([ScheduledContact.t()]) :: %{binary() => map() | nil}
  def for_scheduled(contacts) when is_list(contacts) do
    listeners = scheduled_listeners_by_id(contacts)

    contacts
    |> Enum.map(
      &%{
        id: &1.scheduled_contact_id,
        starts_at: &1.starts_at,
        ends_at: &1.ends_at,
        listeners: listeners[&1.scheduled_contact_id]
      }
    )
    |> overlaps()
  end

  @doc """
  `scheduled_listeners/1` for many contacts, resolved once per distinct route (api-ops): contacts
  booked on one route share their link-assignment refs, template refs and inline paths, and
  that's all a listener depends on (`resolve_paths/1`'s per-booking change is the uplink
  resource id, never the host, port or mode). `%{scheduled_contact_id => listeners}`.
  """
  @spec scheduled_listeners_by_id([ScheduledContact.t()]) :: %{binary() => [listener()]}
  def scheduled_listeners_by_id(contacts) do
    routes = contacts |> Enum.group_by(&route_key/1) |> Map.values()
    resolved = routes |> Enum.map(&hd/1) |> ContactRuntimeConfig.resolve_paths_many()

    for [first | _] = same <- routes,
        listeners = resolved_listeners(Map.fetch!(resolved, first)),
        contact <- same,
        into: %{},
        do: {contact.scheduled_contact_id, listeners}
  end

  defp route_key(%ScheduledContact{} = c),
    do:
      {c.organization_id, c.mission_id, c.link_assignment_refs, c.path_template_ids,
       c.path_template_refs, c.paths}

  @doc """
  `template_listeners/4` for many `{template_id, version}` refs, each distinct ref resolved once:
  `%{{template_id, version} => listeners}`.
  """
  @spec template_listeners_by_ref(binary(), binary(), [{term(), term()}]) :: %{
          {term(), term()} => [listener()]
        }
  def template_listeners_by_ref(organization_id, mission_id, refs) do
    refs
    |> Enum.uniq()
    |> Map.new(fn {id, version} = ref ->
      {ref, template_listeners(organization_id, mission_id, id, version)}
    end)
  end

  @doc "A booked pass's own listeners, its paths resolved as the runtime resolves them."
  @spec scheduled_listeners(ScheduledContact.t()) :: [listener()]
  def scheduled_listeners(%ScheduledContact{} = contact) do
    contact |> ContactRuntimeConfig.resolve_paths() |> resolved_listeners()
  end

  defp resolved_listeners({:ok, paths}), do: listeners(paths)
  defp resolved_listeners({:error, _unresolvable}), do: []

  @doc """
  A planned pass's own listeners: its route's path template resolved as a booking's would be
  (`PathTemplateStore.fetch_ref/3` then `resolve/1`, what `ContactRuntimeConfig` does for a
  template ref). `[]` when the route names no template, or it can't be resolved.
  """
  @spec template_listeners(binary(), binary(), binary() | nil, pos_integer() | nil) :: [
          listener()
        ]
  def template_listeners(organization_id, mission_id, template_id, version)
      when is_binary(template_id) and is_integer(version) do
    ref = %{"path_template_id" => template_id, "version" => version}

    with {:ok, template} <- PathTemplateStore.fetch_ref(organization_id, mission_id, ref),
         {:ok, path} <- PathTemplateStore.resolve(template) do
      listeners([path])
    else
      _unresolvable -> []
    end
  end

  def template_listeners(_organization_id, _mission_id, _template_id, _version), do: []

  @doc """
  Per pass id, nil or its named listener overlap (see the moduledoc). A sweep, not all pairs
  (api-ops): passes are grouped by listen port (a collision needs the same port), sorted by
  start, and each is paired only with passes still open when it starts.
  """
  @spec overlaps([pass()]) :: %{term() => map() | nil}
  def overlaps(passes) when is_list(passes) do
    found =
      passes
      |> Enum.filter(&(&1.listeners != []))
      |> candidate_pairs()
      |> Enum.flat_map(&pair_entries/1)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Map.new(passes, fn pass ->
      {pass.id, found |> Map.get(pass.id, []) |> named()}
    end)
  end

  # Unique {earlier, later} pairs whose windows can overlap on a shared port.
  defp candidate_pairs(passes) do
    passes
    |> Enum.flat_map(fn pass ->
      pass.listeners |> Enum.map(& &1.port) |> Enum.uniq() |> Enum.map(&{&1, pass})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.values()
    |> Enum.flat_map(&sweep/1)
    |> Enum.uniq_by(fn {a, b} -> {a.id, b.id} end)
  end

  defp sweep(group) do
    group
    |> Enum.sort_by(& &1.starts_at, DateTime)
    |> Enum.reduce({[], []}, fn pass, {open, pairs} ->
      still_open = Enum.filter(open, &open_at?(&1, pass.starts_at))
      {[pass | still_open], Enum.map(still_open, &{&1, pass}) ++ pairs}
    end)
    |> elem(1)
  end

  defp open_at?(%{ends_at: nil}, _at), do: true
  defp open_at?(%{ends_at: ends_at}, at), do: DateTime.compare(ends_at, at) == :gt

  # Each pair's colliding listeners, once, as an entry for each side.
  defp pair_entries({a, b}) do
    for listener <- a.listeners,
        Enum.any?(b.listeners, &ListenClaims.overlaps?(&1, listener)),
        {pass, other} <- [{a, b}, {b, a}],
        overlap = contend(pass, other),
        overlap != nil,
        do:
          {pass.id,
           Map.merge(overlap, %{
             with: other.id,
             direction: listener.direction,
             listener: Map.take(listener, [:host, :port])
           })}
  end

  defp named([]), do: nil

  defp named(list) do
    count = list |> Enum.map(& &1.with) |> Enum.uniq() |> length()
    list |> named_first() |> Map.put(:count, count)
  end

  # The pass's OWN loss first (domain, fe-ops): the costliest overlap where it loses ("this",
  # then "either"); only when it loses nothing, the costliest it causes ("other"). An
  # unmeasurable loss (nil seconds) counts as the costliest.
  defp named_first(list) do
    own = Enum.filter(list, &(&1.loses in ["this", "either"]))
    {pool, rank} = if own == [], do: {list, & &1}, else: {own, &own_rank/1}
    Enum.max_by(pool, &{rank.(&1.loses), &1.seconds || :infinity})
  end

  defp own_rank("this"), do: 1
  defp own_rank(_either), do: 0

  # nil when the two windows don't overlap (or neither ends, so nothing is measurable).
  defp contend(pass, other) do
    case DateTime.compare(pass.starts_at, other.starts_at) do
      :gt -> lost(pass, other, "this")
      :lt -> other |> lost(pass, "other")
      :eq -> lost(pass, other, "either")
    end
  end

  # `later` loses from its start to `earlier`'s end, capped at its own end. Neither ending is a
  # real contention it can't measure: flagged with `seconds: nil` (domain).
  defp lost(later, earlier, loses) do
    case first_end(earlier.ends_at, later.ends_at) do
      nil ->
        %{seconds: nil, loses: loses}

      until ->
        seconds = DateTime.diff(until, later.starts_at)
        if seconds > 0, do: %{seconds: seconds, loses: loses}
    end
  end

  defp first_end(nil, nil), do: nil
  defp first_end(nil, b), do: b
  defp first_end(a, nil), do: a
  defp first_end(a, b), do: if(DateTime.compare(a, b) == :gt, do: b, else: a)
end
