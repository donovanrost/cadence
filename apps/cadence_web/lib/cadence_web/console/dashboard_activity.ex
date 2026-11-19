defmodule CadenceWeb.Console.DashboardActivity do
  @moduledoc """
  D17 activity (fe-setup, docs/apogee/plans/dashboards-settings.md): one feed, newest first,
  25 per page, merged from the dashboard's versions and lifecycle events
  (`Reads.Dashboards.Activity`, which pages each newest first on its own cursor).

  Kinds are closed: `saved | restored | archived | unarchived`. Share, snapshot and export
  rows (`share_created | share_revoked | snapshot_taken | exported`) join once their creator and
  time are projected (domain, with D14-D16). A `published` or `reverted` lifecycle event repeats
  the version row it belongs to (every save is current), and review, health and readiness
  events are bookkeeping, so those are left out.

  Exact paging over two sources: a page only goes as far back as the oldest fetched item of a
  source that has more, and the opaque cursor holds both sources' positions.
  """

  alias Cadence.Accounts
  alias Cadence.Reads.Dashboards.Activity

  @page 25
  @shown %{"archived" => "archived", "restored" => "unarchived"}

  @spec load(Cadence.Auth.Scope.t(), binary(), binary(), binary() | nil) ::
          {:ok, map()} | {:error, :invalid_cursor | :unavailable}
  def load(scope, mission, dashboard, cursor) do
    with {:ok, position} <- decode(cursor),
         {:ok, history} <- Activity.load(scope, mission, dashboard, params(position)) do
      {:ok, page(history, names(history))}
    end
  end

  @doc "Pure: one page from an Activity.load/4 result and actor names (id => name)."
  @spec page(map(), map()) :: map()
  def page(history, names) do
    versions = Enum.map(history.versions, &{:version, &1})
    events = Enum.map(history.events, &{:event, &1})
    floor = page_floor([{versions, history.next_version}, {events, history.next_event}])

    candidates =
      (versions ++ events)
      |> Enum.filter(&(floor == nil or compare(key(&1), floor) != :lt))
      |> Enum.sort(&(compare(key(&1), key(&2)) != :lt))

    {taken, rest} = take_visible(candidates, @page)

    %{
      events: taken |> Enum.map(&item(&1, names)) |> Enum.reject(&is_nil/1),
      next: next_cursor(taken, rest, history)
    }
  end

  # Takes candidates (skipped ones included, so the cursor passes them) until `n` are shown.
  defp take_visible(candidates, n) do
    {taken, rest, _shown} =
      Enum.reduce(candidates, {[], [], 0}, fn candidate, {taken, rest, shown} ->
        cond do
          shown >= n -> {taken, [candidate | rest], shown}
          shown?(candidate) -> {[candidate | taken], rest, shown + 1}
          true -> {[candidate | taken], rest, shown}
        end
      end)

    {Enum.reverse(taken), Enum.reverse(rest)}
  end

  defp next_cursor(taken, rest, history) do
    more? = rest != [] or (history.next_version != nil or history.next_event != nil)

    if more? and taken != [] do
      position = %{
        "v" => taken |> Enum.filter(&match?({:version, _}, &1)) |> last_version(history),
        "e" => taken |> Enum.filter(&match?({:event, _}, &1)) |> last_event(history)
      }

      Base.url_encode64(Jason.encode!(position), padding: false)
    end
  end

  # Where each source resumes: after the last one taken, else where this page started.
  defp last_version([], history), do: history.query.before_version
  defp last_version(taken, _history), do: taken |> List.last() |> elem(1) |> Map.fetch!(:version)
  defp last_event([], history), do: history.query.before_event
  defp last_event(taken, _history), do: taken |> List.last() |> elem(1) |> Map.fetch!(:id)

  defp shown?({:version, _version}), do: true
  defp shown?({:event, event}), do: Map.has_key?(@shown, event.event_type)

  defp item({:version, version}, names) do
    restored_from = restored_from(version)

    %{
      id: "version:#{version.version}",
      kind: if(restored_from, do: "restored", else: "saved"),
      at: version.saved_at,
      actor: actor(version.actor_id, names),
      version: version.version,
      detail:
        if(restored_from, do: "Restored from v#{restored_from}", else: blank(version.summary))
    }
  end

  defp item({:event, event}, names) do
    case Map.fetch(@shown, event.event_type) do
      {:ok, kind} ->
        %{
          id: event.id,
          kind: kind,
          at: event.occurred_at,
          actor: actor(event.actor_id, names),
          version: event.document_version,
          detail: nil
        }

      :error ->
        nil
    end
  end

  # Publishing overwrites a revert's snapshot_kind (domain), but CurrentVersions.restore always
  # writes "Restored from version N" as the change summary.
  defp restored_from(%{kind: "revert", based_on_version: from}) when is_integer(from), do: from

  defp restored_from(%{summary: "Restored from version " <> number}) do
    case Integer.parse(number) do
      {from, ""} -> from
      _other -> nil
    end
  end

  defp restored_from(_version), do: nil

  # The newest key a page may not go past: the oldest fetched item of each source with more.
  defp page_floor(sources) do
    sources
    |> Enum.filter(fn {items, next} -> next != nil and items != [] end)
    |> Enum.map(fn {items, _next} -> items |> List.last() |> key() end)
    |> Enum.max(&(compare(&1, &2) != :lt), fn -> nil end)
  end

  defp key({:version, version}), do: {time(version.saved_at), "version:#{version.version}"}
  defp key({:event, event}), do: {time(event.occurred_at), event.id}

  defp compare({at_a, id_a}, {at_b, id_b}) do
    case DateTime.compare(at_a, at_b) do
      :eq -> compare_ids(id_a, id_b)
      order -> order
    end
  end

  defp compare_ids(same, same), do: :eq
  defp compare_ids(a, b) when a > b, do: :gt
  defp compare_ids(_a, _b), do: :lt

  defp time(iso) when is_binary(iso) do
    {:ok, at, _offset} = DateTime.from_iso8601(iso)
    at
  end

  defp time(_missing), do: ~U[1970-01-01 00:00:00Z]

  defp params(%{"v" => v, "e" => e}) do
    %{}
    |> then(&if(is_integer(v), do: Map.put(&1, "before_version", Integer.to_string(v)), else: &1))
    |> then(&if(is_binary(e), do: Map.put(&1, "before_event", e), else: &1))
  end

  defp decode(nil), do: {:ok, %{"v" => nil, "e" => nil}}

  defp decode(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"v" => v, "e" => e} = position} <- Jason.decode(raw),
         true <- (is_nil(v) or is_integer(v)) and (is_nil(e) or is_binary(e)) do
      {:ok, position}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp decode(_cursor), do: {:error, :invalid_cursor}

  defp names(history) do
    (Enum.map(history.versions, & &1.actor_id) ++ Enum.map(history.events, & &1.actor_id))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Map.new(fn id ->
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _not_a_user -> {id, nil}
      end
    end)
  end

  defp actor(id, names) when is_binary(id), do: %{id: id, name: Map.get(names, id)}
  defp actor(_none, _names), do: nil

  defp blank(""), do: nil
  defp blank(text), do: text
end
