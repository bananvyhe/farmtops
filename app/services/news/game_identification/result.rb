module News
  module GameIdentification
    Result = Struct.new(
      :request_id,
      :article_id,
      :status,
      :identified_game_name,
      :confidence,
      :model,
      :external_game_id,
      :slug,
      :error,
      keyword_init: true
    )
  end
end
