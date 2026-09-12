defmodule Cadence.Reads.CommandHistory do
  @moduledoc "Authorized request history with independently pinned release and verifier selections."
  alias Cadence.Auth.Scope
  alias Cadence.Reads.CommandHistory.{Projection, Query}
  alias Cadence.Reads.CommandReadAccess
  alias Cadence.Repo
  @keys ~w(release release_after verifier_after verifier)

  def load(scope, mission, request, params \\ %{}, opts \\ [])

  def load(%Scope{} = scope, mission, request, params, opts) when is_list(opts) do
    with :ok <- CommandReadAccess.authorize(scope, mission),
         true <- identity?(request),
         {:ok, query} <- admit_query(params) do
      execute = Keyword.get(opts, :query, &Repo.query!/2)
      args = [scope.organization_id, mission, request] ++ Enum.map(@keys, &query[&1])
      %{rows: [[data]], num_rows: 1} = execute.(Query.statement(), args)
      observed = Keyword.get(opts, :observed_at, &DateTime.utc_now/0).()
      {:ok, Projection.model(data, scope.organization_id, mission, request, query, observed)}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(_, _, _, _, _), do: {:error, :unavailable}

  def admit_query(params) when is_map(params) and map_size(params) <= 4 do
    if Enum.all?(params, fn {key, value} -> key in @keys and (value == "" or identity?(value)) end) do
      query = Map.new(@keys, &{&1, Map.get(params, &1, "")})

      if query["verifier"] == "" or query["release"] != "",
        do: {:ok, query},
        else: {:error, :invalid_history_query}
    else
      {:error, :invalid_history_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_history_query}

  def identity?(value),
    do:
      is_binary(value) and String.valid?(value) and byte_size(value) in 1..256 and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, value)
end
