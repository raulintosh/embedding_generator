defmodule EmbeddingGenerator.Schema.Image do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "images" do
    field :base64_content, :string
    field :longitude, :float
    field :latitude, :float
    field :user_id, :integer
    field :s3_url, :string
    field :embedding, EmbeddingGenerator.Types.Vector

    timestamps()
  end

  def changeset(image, attrs) do
    image
    |> cast(attrs, [:base64_content, :longitude, :latitude, :user_id, :s3_url, :embedding])
    |> validate_required([:user_id])
  end
end
