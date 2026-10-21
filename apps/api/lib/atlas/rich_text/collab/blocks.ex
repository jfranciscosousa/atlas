defmodule Atlas.RichText.Collab.Blocks do
  @moduledoc """
  Converts between the BlockNote block array and the Yjs document the editors share.

  `project/1` reads a Yjs document and returns BlockNote JSON. It accepts only the node shapes
  BlockNote writes and fails closed on anything else, because readers receive the whole Yjs
  state: a node that never reaches the JSON would also bypass the JSON validation.
  `seed/1` builds the Yjs document for a stored block array.

  Tests compare both directions with BlockNote's own output (`test/support/fixtures`).
  """

  alias Atlas.RichText.Document

  @fragment "document-store"
  @max_nodes 20_000
  @max_depth 24

  @color_props ~w(backgroundColor textColor textAlignment)
  @props %{
    "paragraph" => @color_props,
    "heading" => @color_props ++ ~w(level isToggleable),
    "quote" => ~w(backgroundColor textColor),
    "bulletListItem" => @color_props,
    "numberedListItem" => @color_props ++ ~w(start),
    "checkListItem" => @color_props ++ ~w(checked),
    "toggleListItem" => @color_props,
    "codeBlock" => ~w(language),
    "table" => ~w(textColor),
    "image" => ~w(textAlignment backgroundColor name url caption showPreview previewWidth),
    "divider" => []
  }
  @inline_blocks ~w(paragraph heading quote bulletListItem numberedListItem checkListItem
                    toggleListItem)
  @cell_props ~w(textColor backgroundColor textAlignment colspan rowspan)
  @cell_tags ~w(tableCell tableHeader)
  @simple_marks ~w(bold italic underline strike code)
  @color_marks ~w(textColor backgroundColor)
  @link_keys ~w(href target rel class)
  @id ~r/\A[A-Za-z0-9_-]{1,80}\z/

  @doc "Block types and the props each one accepts."
  def props, do: @props

  @doc "Name of the Yjs root that holds the document."
  def fragment, do: @fragment

  @doc """
  Returns the BlockNote blocks of a Yjs document, or `{:error, reason}` when the document is not
  one this schema accepts. The result still goes through `Atlas.RichText.Document`.
  """
  @spec project(Yex.Doc.t()) :: {:ok, [map()]} | {:error, atom()}
  def project(%Yex.Doc{} = doc) do
    with :ok <- check(Yex.Doc.get_pending_update(doc) == {:ok, nil}, :pending_update),
         :ok <- check(Yex.Doc.get_pending_ds(doc) == {:ok, nil}, :pending_delete_set),
         :ok <-
           check(
             Yex.Doc.root_refs(doc) in [[{@fragment, :untyped}], [{@fragment, :xml_fragment}]],
             :roots
           ) do
      read(doc)
    end
  catch
    {:invalid, reason} -> {:error, reason}
  end

  # A typed getter claims an untyped root, so read a copy and keep the candidate untouched.
  defp read(doc) do
    {:ok, state} = Yex.encode_state_as_update(doc)
    copy = Yex.Doc.new()
    :ok = Yex.apply_update(copy, state)

    # XML iteration skips root map entries, so look at them before claiming the root as XML.
    :ok = check(copy |> Yex.Doc.get_map(@fragment) |> Yex.Map.to_map() == %{}, :root_attributes)
    roots = copy |> Yex.Doc.get_array(@fragment) |> Yex.Array.to_list()
    :ok = check(length(roots) == 1, :root_shape)

    {blocks, _} = group(hd(roots), 0, 0)
    {:ok, blocks}
  end

  defp group(node, depth, count) do
    {tag, attrs, children} = element(node)
    :ok = check(tag == "blockGroup" and attrs == %{}, :block_group)
    :ok = check(depth <= @max_depth, :depth)
    Enum.map_reduce(children, count, &container(&1, depth + 1, &2))
  end

  defp container(node, depth, count) do
    {tag, attrs, children} = element(node)
    count = count + 1
    :ok = check(count <= @max_nodes, :node_limit)
    id = attrs["id"]
    :ok = check(tag == "blockContainer", :block_container)
    :ok = check(Map.keys(attrs) == ["id"] and is_binary(id) and Regex.match?(@id, id), :block_id)

    {content, nested} =
      case children do
        [content] -> {content, nil}
        [content, nested] -> {content, nested}
        _ -> throw({:invalid, :block_shape})
      end

    {block, count} = content(content, count)

    {descendants, count} =
      case nested do
        nil -> {[], count}
        nested -> group(nested, depth + 1, count)
      end

    {block |> Map.put("id", id) |> Map.put("children", descendants), count}
  end

  defp content(node, count) do
    {type, attrs, children} = element(node)
    allowed = Map.get(@props, type) || throw({:invalid, :block_type})
    props = props(attrs, allowed)

    case type do
      type when type in @inline_blocks ->
        {%{"type" => type, "props" => props, "content" => inline(children)}, count}

      "codeBlock" ->
        {%{"type" => type, "props" => props, "content" => plain(children)}, count}

      "table" ->
        table(props, children, count)

      _ ->
        :ok = check(children == [], :block_content)
        {%{"type" => type, "props" => props}, count}
    end
  end

  defp props(attrs, allowed) do
    :ok = check(Map.keys(attrs) -- allowed == [], :attribute)
    Map.new(attrs, fn {key, value} -> {key, scalar(value)} end)
  end

  # yrs reads every JavaScript number as a float.
  defp scalar(value) when is_float(value) and trunc(value) == value, do: trunc(value)
  defp scalar(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp scalar(nil), do: nil
  defp scalar(_), do: throw({:invalid, :attribute_value})

  defp table(props, rows, count) do
    {rows, count} =
      Enum.map_reduce(rows, count, fn row, count ->
        {tag, attrs, cells} = element(row)
        :ok = check(tag == "tableRow" and attrs == %{}, :table_row)
        Enum.map_reduce(cells, count, &cell/2)
      end)

    first = rows |> List.first([]) |> Enum.map(& &1.width)
    headers = Enum.map(rows, fn cells -> Enum.map(cells, & &1.header?) end)

    rows = Enum.map(rows, fn cells -> %{"cells" => Enum.map(cells, & &1.cell)} end)

    content =
      %{"type" => "tableContent", "columnWidths" => List.flatten(first), "rows" => rows}
      |> put_headers(headers)

    {%{"type" => "table", "props" => props, "content" => content}, count}
  end

  defp put_headers(content, headers) do
    header_rows = Enum.count(headers, &(&1 != [] and Enum.all?(&1)))

    header_cols =
      case headers do
        [first | _] ->
          first
          |> Enum.with_index()
          |> Enum.count(fn {_, col} -> Enum.all?(headers, &Enum.at(&1, col)) end)

        [] ->
          0
      end

    content
    |> then(&if header_rows > 0, do: Map.put(&1, "headerRows", header_rows), else: &1)
    |> then(&if header_cols > 0, do: Map.put(&1, "headerCols", header_cols), else: &1)
  end

  defp cell(node, count) do
    {tag, attrs, paragraphs} = element(node)
    :ok = check(tag in @cell_tags, :table_cell)
    :ok = check(Map.keys(attrs) -- ["colwidth" | @cell_props] == [], :attribute)
    colspan = scalar(Map.get(attrs, "colspan", 1))

    width =
      case Map.get(attrs, "colwidth") do
        nil -> List.duplicate(nil, colspan)
        widths when is_list(widths) -> Enum.map(widths, &width/1)
        _ -> throw({:invalid, :column_width})
      end

    content =
      paragraphs
      |> Enum.map(fn paragraph ->
        {tag, attrs, children} = element(paragraph)
        :ok = check(tag == "tableParagraph" and attrs == %{}, :table_paragraph)
        inline(children)
      end)
      |> Enum.intersperse([%{"type" => "text", "text" => "\n", "styles" => %{}}])
      |> Enum.concat()

    cell = %{
      "type" => "tableCell",
      "content" => content,
      "props" => attrs |> Map.take(@cell_props) |> Map.new(fn {k, v} -> {k, scalar(v)} end)
    }

    {%{cell: cell, width: width, header?: tag == "tableHeader"}, count + 1}
  end

  defp width(nil), do: nil
  defp width(value) when is_number(value), do: scalar(value)
  defp width(_), do: throw({:invalid, :column_width})

  # Inline content: XmlText runs, with hard breaks between them.
  defp inline(children) do
    children
    |> Enum.flat_map(fn
      %Yex.XmlText{} = text -> text(text)
      %Yex.XmlElement{} = node -> hard_break(node)
      _ -> throw({:invalid, :inline})
    end)
    |> merge()
    |> link_runs()
  end

  defp plain(children) do
    inline(children)
    |> Enum.map(fn
      %{"type" => "text"} = run -> run
      _ -> throw({:invalid, :plain_content})
    end)
  end

  defp hard_break(node) do
    {tag, attrs, children} = element(node)
    :ok = check(tag == "hardBreak" and attrs == %{} and children == [], :inline_element)
    [{"\n", %{}, nil}]
  end

  defp text(%Yex.XmlText{} = node) do
    :ok = check(Yex.XmlText.get_attributes(node) == %{}, :text_attributes)

    Enum.map(Yex.XmlText.to_delta(node), fn span ->
      :ok = check(Map.keys(span) -- [:insert, :attributes] == [], :delta)
      text = span[:insert]
      :ok = check(is_binary(text) and String.valid?(text), :embed)
      {styles, link} = marks(Map.get(span, :attributes, %{}))
      {text, styles, link}
    end)
  end

  defp marks(attrs) when is_map(attrs) do
    Enum.reduce(attrs, {%{}, nil}, fn
      {mark, value}, {styles, link} when mark in @simple_marks ->
        :ok = check(value == true or value == %{}, :mark)
        {Map.put(styles, mark, true), link}

      {mark, %{"stringValue" => value}}, {styles, link}
      when mark in @color_marks and is_binary(value) ->
        {Map.put(styles, mark, value), link}

      {"link", %{"href" => href} = value}, {styles, nil} when is_binary(href) ->
        :ok = check(Map.keys(value) -- @link_keys == [], :link)
        {styles, href}

      _, _ ->
        throw({:invalid, :mark})
    end)
  end

  defp marks(_), do: throw({:invalid, :mark})

  # Joins neighbouring runs that carry the same marks, as BlockNote does.
  defp merge(runs) do
    runs
    |> Enum.reject(fn {text, _, _} -> text == "" end)
    |> Enum.reduce([], fn
      {text, styles, link}, [{previous, styles, link} | rest] ->
        [{previous <> text, styles, link} | rest]

      run, acc ->
        [run | acc]
    end)
    |> Enum.reverse()
  end

  # Runs with the same link become one link node.
  defp link_runs(runs) do
    runs
    |> Enum.chunk_by(fn {_, _, link} -> link end)
    |> Enum.flat_map(fn
      [{_, _, nil} | _] = plain ->
        Enum.map(plain, fn {text, styles, _} ->
          %{"type" => "text", "text" => text, "styles" => styles}
        end)

      [{_, _, href} | _] = linked ->
        [
          %{
            "type" => "link",
            "href" => href,
            "content" =>
              Enum.map(linked, fn {text, styles, _} ->
                %{"type" => "text", "text" => text, "styles" => styles}
              end)
          }
        ]
    end)
  end

  defp element(%Yex.XmlElement{} = node) do
    children = Enum.to_list(Yex.XmlElement.children(node))
    # yrs stops iterating at a child that is not an XML node, which would hide it.
    :ok = check(length(children) == Yex.XmlElement.length(node), :hidden_child)
    {Yex.XmlElement.get_tag(node), Yex.XmlElement.get_attributes(node), children}
  end

  defp element(_), do: throw({:invalid, :node})

  defp check(true, _), do: :ok
  defp check(false, reason), do: throw({:invalid, reason})

  @doc """
  Builds the Yjs document for a stored block array. An empty array becomes one empty paragraph,
  which is the document BlockNote shows for it. The block ID is new.
  """
  @spec seed([map()]) :: Yex.Doc.t()
  def seed(blocks) when is_list(blocks) do
    blocks = if blocks == [], do: [empty_paragraph()], else: blocks
    doc = Yex.Doc.new()
    fragment = Yex.Doc.get_xml_fragment(doc, @fragment)
    :ok = Yex.XmlFragment.push(fragment, group_prelim(blocks))
    doc
  end

  defp empty_paragraph do
    %{"id" => Ash.UUID.generate(), "type" => "paragraph", "props" => %{}, "children" => []}
  end

  defp group_prelim(blocks) do
    Yex.XmlElementPrelim.new("blockGroup", Enum.map(blocks, &container_prelim/1))
  end

  defp container_prelim(%{"id" => id} = block) do
    nested =
      case block["children"] || [] do
        [] -> []
        children -> [group_prelim(children)]
      end

    Yex.XmlElementPrelim.new("blockContainer", [content_prelim(block) | nested], %{"id" => id})
  end

  defp content_prelim(%{"type" => "table"} = block) do
    content = block["content"]
    widths = content["columnWidths"] || []
    header_rows = content["headerRows"] || 0
    header_cols = content["headerCols"] || 0

    rows =
      content["rows"]
      |> Enum.with_index()
      |> Enum.map(fn {row, r} ->
        cells =
          row["cells"]
          |> Enum.with_index()
          |> Enum.map(fn {cell, c} ->
            tag = if r < header_rows or c < header_cols, do: "tableHeader", else: "tableCell"
            cell_prelim(tag, cell, widths, c)
          end)

        Yex.XmlElementPrelim.new("tableRow", cells)
      end)

    Yex.XmlElementPrelim.new("table", rows, known_props(block))
  end

  defp content_prelim(%{"type" => type} = block) do
    children =
      case block["content"] do
        content when is_list(content) -> inline_prelims(content, type != "codeBlock")
        _ -> []
      end

    Yex.XmlElementPrelim.new(type, children, known_props(block))
  end

  # Stored JSON may carry props the block does not have (older saves, imports). BlockNote ignores
  # them, and the projection rejects them, so seeding leaves them out.
  defp known_props(%{"type" => type} = block),
    do: Map.take(block["props"] || %{}, Map.fetch!(@props, type))

  defp cell_prelim(tag, cell, widths, col) do
    {props, content} =
      case cell do
        %{"content" => content} -> {Map.take(cell["props"] || %{}, @cell_props), content}
        content when is_list(content) -> {%{}, content}
      end

    colspan = props["colspan"] || 1
    span = widths |> Enum.slice(col, colspan) |> Enum.reject(&is_nil/1)
    attrs = if span == [], do: props, else: Map.put(props, "colwidth", span)

    # A cell holds one paragraph per line, split on the newlines that `project/1` joins with.
    paragraphs =
      content
      |> split_lines()
      |> Enum.map(&Yex.XmlElementPrelim.new("tableParagraph", inline_prelims(&1)))

    Yex.XmlElementPrelim.new(tag, paragraphs, attrs)
  end

  defp split_lines(content) do
    Enum.reduce(content, [[]], fn
      %{"type" => "text", "text" => text} = run, [line | lines] ->
        [first | rest] = String.split(text, "\n")

        Enum.reduce(rest, [line ++ [%{run | "text" => first}] | lines], fn part, acc ->
          [[%{run | "text" => part}] | acc]
        end)

      run, [line | lines] ->
        [line ++ [run] | lines]
    end)
    |> Enum.reverse()
  end

  # Text becomes XmlText runs with marks as attributes. A newline becomes a hard break element.
  defp inline_prelims(content, breaks? \\ true) do
    content
    |> Enum.flat_map(fn
      %{"type" => "link", "href" => href, "content" => runs} ->
        Enum.map(runs, &{&1, %{"link" => %{"href" => href}}})

      run ->
        [{run, %{}}]
    end)
    |> Enum.flat_map(fn {%{"text" => text} = run, extra} ->
      marks = Map.merge(styles_to_marks(run["styles"] || %{}), extra)

      text
      |> split_breaks(breaks?)
      |> Enum.intersperse(:break)
      |> Enum.map(fn
        :break -> :break
        part -> {part, marks}
      end)
    end)
    |> Enum.chunk_by(&(&1 == :break))
    |> Enum.flat_map(fn
      [:break | _] = breaks ->
        Enum.map(breaks, fn _ -> Yex.XmlElementPrelim.empty("hardBreak") end)

      parts ->
        case Enum.reject(parts, fn {text, _} -> text == "" end) do
          [] -> []
          parts -> [Yex.XmlTextPrelim.from(Enum.map(parts, &delta/1))]
        end
    end)
  end

  # Code blocks keep newlines as plain text.
  defp split_breaks(text, true), do: String.split(text, "\n")
  defp split_breaks(text, false), do: [text]

  defp delta({text, marks}) when marks == %{}, do: %{insert: text}
  defp delta({text, marks}), do: %{insert: text, attributes: marks}

  defp styles_to_marks(styles) do
    Map.new(styles, fn
      {mark, true} when mark in @simple_marks ->
        {mark, %{}}

      {mark, value} when mark in @color_marks and is_binary(value) ->
        {mark, %{"stringValue" => value}}
    end)
  end

  @doc "Validates projected blocks with the same rules as a saved document."
  @spec validate([map()]) :: {:ok, [map()]} | {:error, term()}
  def validate(blocks), do: Document.cast_input(blocks, [])
end
