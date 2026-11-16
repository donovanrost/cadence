defmodule Cadence.Applications.FixtureContributorsTest do
  @moduledoc """
  The registries' test-only extension point must stay test-only: no dev or prod configuration may
  set `:fixture_application_contributors`, so a fixture application (surface_fixture) can never
  reach a deployment. Production publication separately forbids the surface-fixture remote
  (frontend/tools/frontend-release-output-check.test.mjs).
  """
  use ExUnit.Case, async: true

  alias Cadence.Applications.FixtureContributors

  @key :fixture_application_contributors
  @app_root Path.expand("../../..", __DIR__)
  @configs [
    Path.join(@app_root, "config/config.exs"),
    Path.join(@app_root, "../cadence_web/config/config.exs")
  ]

  for env <- [:dev, :prod] do
    test "the #{env} configuration sets no fixture application contributors" do
      for path <- @configs, File.exists?(path) do
        cadence =
          path
          |> Config.Reader.read!(env: unquote(env), target: :host)
          |> Keyword.get(:cadence, [])

        assert Keyword.get(cadence, @key, []) == [],
               "#{Path.relative_to(path, @app_root)} sets :#{@key} for #{unquote(env)}"
      end
    end
  end

  test "no runtime configuration mentions the fixture contributors" do
    for path <- [
          Path.join(@app_root, "config/runtime.exs"),
          Path.join(@app_root, "../cadence_web/config/runtime.exs")
        ],
        File.exists?(path) do
      refute File.read!(path) =~ Atom.to_string(@key), "#{path} mentions :#{@key}"
    end
  end

  test "every configured fixture contributor exists in the test environment" do
    for contributor <- FixtureContributors.configured() do
      assert Code.ensure_loaded?(contributor), "#{inspect(contributor)} is not compiled"
    end
  end
end
