class NewsGameBookmark < ApplicationRecord
  belongs_to :game
  belongs_to :user, optional: true

  validates :bookmarked_at, presence: true
  validates :visitor_uuid, presence: true, unless: :user_id?
  validates :user_id, uniqueness: { scope: :game_id, allow_nil: true }
  validates :visitor_uuid, uniqueness: { scope: :game_id, allow_nil: true }

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :for_visitor, ->(visitor_uuid) { where(visitor_uuid:) }

  def self.identity_for(user: nil, visitor_uuid: nil)
    if user.present?
      where(user_id: user.id)
    elsif visitor_uuid.present?
      where(visitor_uuid:)
    else
      none
    end
  end
end
