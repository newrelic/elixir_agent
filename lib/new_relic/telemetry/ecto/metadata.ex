defmodule NewRelic.Telemetry.Ecto.Metadata do
  @moduledoc false

  def parse(%{result: {:ok, %{__struct__: Postgrex.Cursor}}}), do: :ignore
  def parse(%{result: {:ok, %{__struct__: MyXQL.Cursor}}}), do: :ignore

  def parse(%{query: query, result: {_ok_err, %{__struct__: struct}}})
      when struct in [Postgrex.Result, Postgrex.Error] do
    {"Postgres", parse_query(query)}
  end

  def parse(%{query: query, result: {_ok_err, %{__struct__: struct}}})
      when struct in [MyXQL.Result, MyXQL.Error] do
    {"MySQL", parse_query(query)}
  end

  def parse(%{query: query, repo: repo, result: {_ok_err, %{__struct__: _struct}}}) do
    [adaapter | _] = repo.__adapter__() |> Module.split() |> Enum.reverse()
    {adaapter, parse_query(query)}
  end

  def parse(%{result: {:ok, _}}), do: :ignore
  def parse(%{result: {:error, _}}), do: :ignore

  def parse_query(query) do
    case query do
      "SELECT" <> _ -> parse_query(:select, query)
      "INSERT" <> _ -> parse_query(:insert, query)
      "UPDATE" <> _ -> parse_query(:update, query)
      "DELETE" <> _ -> parse_query(:delete, query)
      "CREATE TABLE" <> _ -> parse_query(:create, query)
      "begin" -> {:begin, :other}
      "commit" -> {:commit, :other}
      "rollback" -> {:rollback, :other}
      _ -> {:other, :other}
    end
  end

  # Table name escaping
  #   Postgrex: "table"
  #   MyXQL: `table`
  #   Tds: [table]
  #   Exqlite: table
  @esc ~w(" ` [ ])

  @capture %{
    select: ~r/FROM (?<table>\S+)/,
    insert: ~r/INSERT INTO (?<table>\S+)/,
    update: ~r/UPDATE (?<table>\S+)/,
    delete: ~r/FROM (?<table>\S+)/,
    create: ~r/CREATE TABLE( IF NOT EXISTS)? (?<table>\S+)/
  }
  def parse_query(operation, query) do
    case Regex.named_captures(@capture[operation], query) do
      %{"table" => table} -> {operation, String.replace(table, @esc, "")}
      _ -> {operation, :other}
    end
  end
end
