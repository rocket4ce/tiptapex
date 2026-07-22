defmodule Tiptapex.Upload.Validator do
  @moduledoc """
  Server-side validation for editor uploads: size limit, content-type
  verification via magic-byte sniffing, and filename sanitization.

  The client's `Content-Type` header is attacker-controlled; for the
  sniffable formats (images, videos, PDF) the actual file signature must
  agree with the claimed type or the upload is rejected. Types without a
  reliable signature (e.g. `text/plain`) are accepted based on the
  allow-list alone.
  """

  @default_allowed ~w(
    image/png image/jpeg image/gif image/webp
    video/mp4 video/webm
    application/pdf
  )

  @default_max_bytes 25_000_000

  # Types we can verify by signature. A claimed type in this list MUST
  # match its sniffed signature.
  @strict_types ~w(image/png image/jpeg image/gif image/webp video/mp4 video/webm application/pdf)

  # Zip-based formats all share the PK signature.
  @zip_types ~w(application/zip application/vnd.openxmlformats-officedocument.wordprocessingml.document application/vnd.openxmlformats-officedocument.spreadsheetml.sheet)

  @doc "The default allowed MIME list."
  def default_allowed, do: @default_allowed

  @doc "The default maximum size in bytes (25 MB)."
  def default_max_bytes, do: @default_max_bytes

  @doc """
  Validates a `Plug.Upload`.

  Options: `:max_bytes` (default 25 MB) and `:allowed` (MIME allow-list).

  Returns `{:ok, %{content_type: type, size: bytes, filename: sanitized}}`
  with the *verified* content type, or `{:error, reason}` where reason is
  `:empty`, `:too_large`, `:unsupported_type`, or `:content_type_mismatch`.
  """
  @spec validate(Plug.Upload.t(), keyword()) ::
          {:ok, %{content_type: String.t(), size: non_neg_integer(), filename: String.t()}}
          | {:error, :empty | :too_large | :unsupported_type | :content_type_mismatch}
  def validate(%Plug.Upload{} = upload, opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    allowed = Keyword.get(opts, :allowed, @default_allowed)

    with {:ok, size} <- check_size(upload.path, max_bytes),
         {:ok, content_type} <- check_type(upload, allowed) do
      {:ok,
       %{content_type: content_type, size: size, filename: sanitize_filename(upload.filename)}}
    end
  end

  defp check_size(path, max_bytes) do
    case File.stat(path) do
      {:ok, %{size: 0}} -> {:error, :empty}
      {:ok, %{size: size}} when size > max_bytes -> {:error, :too_large}
      {:ok, %{size: size}} -> {:ok, size}
      {:error, _} -> {:error, :empty}
    end
  end

  defp check_type(upload, allowed) do
    claimed = upload.content_type || "application/octet-stream"
    sniffed = sniff(upload.path)

    effective =
      case sniffed do
        {:ok, "application/zip"} -> if claimed in @zip_types, do: claimed, else: "application/zip"
        {:ok, type} -> type
        :unknown -> claimed
      end

    cond do
      # A claimed verifiable type must be confirmed by its signature —
      # bytes that disagree (or match nothing) mean a forged upload.
      claimed in @strict_types and sniffed != {:ok, claimed} ->
        {:error, :content_type_mismatch}

      effective in allowed ->
        {:ok, effective}

      true ->
        {:error, :unsupported_type}
    end
  end

  @doc """
  Detects the file's MIME type from its magic bytes. Returns
  `{:ok, type}` for the known signatures or `:unknown`.
  """
  @spec sniff(Path.t()) :: {:ok, String.t()} | :unknown
  def sniff(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 16)) do
      {:ok, header} when is_binary(header) -> sniff_bytes(header)
      _ -> :unknown
    end
  end

  defp sniff_bytes(<<0x89, "PNG", _::binary>>), do: {:ok, "image/png"}
  defp sniff_bytes(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, "image/jpeg"}
  defp sniff_bytes(<<"GIF8", _::binary>>), do: {:ok, "image/gif"}
  defp sniff_bytes(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: {:ok, "image/webp"}
  defp sniff_bytes(<<_::binary-size(4), "ftyp", _::binary>>), do: {:ok, "video/mp4"}
  defp sniff_bytes(<<0x1A, 0x45, 0xDF, 0xA3, _::binary>>), do: {:ok, "video/webm"}
  defp sniff_bytes(<<"%PDF", _::binary>>), do: {:ok, "application/pdf"}
  defp sniff_bytes(<<"PK", 0x03, 0x04, _::binary>>), do: {:ok, "application/zip"}
  defp sniff_bytes(_), do: :unknown

  @doc """
  Sanitizes a client-provided filename: basename only, control characters
  and path separators stripped, length-capped. Falls back to `"file"`.
  """
  @spec sanitize_filename(String.t() | nil) :: String.t()
  def sanitize_filename(nil), do: "file"

  def sanitize_filename(filename) do
    sanitized =
      filename
      # Treat both separators as path boundaries (clients may be on Windows).
      |> String.split(~r/[\/\\]/)
      |> List.last()
      |> String.replace(~r/[\x00-\x1f\x7f]/, "")
      |> String.trim()
      |> String.slice(0, 255)

    if sanitized == "", do: "file", else: sanitized
  end
end
