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
          "packages/*/test/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/", ~r"/cover/"]
      }
    }
  ]
}
