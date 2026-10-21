if Mix.env() != :dev, do: raise("The Earendil configuration is a development-only fixture")
Logger.configure(level: :warning)
{:ok, _} = Application.ensure_all_started(:cadence)
Code.require_file("reflect_orbital/fixture.exs", __DIR__)
Code.require_file("reflect_orbital/configuration.exs", __DIR__)

alias Cadence.Dev.ReflectOrbital.Fixture, as: F

{:ok, user} =
  Cadence.Accounts.fetch_user_by_email(System.get_env("EARENDIL_DEMO_EMAIL", "admin@example.com"))

{:ok, organization} = Cadence.Organizations.fetch_organization(F.organization_id())
{:ok, membership} = Cadence.Accounts.fetch_user_membership(user.user_id, F.organization_id())

scope =
  Cadence.Auth.Scope.new(%{
    user: user,
    organization: organization,
    organization_membership: membership
  })

configured =
  Cadence.Dev.ReflectOrbital.Configuration.prepare(scope,
    reimport?: "--reimport" in System.argv()
  )

IO.puts(
  "Saved 500 configurations against catalog revision #{configured.revision.catalog_revision_id}"
)
