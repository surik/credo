defmodule Credo.Code.Heredocs do
  @moduledoc """
  This module lets you strip heredocs from source code.
  """

  alias Credo.Code.InterpolationHelper
  alias Credo.SourceFile

  @alphabet ~w(a b c d e f g h i j k l m n o p q r s t u v w x y z)
  @sigil_delimiters [
    {"(", ")"},
    {"[", "]"},
    {"{", "}"},
    {"<", ">"},
    {"|", "|"},
    {"/", "/"},
    {"\"", "\""},
    {"'", "'"}
  ]
  @all_sigil_chars Enum.flat_map(@alphabet, fn a ->
                     [a, String.upcase(a)]
                   end)
  @all_sigil_starts Enum.map(@all_sigil_chars, fn c -> "~#{c}" end)

  @non_removable_normal_sigils @sigil_delimiters
                               |> Enum.flat_map(fn {b, e} ->
                                 Enum.flat_map(@all_sigil_starts, fn start ->
                                   [{"#{start}#{b}", e}, {"#{start}#{b}", e}]
                                 end)
                               end)
                               |> Enum.uniq()

  @removable_heredoc_sigil_delimiters [
    {"\"\"\"", "\"\"\""},
    {"'''", "'''"}
  ]
  @removable_heredoc_sigils @removable_heredoc_sigil_delimiters
                            |> Enum.flat_map(fn {b, e} ->
                              Enum.flat_map(@all_sigil_starts, fn start ->
                                [{"#{start}#{b}", e}, {"#{start}#{b}", e}]
                              end)
                            end)
                            |> Enum.uniq()

  @doc """
  Replaces all characters inside heredocs
  with the equivalent amount of white-space.
  """
  def replace_with_spaces(
        source_file,
        replacement \\ " ",
        interpolation_replacement \\ " ",
        empty_line_replacement \\ "",
        filename \\ "nofilename"
      ) do
    {source, filename} = SourceFile.source_and_filename(source_file, filename)

    source
    |> InterpolationHelper.replace_interpolations(interpolation_replacement, filename)
    |> parse_code("", replacement, empty_line_replacement)
  end

  defp parse_code("", acc, _replacement, _empty_line_replacement) do
    acc
  end

  for {sigil_start, sigil_end} <- @removable_heredoc_sigils do
    defp parse_code(
           <<unquote(sigil_start)::utf8, t::binary>>,
           acc,
           replacement,
           empty_line_replacement
         ) do
      parse_removable_heredoc_sigil(
        t,
        acc <> unquote(sigil_start),
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end
  end

  for {sigil_start, sigil_end} <- @non_removable_normal_sigils do
    defp parse_code(
           <<unquote(sigil_start)::utf8, t::binary>>,
           acc,
           replacement,
           empty_line_replacement
         ) do
      parse_non_removable_normal_sigil(
        t,
        acc <> unquote(sigil_start),
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end
  end

  defp parse_code(<<"\"\"\""::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_heredoc(t, acc <> ~s("""), replacement, empty_line_replacement, ~s("""))
  end

  defp parse_code(<<"\'\'\'"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_heredoc(t, acc <> ~s('''), replacement, empty_line_replacement, ~s('''))
  end

  defp parse_code(<<"\\\""::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_code(t, acc <> "\\\"", replacement, empty_line_replacement)
  end

  defp parse_code(<<"#"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_comment(t, acc <> "#", replacement, empty_line_replacement)
  end

  defp parse_code(<<"?\""::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_code(t, acc <> "?\"", replacement, empty_line_replacement)
  end

  defp parse_code(<<"?'"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_code(t, acc <> "?\'", replacement, empty_line_replacement)
  end

  defp parse_code(<<"'"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_charlist(t, acc <> "'", replacement, empty_line_replacement)
  end

  defp parse_code(<<"\""::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_string_literal(t, acc <> "\"", replacement, empty_line_replacement)
  end

  defp parse_code(<<h::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_code(t, acc <> <<h::utf8>>, replacement, empty_line_replacement)
  end

  defp parse_code(str, acc, replacement, empty_line_replacement) when is_binary(str) do
    {h, t} = String.next_codepoint(str)

    parse_code(t, acc <> h, replacement, empty_line_replacement)
  end

  #
  # Charlists
  #

  defp parse_charlist("", acc, _replacement, _empty_line_replacement) do
    acc
  end

  defp parse_charlist(<<"\\\\"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_charlist(t, acc <> "\\\\", replacement, empty_line_replacement)
  end

  defp parse_charlist(<<"\\\'"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_charlist(t, acc <> "\\\'", replacement, empty_line_replacement)
  end

  defp parse_charlist(<<"\'"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_code(t, acc <> "'", replacement, empty_line_replacement)
  end

  defp parse_charlist(<<"\n"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_charlist(t, acc <> "\n", replacement, empty_line_replacement)
  end

  defp parse_charlist(str, acc, replacement, empty_line_replacement) when is_binary(str) do
    {h, t} = String.next_codepoint(str)

    parse_comment(t, acc <> h, replacement, empty_line_replacement)
  end

  #
  # Comments
  #

  defp parse_comment("", acc, _replacement, _empty_line_replacement) do
    acc
  end

  defp parse_comment(<<"\n"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_code(t, acc <> "\n", replacement, empty_line_replacement)
  end

  defp parse_comment(str, acc, replacement, empty_line_replacement) when is_binary(str) do
    {h, t} = String.next_codepoint(str)

    parse_comment(t, acc <> h, replacement, empty_line_replacement)
  end

  #
  # "Normal" Sigils (e.g. `~S"..."` or `~s(...)`)
  #

  for {_sigil_start, sigil_end} <- @non_removable_normal_sigils do
    defp parse_non_removable_normal_sigil(
           "",
           acc,
           unquote(sigil_end),
           _replacement,
           _empty_line_replacement
         ) do
      acc
    end

    defp parse_non_removable_normal_sigil(
           <<"\\\\"::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      parse_non_removable_normal_sigil(
        t,
        acc,
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end

    defp parse_non_removable_normal_sigil(
           <<unquote("\\#{sigil_end}")::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      parse_non_removable_normal_sigil(
        t,
        acc <> replacement <> replacement,
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end

    defp parse_non_removable_normal_sigil(
           <<unquote(sigil_end)::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      parse_code(t, acc <> unquote(sigil_end), replacement, empty_line_replacement)
    end

    defp parse_non_removable_normal_sigil(
           <<"\n"::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      parse_non_removable_normal_sigil(
        t,
        acc <> "\n",
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end

    defp parse_non_removable_normal_sigil(
           str,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      {h, t} = String.next_codepoint(str)

      parse_non_removable_normal_sigil(
        t,
        acc <> h,
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end
  end

  #
  # Removable Sigils (e.g. `~S"""`)
  #

  for {_sigil_start, sigil_end} <- @removable_heredoc_sigils do
    defp parse_removable_heredoc_sigil(
           "",
           acc,
           unquote(sigil_end),
           _replacement,
           _empty_line_replacement
         ) do
      acc
    end

    defp parse_removable_heredoc_sigil(
           <<"\\\\"::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      parse_removable_heredoc_sigil(
        t,
        acc,
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end

    defp parse_removable_heredoc_sigil(
           <<unquote("\\#{sigil_end}")::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      parse_removable_heredoc_sigil(
        t,
        acc <> replacement <> replacement,
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end

    defp parse_removable_heredoc_sigil(
           <<unquote(sigil_end)::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      acc = pad_replaced_heredoc(acc, unquote(sigil_end))

      parse_code(t, acc <> unquote(sigil_end), replacement, empty_line_replacement)
    end

    defp parse_removable_heredoc_sigil(
           <<"\n"::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      parse_removable_heredoc_sigil(
        t,
        acc <> "\n",
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end

    defp parse_removable_heredoc_sigil(
           <<_::utf8, t::binary>>,
           acc,
           unquote(sigil_end),
           replacement,
           empty_line_replacement
         ) do
      parse_removable_heredoc_sigil(
        t,
        acc <> replacement,
        unquote(sigil_end),
        replacement,
        empty_line_replacement
      )
    end
  end

  #
  # Heredocs
  #

  defp parse_heredoc("", acc, _replacement, _empty_line_replacement, _here_doc_delimiter) do
    acc
  end

  defp parse_heredoc(
         <<"\\\\"::utf8, t::binary>>,
         acc,
         replacement,
         empty_line_replacement,
         here_doc_delimiter
       ) do
    parse_heredoc(t, acc, replacement, empty_line_replacement, here_doc_delimiter)
  end

  defp parse_heredoc(
         <<"\\\""::utf8, t::binary>>,
         acc,
         replacement,
         empty_line_replacement,
         here_doc_delimiter
       ) do
    parse_heredoc(t, acc, replacement, empty_line_replacement, here_doc_delimiter)
  end

  defp parse_heredoc(
         <<"\"\"\""::utf8, t::binary>>,
         acc,
         replacement,
         empty_line_replacement,
         "\"\"\""
       ) do
    acc = pad_replaced_heredoc(acc, ~s("""))

    parse_code(t, acc <> ~s("""), replacement, empty_line_replacement)
  end

  defp parse_heredoc(
         <<"\'\'\'"::utf8, t::binary>>,
         acc,
         replacement,
         empty_line_replacement,
         "\'\'\'"
       ) do
    acc = pad_replaced_heredoc(acc, ~s('''))

    parse_code(t, acc <> ~s('''), replacement, empty_line_replacement)
  end

  defp parse_heredoc(
         <<"\n"::utf8, t::binary>>,
         acc,
         replacement,
         empty_line_replacement,
         here_doc_delimiter
       ) do
    end_of_empty_line? = String.slice(acc, -1..-1) == "\n"

    acc =
      if end_of_empty_line? do
        acc <> empty_line_replacement
      else
        acc
      end

    parse_heredoc(t, acc <> "\n", replacement, empty_line_replacement, here_doc_delimiter)
  end

  defp parse_heredoc(
         <<_::utf8, t::binary>>,
         acc,
         replacement,
         empty_line_replacement,
         here_doc_delimiter
       ) do
    parse_heredoc(t, acc <> replacement, replacement, empty_line_replacement, here_doc_delimiter)
  end

  #
  # String Literals
  #

  defp parse_string_literal("", acc, _replacement, _empty_line_replacement) do
    acc
  end

  defp parse_string_literal(<<"\\\\"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_string_literal(t, acc <> "\\\\", replacement, empty_line_replacement)
  end

  defp parse_string_literal(<<"\\\""::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_string_literal(t, acc <> "\\\"", replacement, empty_line_replacement)
  end

  defp parse_string_literal(<<"\""::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_code(t, acc <> ~s("), replacement, empty_line_replacement)
  end

  defp parse_string_literal(<<"\n"::utf8, t::binary>>, acc, replacement, empty_line_replacement) do
    parse_string_literal(t, acc <> "\n", replacement, empty_line_replacement)
  end

  defp parse_string_literal(str, acc, replacement, empty_line_replacement) when is_binary(str) do
    {h, t} = String.next_codepoint(str)

    parse_string_literal(t, acc <> h, replacement, empty_line_replacement)
  end

  defp pad_replaced_heredoc(acc, delimiter) do
    no_of_chars_to_replace =
      if acc =~ ~r/\n\Z/m do
        0
      else
        [leading_string] = Regex.run(~r/[^\n]*\Z/m, acc)

        String.length(leading_string)
      end

    pad_string = "\n" <> String.pad_leading("", no_of_chars_to_replace)

    {byte_index, _match_size} =
      Regex.scan(~r/#{delimiter}/m, acc, return: :index)
      |> List.last()
      |> List.first()

    length_after_byte_index = byte_size(acc) - byte_index

    new_acc =
      acc
      |> :binary.part(byte_index, length_after_byte_index)
      |> String.replace(~r/\n(.{#{no_of_chars_to_replace}})/, pad_string)

    :binary.part(acc, 0, byte_index) <> new_acc
  end
end
