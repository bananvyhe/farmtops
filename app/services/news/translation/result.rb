module News
  module Translation
    Result = Struct.new(
      :request_id,
      :translated_title,
      :translated_preview_text,
      :translated_body_text,
      :model,
      :latency_ms,
      :status,
      :error,
      keyword_init: true
    )
  end
end
