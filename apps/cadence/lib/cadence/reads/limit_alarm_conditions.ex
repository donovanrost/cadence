defmodule Cadence.Reads.LimitAlarmConditions do
  @moduledoc "Authorized, paged limit conditions for host-owned Ops composition."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Limits.Pages
  alias Cadence.Reads.Limits
  alias Cadence.Reads.LimitStateEvidence
  alias Cadence.SpacecraftStore

  @keys ~w(severity state spacecraft_id query page spacecraft_page spacecraft_query)
  @severity %{"critical" => "red", "warning" => "yellow", "info" => "blue", "nominal" => "green"}

  def load(scope, mission, params \\ %{})

  def load(%Scope{actor_kind: :user, user: %{user_id: user}} = scope, mission, params) do
    with true <- is_binary(user) and scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, entity} <- Missions.fetch_mission(scope.organization_id, mission),
         {:ok, query} <- admit_query(params),
         {:ok, craft_opts, craft_label} <-
           spacecraft(scope.organization_id, mission, query["spacecraft_id"]) do
      base = "/missions/#{mission}/ops/alarms"
      org = scope.organization_id

      states =
        Limits.latest_states_page(
          org,
          mission,
          craft_opts ++
            [
              search: query["query"],
              severity: @severity[query["severity"]],
              violation: violation(query["state"]),
              page: query["page"]
            ]
        )

      craft = craft_page(org, mission, query)

      data = %{
        "version" => 1,
        "organization_id" => org,
        "mission_id" => mission,
        "mission_name" => entity.display_name,
        "loaded_at" => Pages.stamp(DateTime.utc_now()),
        "query" => query,
        "links" => %{
          "self" => base,
          "definitions" => "/missions/#{mission}/applications/limits/manage",
          "posture" => "/missions/#{mission}/applications/limits/activity"
        },
        "counts" =>
          Map.new(@severity, fn {tone, state} -> {tone, Map.fetch!(states.counts, state)} end),
        "states" =>
          Pages.envelope(
            %{states | items: Enum.map(states.items, &row(&1, mission))},
            base,
            query,
            "page"
          ),
        "spacecraft_filter" => craft_label,
        "spacecraft" =>
          Pages.envelope(
            %{
              items:
                Enum.map(craft.items, &%{"id" => &1.spacecraft_id, "label" => &1.display_name}),
              total_count: craft.total_count,
              page: craft.page
            },
            base,
            query,
            "spacecraft_page"
          )
      }

      if byte_size(Jason.encode!(data)) <= 524_288, do: {:ok, data}, else: {:error, :unavailable}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def load(_, _, _), do: {:error, :unavailable}

  def admit_query(params) when is_map(params) and map_size(params) <= 7 do
    with true <- Enum.all?(params, fn {k, v} -> k in @keys and query_text?(v) end),
         severity = default(params["severity"], "all"),
         true <- severity in ["all", "critical", "warning", "info", "nominal"],
         state = default(params["state"], "all"),
         true <- state in ["all", "active", "nominal"],
         {:ok, page} <- number(params["page"]),
         {:ok, craft_page} <- number(params["spacecraft_page"]) do
      {:ok,
       %{
         "severity" => severity,
         "state" => state,
         "spacecraft_id" => default(params["spacecraft_id"], "all"),
         "query" => String.trim(params["query"] || ""),
         "page" => page,
         "spacecraft_page" => craft_page,
         "spacecraft_query" => String.trim(params["spacecraft_query"] || "")
       }}
    else
      _ -> {:error, :invalid_alarm_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_alarm_query}

  defp query_text?(v),
    do:
      is_binary(v) and String.valid?(v) and byte_size(v) <= 240 and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, v)

  defp default(v, fallback) when v in [nil, ""], do: fallback
  defp default(v, _), do: v
  defp number(nil), do: {:ok, 1}

  defp number(v) do
    case Integer.parse(v) do
      {n, ""} when n in 1..100_000 -> {:ok, n}
      _ -> {:error, :invalid_page}
    end
  end

  defp violation("active"), do: true
  defp violation("nominal"), do: false
  defp violation(_), do: nil
  defp spacecraft(_, _, "all"), do: {:ok, [], "All spacecraft and mission states"}
  defp spacecraft(_, _, "mission"), do: {:ok, [spacecraft_id: nil], "Mission states"}

  defp spacecraft(org, mission, id) do
    with {:ok, craft} <- SpacecraftStore.fetch_spacecraft(org, mission, id),
         do: {:ok, [spacecraft_id: id], craft.display_name}
  end

  defp craft_page(org, mission, query) do
    opts = [page: query["spacecraft_page"], page_size: 25, search: query["spacecraft_query"]]
    page = SpacecraftStore.list_spacecraft_page(org, mission, opts)
    last = max(1, ceil(page.total_count / 25))

    if page.page > last,
      do: SpacecraftStore.list_spacecraft_page(org, mission, Keyword.put(opts, :page, last)),
      else: page
  end

  defp row(e, mission) do
    query = %{"definition" => e.limit_definition_id, "version" => e.limit_definition_version}
    href = "/missions/#{mission}/applications/limits/activity?" <> URI.encode_query(query)
    LimitStateEvidence.row(e, mission, href)
  end
end
