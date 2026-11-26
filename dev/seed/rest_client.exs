defmodule EarendilRestClient do
  @moduledoc "HTTP session client shared by the standalone Earendil seed and live rehearsal."

  @api_base "/api/v1"

  def sign_in(base, email, password) do
    client = %{base: String.trim_trailing(base, "/"), cookies: %{}, csrf: nil}
    {client, page} = request!(client, :get, "/console/sign-in", nil, api?: false)
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page)
    client = %{client | csrf: csrf}
    {client, _} = request!(client, :post, "/auth/sign-in", %{email: email, password: password})
    {client, session} = request!(%{client | csrf: nil}, :get, "/session")

    unless session["admin_mode"] == true,
      do: raise("admin sign-in: environment admin session did not enter admin mode")

    {%{client | csrf: session["csrf_token"]}, session}
  end

  def select_organization(client, organization_id) do
    {client, session} =
      request!(client, :put, "/session/organization", %{organization_id: organization_id})

    {%{client | csrf: session["csrf_token"]}, session}
  end

  def request!(client, method, path, body \\ nil, opts \\ []) do
    url = client.base <> if(Keyword.get(opts, :api?, true), do: @api_base, else: "") <> path
    accept = if Keyword.get(opts, :api?, true), do: "application/json", else: "text/html"

    options = [
      method: method,
      url: url,
      headers: headers(client, accept),
      receive_timeout: 120_000,
      retry: false
    ]

    options = if body, do: Keyword.put(options, :json, body), else: options

    options =
      if opts[:multipart],
        do: Keyword.put(options, :form_multipart, opts[:multipart]),
        else: options

    case Req.request(options) do
      {:ok, response} -> response!(client, method, path, response)
      {:error, error} -> raise("#{method} #{path}: #{Exception.message(error)}")
    end
  end

  defp headers(client, accept) do
    headers = [{"accept", accept}]
    headers = if client.csrf, do: [{"x-csrf-token", client.csrf} | headers], else: headers

    if map_size(client.cookies) == 0 do
      headers
    else
      cookie = Enum.map_join(client.cookies, "; ", fn {name, value} -> "#{name}=#{value}" end)
      [{"cookie", cookie} | headers]
    end
  end

  defp response!(client, method, path, response) do
    unless response.status in 200..299,
      do: raise("#{method} #{path} (HTTP #{response.status}): #{inspect(response.body)}")

    cookies =
      Enum.reduce(Req.Response.get_header(response, "set-cookie"), client.cookies, &cookie/2)

    data =
      if is_map(response.body),
        do: Map.get(response.body, "data", response.body),
        else: response.body

    {%{client | cookies: cookies}, data}
  end

  defp cookie(line, cookies) do
    [pair | _] = String.split(line, ";", parts: 2)

    case String.split(pair, "=", parts: 2) do
      [name, value] -> Map.put(cookies, name, value)
      _ -> cookies
    end
  end
end
