%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "mix.exs",
          "apps/*/mix.exs",
          "apps/*/lib/",
          "apps/*/test/",
          "packages/*/mix.exs",
          "packages/*/lib/",
          "packages/*/test/",
          "dev/otp_cluster/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/", ~r"/cover/"]
      },
      checks: %{
        extra: [
          # `# todo(authz): …` marks where Cedar should decide later (the user's convention,
          # DECISIONS #62). Keep them listed, but don't fail the build on them.
          {Credo.Check.Design.TagTODO, [exit_status: 0]}
        ]
      }
    }
  ]
}
