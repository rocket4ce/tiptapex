defmodule Tiptapex.Upload.ValidatorTest do
  use ExUnit.Case, async: true

  alias Tiptapex.Upload.Validator

  @png_header <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0::size(64)>>
  @jpeg_header <<0xFF, 0xD8, 0xFF, 0xE0, 0::size(96)>>
  @zip_header <<"PK", 0x03, 0x04, 0::size(96)>>

  defp upload(tmp_dir, bytes, filename, content_type) do
    path = Path.join(tmp_dir, "upload-#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  describe "validate/2" do
    @describetag :tmp_dir

    test "accepts a genuine PNG", %{tmp_dir: tmp} do
      assert {:ok, %{content_type: "image/png", filename: "pic.png", size: size}} =
               Validator.validate(upload(tmp, @png_header, "pic.png", "image/png"))

      assert size == byte_size(@png_header)
    end

    test "rejects a forged PNG (claimed image, text bytes)", %{tmp_dir: tmp} do
      assert {:error, :content_type_mismatch} =
               Validator.validate(upload(tmp, "just text", "pic.png", "image/png"))
    end

    test "rejects a claimed JPEG with PNG bytes", %{tmp_dir: tmp} do
      assert {:error, :content_type_mismatch} =
               Validator.validate(upload(tmp, @png_header, "pic.jpg", "image/jpeg"))
    end

    test "sniffed type wins over a lying non-strict claim", %{tmp_dir: tmp} do
      # Client claims text/plain but sends a real JPEG: effective type is the
      # sniffed one, which must be in the allow-list.
      assert {:ok, %{content_type: "image/jpeg"}} =
               Validator.validate(
                 upload(tmp, @jpeg_header, "note.txt", "text/plain"),
                 allowed: ~w(image/jpeg text/plain)
               )
    end

    test "unsniffable type allowed by list passes with claimed type", %{tmp_dir: tmp} do
      assert {:ok, %{content_type: "text/plain"}} =
               Validator.validate(
                 upload(tmp, "hello", "note.txt", "text/plain"),
                 allowed: ~w(text/plain)
               )
    end

    test "unsniffable type not in the allow-list is rejected", %{tmp_dir: tmp} do
      assert {:error, :unsupported_type} =
               Validator.validate(upload(tmp, "hello", "note.txt", "text/plain"))
    end

    test "zip-based office types keep the claimed type", %{tmp_dir: tmp} do
      docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

      assert {:ok, %{content_type: ^docx}} =
               Validator.validate(upload(tmp, @zip_header, "doc.docx", docx), allowed: [docx])
    end

    test "rejects oversize files", %{tmp_dir: tmp} do
      assert {:error, :too_large} =
               Validator.validate(upload(tmp, @png_header, "pic.png", "image/png"),
                 max_bytes: 4
               )
    end

    test "rejects empty files", %{tmp_dir: tmp} do
      assert {:error, :empty} = Validator.validate(upload(tmp, "", "pic.png", "image/png"))
    end
  end

  describe "sanitize_filename/1" do
    test "strips paths, control characters, and separators" do
      assert Validator.sanitize_filename("../../etc/passwd") == "passwd"
      assert Validator.sanitize_filename("a\x00b.png") == "ab.png"
      assert Validator.sanitize_filename("dir\\file.txt") == "file.txt"
      assert Validator.sanitize_filename(nil) == "file"
      assert Validator.sanitize_filename("   ") == "file"
    end

    test "caps length at 255" do
      long = String.duplicate("a", 300) <> ".png"
      assert String.length(Validator.sanitize_filename(long)) == 255
    end
  end
end
