defmodule CadenceWeb.ConsolePaths do
  @moduledoc """
  Console URLs for server-side redirects. Console paths carry the organization slug; the server
  holds ids, so the slug is looked up from the signed-in organization. An organization without a
  slug falls back to `/console`. Query parameters pass through only when the caller keeps them.
  """

  alias Cadence.Organizations

  @doc "`/console/<org><rest>`, or `/console`."
  @spec organization(binary() | nil, binary(), map()) :: binary()
  def organization(organization_id, rest, query \\ %{})

  def organization(organization_id, rest, query) when is_binary(organization_id) do
    case Organizations.fetch_organization(organization_id) do
      {:ok, %{slug: slug}} when is_binary(slug) ->
        "/console/#{segment(slug)}" <> rest <> qs(query)

      _other ->
        "/console"
    end
  end

  def organization(_organization_id, _rest, _query), do: "/console"

  @doc "An escaped path segment."
  @spec segment(binary()) :: binary()
  def segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  @doc "`?a=1&b=2` from the kept, non-empty parameters, or empty."
  @spec qs(map()) :: binary()
  def qs(query) do
    case Enum.reject(query, fn {_key, value} -> value in [nil, ""] end) do
      [] -> ""
      kept -> "?" <> URI.encode_query(kept)
    end
  end
end
