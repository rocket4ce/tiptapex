defmodule Tiptapex.Upload do
  @moduledoc """
  Behaviour for storing editor uploads.

  The editor POSTs files (drag & drop, paste, toolbar buttons) as
  `multipart/form-data` to the endpoint configured via the component's
  `upload_url` attribute. `Tiptapex.Upload.Controller` receives and
  validates the request, then hands the file to your implementation of
  this behaviour — where you decide how to store it (S3, local disk, your
  existing attachments context…).

      defmodule MyApp.EditorUploads do
        @behaviour Tiptapex.Upload

        @impl true
        def store(%Plug.Upload{} = upload, %{scope: article_id}) do
          with {:ok, attachment} <- MyApp.Attachments.create_for(article_id, upload) do
            {:ok,
             %{
               url: MyApp.Attachments.url(attachment),
               content_type: attachment.content_type,
               filename: attachment.filename
             }}
          end
        end
      end

  The returned map is the frozen wire contract with the JS hook: it is
  serialized as `{"url": ..., "content_type": ..., "filename": ...}` and
  the hook inserts an image (`image/*`), a video node (`video/*`), or a
  download link (anything else).
  """

  @type result :: %{
          required(:url) => String.t(),
          required(:content_type) => String.t(),
          required(:filename) => String.t()
        }

  @type context :: %{
          required(:scope) => term(),
          required(:params) => map(),
          required(:conn_assigns) => map()
        }

  @callback store(upload :: Plug.Upload.t(), context :: context()) ::
              {:ok, result()} | {:error, term()}
end
