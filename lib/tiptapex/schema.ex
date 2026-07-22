if Code.ensure_loaded?(Ecto.Type) do
  defmodule Tiptapex.Schema.Document do
    @moduledoc """
    An `Ecto.Type` for Tiptap/ProseMirror JSON documents.

    Stores the document as a map (`:map` column / `jsonb` in Postgres) and
    accepts either an already-decoded map or a JSON string — the latter is
    what arrives through a hidden-input form field
    (`sync={{:hidden_input, field}}` on `tiptapex_editor/1`).

        schema "articles" do
          field :body, Tiptapex.Schema.Document
        end

    Only available when `:ecto` is present (it is an optional dependency).
    """

    use Ecto.Type

    @impl true
    def type, do: :map

    @impl true
    def cast(nil), do: {:ok, nil}

    def cast(doc) when is_map(doc) do
      if valid_doc?(doc), do: {:ok, doc}, else: :error
    end

    def cast(json) when is_binary(json) do
      case Jason.decode(json) do
        {:ok, doc} when is_map(doc) -> cast(doc)
        _ -> :error
      end
    end

    def cast(_), do: :error

    @impl true
    def load(doc) when is_map(doc), do: {:ok, doc}
    def load(_), do: :error

    @impl true
    def dump(doc) when is_map(doc), do: {:ok, doc}
    def dump(nil), do: {:ok, nil}
    def dump(_), do: :error

    # A doc is either empty or has "type" => "doc". Atom-keyed maps are
    # normalized by Jason on dump, so accept both key styles.
    defp valid_doc?(doc) when doc == %{}, do: true
    defp valid_doc?(%{"type" => "doc"}), do: true
    defp valid_doc?(%{type: "doc"}), do: true
    defp valid_doc?(_), do: false
  end
end
