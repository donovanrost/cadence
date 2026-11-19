defmodule CadenceWeb.Console.OrganizationController do
  @moduledoc """
  Organization-level reads under `/api/console/v1/organizations/:organization_id`
  (the `console_organization` pipeline authorizes membership). Contract:
  docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias Cadence.Reads.{OrganizationAudit, OrganizationMissions}
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  @default_window_s 7 * 86_400

  def missions(conn, _params) do
    missions = OrganizationMissions.list(conn.assigns.current_scope.organization_id)
    json(conn, %{data: ConfigJSON.encode(%{missions: missions})})
  end

  @doc "AU1, organization admins only (`:read_organization`). See setup.md."
  def audit(conn, params) do
    scope = conn.assigns.current_scope
    org = scope.organization_id

    with :ok <- Policy.authorize(scope, :read_organization, %{organization_id: org}),
         {:ok, opts} <- audit_opts(params) do
      data = OrganizationAudit.list(org, opts)

      json(conn, %{
        data:
          ConfigJSON.encode(%{
            events: data.events,
            sources: data.sources,
            next_cursor: data.next_offset && Integer.to_string(data.next_offset)
          })
      })
    else
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
      {:error, _forbidden} -> Problem.respond(conn, :forbidden)
    end
  end

  defp audit_opts(params) do
    now = DateTime.utc_now()

    with {:ok, to} <- time(params["to"], now, :to),
         {:ok, from} <- time(params["from"], DateTime.add(to, -@default_window_s), :from),
         {:ok, kinds} <- kinds(params["kinds"]),
         {:ok, offset} <- non_negative(params["cursor"], 0, :cursor),
         {:ok, limit} <- non_negative(params["limit"], 100, :limit) do
      {:ok,
       %{
         from: from,
         to: to,
         kinds: kinds,
         actor_id: blank(params["actor_id"]),
         mission_id: blank(params["mission_id"]),
         offset: offset,
         limit: limit |> max(1) |> min(200)
       }}
    end
  end

  defp time(nil, default, _key), do: {:ok, default}

  defp time(value, _default, key) do
    case DateTime.from_iso8601(to_string(value)) do
      {:ok, at, _offset} -> {:ok, at}
      _invalid -> {:error, {:invalid_params, %{key => "must be ISO-8601"}}}
    end
  end

  defp kinds(nil), do: {:ok, nil}

  defp kinds(value) do
    list = value |> to_string() |> String.split(",", trim: true)

    if Enum.all?(list, &(&1 in OrganizationAudit.kinds())),
      do: {:ok, list},
      else:
        {:error,
         {:invalid_params, %{kinds: "must be from #{Enum.join(OrganizationAudit.kinds(), ", ")}"}}}
  end

  defp non_negative(nil, default, _key), do: {:ok, default}

  defp non_negative(value, _default, key) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n >= 0 -> {:ok, n}
      _invalid -> {:error, {:invalid_params, %{key => "must be a non-negative integer"}}}
    end
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value
end
