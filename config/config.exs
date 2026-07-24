# This configuration only applies when working on the tiptapex library
# itself (the dev/demo app and its asset pipeline). Host applications never
# load a dependency's config files.
import Config

if config_env() == :dev do
  config :esbuild,
    version: "0.25.4",
    dev_app: [
      args: ~w(
        js/app.js
        --bundle
        --target=es2022
        --outdir=../../priv/static/dev
        --alias:tiptapex=../../assets/js/tiptapex/index.js
        --alias:tiptapex/collaboration=../../assets/js/tiptapex/collaboration.js
        --alias:tiptapex/html-editor=../../assets/js/tiptapex/html-editor.js
      ),
      cd: Path.expand("../dev/assets", __DIR__),
      env: %{
        "NODE_PATH" =>
          Enum.join(
            [
              Path.expand("../dev/assets/node_modules", __DIR__),
              Path.expand("../deps", __DIR__)
            ],
            ":"
          )
      }
    ]
end
