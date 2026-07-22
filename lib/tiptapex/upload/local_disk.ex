defmodule Tiptapex.Upload.LocalDisk do
  @moduledoc """
  A ready-made `Tiptapex.Upload` handler that writes files to local disk.
  Intended for development, demos, and single-node deployments — for
  production prefer a handler backed by object storage.

  Configure the destination directory and the public URL prefix:

      config :tiptapex, Tiptapex.Upload.LocalDisk,
        dir: "priv/uploads",
        url_prefix: "/uploads"

  Serve the directory with `Plug.Static` (or your endpoint):

      plug Plug.Static, at: "/uploads", from: "priv/uploads"

  Stored files get a random, collision-free name; the original (sanitized)
  filename is only used for its extension and the returned `filename`.
  """

  @behaviour Tiptapex.Upload

  alias Tiptapex.Upload.Validator

  @impl true
  def store(%Plug.Upload{} = upload, _context) do
    config = Application.get_env(:tiptapex, __MODULE__, [])
    dir = Keyword.get(config, :dir, "priv/uploads")
    url_prefix = Keyword.get(config, :url_prefix, "/uploads")

    filename = Validator.sanitize_filename(upload.filename)
    ext = filename |> Path.extname() |> String.slice(0, 10)
    key = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false) <> ext
    dest = Path.join(dir, key)

    with :ok <- File.mkdir_p(dir),
         {:ok, _} <- File.copy(upload.path, dest) do
      {:ok,
       %{
         url: Path.join(url_prefix, key),
         content_type: upload.content_type || "application/octet-stream",
         filename: filename
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
