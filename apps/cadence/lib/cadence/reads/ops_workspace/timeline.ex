defmodule Cadence.Reads.OpsWorkspace.Timeline do
  @moduledoc "Authorized cross-module timeline facts for host workspace composition."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.{Dashboards, Missions}
  alias Cadence.Reads.MissionTimeline

  @filter_keys ~w(category kind severity spacecraft_id from to)
  @query_keys @filter_keys ++ ~w(event_id source_dashboard_id before_at before_id)
  @reference_keys ~w(spacecraft_id source_endpoint_ref scheduled_contact_id realized_contact_id path_id capability_instance_id activation_id correlation_key)a

  def load(%Scope{} = scope, mission_id, params) when is_binary(mission_id) and is_map(params) do
    with true <- is_nil(scope.mission_id) or scope.mission_id == mission_id,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, query} <- query(params) do
      {errors, opts} = filters(query)

      page =
        if errors == [],
          do: MissionTimeline.page_for_mission(scope.organization_id, mission_id, opts),
          else: %{entries: [], next_cursor: nil}

      {selected_status, selected} = selected(scope, mission_id, query["event_id"])

      {:ok,
       %{
         "version" => 1,
         "context" => %{"organization_id" => scope.organization_id, "mission_id" => mission_id},
         "mission_name" => mission.display_name,
         "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
         "query" => query,
         "errors" => errors,
         "limit" => 100,
         "events" => Enum.map(page.entries, &event/1),
         "next_cursor" => cursor_dto(page.next_cursor),
         "selected_status" => selected_status,
         "selected" => selected,
         "source_dashboard_id" =>
           source_dashboard(scope, mission_id, query["source_dashboard_id"])
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def load(_, _, _), do: {:error, :unavailable}

  defp query(params) do
    if Enum.all?(params, fn {key, value} ->
         key in @query_keys and is_binary(value) and byte_size(value) <= 512 and
           not String.contains?(value, ["\n", "\r", <<0>>])
       end) do
      {:ok, Map.new(@query_keys, &{&1, Map.get(params, &1, "")})}
    else
      {:error, :invalid_query}
    end
  end

  defp filters(query) do
    errors =
      []
      |> invalid(
        query["category"] not in ["", "operations", "health", "runtime", "transport"],
        "category"
      )
      |> invalid(
        query["severity"] not in ["", "info", "warning", "error", "critical"],
        "severity"
      )
      |> invalid(not identity?(query["spacecraft_id"]), "spacecraft_id")
      |> invalid(
        query["kind"] != "" and not Regex.match?(~r/^[a-z][a-z0-9_]{0,119}$/, query["kind"]),
        "kind"
      )

    from = date(query["from"])
    to = date(query["to"])
    errors = errors |> invalid(from == :invalid, "from") |> invalid(to == :invalid, "to")

    errors =
      invalid(
        errors,
        match?(%DateTime{}, from) and match?(%DateTime{}, to) and
          DateTime.compare(from, to) != :lt,
        "time_range"
      )

    cursor = read_cursor(query)
    errors = invalid(errors, cursor == :invalid, "cursor")

    opts =
      [limit: 100]
      |> put(:cursor, cursor)
      |> put(:category, query["category"])
      |> put(:kind, query["kind"])
      |> put(:severity, query["severity"])
      |> put(:spacecraft_id, query["spacecraft_id"])
      |> put(:from_occurred_at, from)
      |> put(:to_occurred_at, to)

    {errors, opts}
  end

  defp read_cursor(%{"before_at" => "", "before_id" => ""}), do: nil

  defp read_cursor(%{"before_at" => at, "before_id" => id}) do
    case date(at) do
      %DateTime{} = time ->
        if id != "" and identity?(id),
          do: %{occurred_at: time, mission_event_id: id},
          else: :invalid

      _ ->
        :invalid
    end
  end

  defp cursor_dto(nil), do: nil

  defp cursor_dto(cursor),
    do: %{"at" => DateTime.to_iso8601(cursor.occurred_at), "id" => cursor.mission_event_id}

  defp invalid(errors, false, _key), do: errors
  defp invalid(errors, true, key), do: errors ++ [key]
  defp identity?(""), do: true
  defp identity?(value), do: Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,511}$/, value)
  defp put(opts, _key, value) when value in [nil, "", :invalid], do: opts
  defp put(opts, key, value), do: Keyword.put(opts, key, value)
  defp date(""), do: nil

  defp date(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> :invalid
    end
  end

  defp selected(_, _, ""), do: {"none", nil}

  defp selected(scope, mission_id, id) do
    case MissionTimeline.fetch_for_mission(scope.organization_id, mission_id, id) do
      {:ok, entry} -> {"ready", event(entry)}
      _ -> {"unavailable", nil}
    end
  end

  defp source_dashboard(_, _, ""), do: nil

  defp source_dashboard(scope, mission_id, id) do
    case Dashboards.fetch_document(scope.organization_id, mission_id, id) do
      {:ok, _} -> id
      _ -> nil
    end
  end

  defp event(entry) do
    %{
      "id" => entry.mission_event_id,
      "occurred_at" => DateTime.to_iso8601(entry.occurred_at),
      "category" => to_string(entry.category),
      "kind" => to_string(entry.kind),
      "severity" => optional(entry.severity),
      "status" => entry.status,
      "title" => entry.title,
      "summary" => entry.summary,
      "source" => %{"kind" => to_string(entry.source_record_kind), "id" => entry.source_record_id},
      "subject" => %{"kind" => optional(entry.subject_kind), "id" => entry.subject_id},
      "references" => Map.new(@reference_keys, &{Atom.to_string(&1), Map.get(entry, &1)})
    }
  end

  defp optional(nil), do: nil
  defp optional(value), do: to_string(value)
end
