defmodule Cadence.Reads.Administration.PlatformOrganizationsTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{User, UserRow}
  alias Cadence.Administration.OrganizationCreation
  alias Cadence.Auth.Scope
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization
  alias Cadence.Reads.Administration.{OrganizationDirectory, PlatformOverview}

  setup do
    user = user!("admin", [:platform_admin])
    %{user: user, scope: Scope.new(%{user: user, admin_mode?: true})}
  end

  test "global counts, binary cursor paging and real producer to component to creation", c do
    slugs = [
      "a-lower",
      "A-upper" | Enum.map(1..51, &"org-#{String.pad_leading(to_string(&1), 3, "0")}")
    ]

    for slug <- slugs do
      assert {:ok, _} =
               Organizations.persist_organization(
                 Organization.new(%{
                   organization_id: slug,
                   slug: slug,
                   display_name: "Name #{slug}",
                   metadata: %{"private" => "omitted"}
                 })
               )
    end

    user!("ordinary", [])
    disabled = user!("disabled", [])

    Repo.get!(UserRow, disabled.user_id)
    |> Ecto.Changeset.change(lifecycle_state: "disabled")
    |> Repo.update!()

    assert {:ok, overview} = PlatformOverview.load(c.scope)
    assert overview["counts"] == %{"organizations" => 53, "active_users" => 2}
    assert {:ok, first} = OrganizationDirectory.load(c.scope)
    assert length(first["organizations"]) == 50
    assert {:ok, last} = OrganizationDirectory.load(c.scope, first["next_cursor"])
    assert length(last["organizations"]) == 3
    assert last["next_cursor"] == nil

    assert Enum.map(first["organizations"] ++ last["organizations"], & &1["slug"]) ==
             Enum.sort(slugs)

    assert Enum.all?(
             first["organizations"],
             &(Map.keys(&1) |> Enum.sort() == ["id", "name", "slug"])
           )

    assert {:ok, creation} = OrganizationCreation.load(c.scope)

    probe =
      Path.expand(
        "../../../../../../frontend/apps/host/src/administration/features/organization-create/producer-consumer-probe.mjs",
        __DIR__
      )

    {output, code} =
      System.cmd(
        "node",
        [probe, Jason.encode!(%{overview: overview, directory: first, creation: creation})],
        stderr_to_stdout: true
      )

    assert code == 0, output
    [_, encoded] = Regex.run(~r/ADMIN_CREATE_INPUT=([A-Za-z0-9+\/=]+)/, output)
    input = encoded |> Base.decode64!() |> Jason.decode!()
    assert {:ok, created} = OrganizationCreation.create(c.scope, input)
    assert {:ok, persisted} = Organizations.fetch_organization(created["id"])
    assert persisted.display_name == "Created through the real form"
    assert persisted.slug == "created-through-vue"
    assert {:ok, refreshed} = PlatformOverview.load(c.scope)
    assert refreshed["counts"]["organizations"] == 54
  end

  test "empty directory and invalid cursor admission", c do
    assert {:ok, %{"organizations" => [], "next_cursor" => nil}} =
             OrganizationDirectory.load(c.scope)

    for params <- [
          %{"after_id" => "id"},
          %{"after_slug" => "slug"},
          %{"page" => "2"},
          %{"after_slug" => [], "after_id" => "id"}
        ] do
      assert {:error, :invalid_query} = OrganizationDirectory.load(c.scope, params)
    end
  end

  test "duplicate slug, invalid fields and injected identity cannot create an organization", c do
    params = %{"display_name" => "First", "slug" => "same-slug"}
    assert {:ok, first} = OrganizationCreation.create(c.scope, params)

    assert {:invalid, %{"slug" => _}} =
             OrganizationCreation.create(c.scope, %{params | "display_name" => "Second"})

    for invalid <- [
          Map.put(params, "organization_id", "forged"),
          %{"display_name" => "  ", "slug" => "new"},
          %{"display_name" => "Name", "slug" => "a\nb"},
          %{"display_name" => String.duplicate("x", 201), "slug" => "new"}
        ] do
      assert {:invalid, _} = OrganizationCreation.create(c.scope, invalid)
    end

    assert Organizations.count_organizations() == 1
    assert {:ok, original} = Organizations.fetch_organization(first["id"])
    assert original.display_name == "First"
  end

  test "reads and effects reject services, missing mode and freshly revoked eligibility", c do
    params = %{"display_name" => "Denied", "slug" => "denied"}

    for scope <- [
          nil,
          %Scope{},
          %{c.scope | actor_kind: :service},
          %{c.scope | admin_mode?: false}
        ] do
      assert {:error, _} = PlatformOverview.load(scope)
      assert {:error, _} = OrganizationDirectory.load(scope)
      assert {:error, _} = OrganizationCreation.load(scope)
      assert {:error, _} = OrganizationCreation.create(scope, params)
    end

    Repo.get!(UserRow, c.user.user_id)
    |> Ecto.Changeset.change(capabilities: [])
    |> Repo.update!()

    assert {:error, _} = PlatformOverview.load(c.scope)
    assert {:error, _} = OrganizationDirectory.load(c.scope)
    assert {:error, _} = OrganizationCreation.create(c.scope, params)
    assert Organizations.count_organizations() == 0
  end

  defp user!(id, capabilities) do
    user =
      User.new(%{
        user_id: id,
        email: "#{id}@example.test",
        display_name: id,
        capabilities: capabilities
      })

    Repo.insert!(UserRow.changeset(user))
    user
  end
end
