defmodule EmbeddingGenerator.Types.Vector do
  use Ecto.Type

  def type, do: :vector

  def cast(vector) when is_list(vector), do: {:ok, vector}
  def cast(_), do: :error

  def load(data), do: {:ok, data}

  def dump(vector) when is_list(vector), do: {:ok, vector}
  def dump(_), do: :error
end
