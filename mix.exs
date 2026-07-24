defmodule Tiptapex.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/rocket4ce/tiptapex"

  def project do
    [
      app: :tiptapex,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Tiptapex",
      description:
        "Tiptap v3 rich-text editor for Phoenix LiveView: HEEx components, " <>
          "safe server-side JSON-to-HTML rendering, uploads, and optional " <>
          "realtime collaboration over Phoenix Channels.",
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:ecto, "~> 3.10", optional: true},
      # Dev/test only
      {:bandit, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.8", only: :dev, runtime: false},
      {:floki, ">= 0.36.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["rocket4ce"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib assets priv/static/tiptapex.css package.json mix.exs README.md CHANGELOG.md
           LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        Components: [Tiptapex.Components],
        Rendering: [
          Tiptapex.Renderer,
          Tiptapex.Renderer.Node,
          Tiptapex.Renderer.Nodes,
          Tiptapex.Renderer.Marks,
          Tiptapex.Renderer.HTML,
          Tiptapex.Renderer.URL
        ],
        Uploads: [
          Tiptapex.Upload,
          Tiptapex.Upload.Controller,
          Tiptapex.Upload.Validator,
          Tiptapex.Upload.LocalDisk
        ],
        Collaboration: [Tiptapex.Collab, Tiptapex.Collab.Channel],
        Ecto: [Tiptapex.Schema, Tiptapex.Schema.Document]
      ]
    ]
  end

  defp aliases do
    [
      dev: "run --no-halt dev.exs",
      "dev.assets": [
        "esbuild.install --if-missing",
        "esbuild dev_app",
        # priv/static/tiptapex.css is the served + Hex-packaged copy of the
        # stylesheet; keep it in step with the source in assets/css.
        "cmd cp assets/css/tiptapex.css priv/static/tiptapex.css"
      ]
    ]
  end
end
