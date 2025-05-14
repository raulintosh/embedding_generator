defmodule EmbeddingGenerator.OllamaService do
  require Logger

  @base_url "http://localhost:11434"
  @model "llama3.2-vision"

  def generate_embedding(image_base64) do
    Logger.info("Generating embedding using Ollama model: #{@model}")

    # Prepare the request payload
    payload = %{
      model: @model,
      prompt: image_base64
    }

    # Make the API call to Ollama
    {:ok, response} =
      Finch.build(
        :post,
        "#{@base_url}/api/embed",
        [{"Content-Type", "application/json"}],
        Jason.encode!(payload)
      )
      |> Finch.request(EmbeddingGenerator.Finch)

    # Parse the response
    {:ok, body} = Jason.decode(response.body)

    # Extract the embedding vector
    embedding = body["embedding"]

    Logger.info("Successfully generated embedding with #{length(embedding)} dimensions")

    embedding
  end
end
