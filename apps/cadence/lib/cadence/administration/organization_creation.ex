defmodule Cadence.Administration.OrganizationCreation do
  @moduledoc "Finite administrator organization creation with curated validation errors."
  alias Cadence.Administration.Access
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization

  def load(scope) do
    with {:ok, user} <- Access.authorize(scope) do
      {:ok,
       %{
         "version" => 1,
         "user_id" => user.user_id,
         "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
         "created" => nil
       }}
    end
  end

  def create(scope, params) do
    with {:ok, _user} <- Access.authorize(scope),
         {:ok, attrs} <- validate(params) do
      case Organizations.create_organization(Organization.new(attrs)) do
        {:ok, organization} ->
          {:ok,
           %{
             "id" => organization.organization_id,
             "name" => organization.display_name,
             "slug" => organization.slug
           }}

        {:error, %Ecto.Changeset{errors: errors}} ->
          creation_error(errors)
      end
    end
  end

  def validate(%{"display_name" => name, "slug" => slug} = params)
      when map_size(params) == 2 and is_binary(name) and is_binary(slug) do
    name = String.trim(name)
    slug = String.trim(slug)

    errors =
      %{}
      |> error(:display_name, valid_text?(name, 200), "Enter a display name of up to 200 bytes.")
      |> error(:slug, valid_text?(slug, 120), "Enter a slug of up to 120 bytes.")

    if errors == %{},
      do: {:ok, %{display_name: name, slug: slug}},
      else: {:invalid, errors}
  end

  def validate(_), do: {:invalid, %{"form" => "Enter a display name and slug."}}

  defp creation_error(errors) do
    if Keyword.has_key?(errors, :slug),
      do: {:invalid, %{"slug" => "This slug is already in use."}},
      else: {:error, :unavailable}
  end

  defp valid_text?(value, max),
    do: byte_size(value) in 1..max and not String.match?(value, ~r/[\x00-\x1f\x7f]/u)

  defp error(errors, _field, true, _message), do: errors
  defp error(errors, field, false, message), do: Map.put(errors, Atom.to_string(field), message)
end
