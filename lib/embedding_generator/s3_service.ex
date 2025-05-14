defmodule EmbeddingGenerator.S3Service do
  require Logger

  def download_file(s3_url) do
    # Parse the S3 URL to extract the path
    path = extract_path_from_url(s3_url)

    Logger.info("Downloading file from S3: #{path}")

    # Download the file from S3
    {:ok, %{body: image_binary}} =
      ExAws.S3.get_object(System.get_env("BUCKET_NAME"), path)
      |> ExAws.request()

    # Return the binary data
    image_binary
  end

  defp extract_path_from_url(s3_url) do
    # Extract the path from the S3 URL
    # Example: https://bucket-name.nyc3.digitaloceanspaces.com/path/to/image.jpg
    # Returns: path/to/image.jpg
    uri = URI.parse(s3_url)
    String.replace_prefix(uri.path, "/", "")
  end
end
