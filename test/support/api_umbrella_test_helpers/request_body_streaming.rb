module ApiUmbrellaTestHelpers
  module RequestBodyStreaming
    def make_streaming_body_request(request_body_chunks, url: "http://127.0.0.1:9080/api/request-body-streaming/")
      easy = Ethon::Easy.new
      easy.http_request(url, :put)
      easy.headers = {
        "Transfer-Encoding" => "chunked",
        "X-Api-Key" => http_options.fetch(:headers).fetch("X-Api-Key"),
      }
      easy.readfunction do |stream, size, num, object|
        chunk = request_body_chunks.shift
        if chunk
          sleep chunk.fetch(:sleep)
          size = chunk.fetch(:data).bytesize
          stream.write_string(chunk.fetch(:data), size)
        else
          size = 0
        end

        size
      end
      easy.infilesize = request_body_chunks.map { |c| c.fetch(:data) }.join("").bytesize
      easy.perform

      easy
    end
  end
end
