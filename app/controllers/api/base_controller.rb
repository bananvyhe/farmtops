module Api
  class BaseController < ApplicationController
    skip_forgery_protection
    before_action :verify_frontend_csrf!

    private

    def render_error(message, status:)
      render json: { error: message }, status:
    end

    def ensure_authenticated!
      return if user_signed_in?

      render_error("Authentication required", status: :unauthorized)
    end

    def ensure_admin!
      return if current_user&.admin?

      render_error("Admin access required", status: :forbidden)
    end

    def user_payload(user)
      {
        id: user.id,
        email: user.email,
        role: user.role,
        active: user.active,
        balance_cents: user.balance_cents,
        tariff_id: user.tariff_id,
        tariff_name: user.tariff_name,
        hourly_rate_cents: user.effective_hourly_rate_cents,
        manual_hourly_rate_cents: user.hourly_rate_cents,
        remaining_days: user.remaining_days,
        last_hourly_charge_at: user.last_hourly_charge_at
      }
    end

    def tariff_payload(tariff)
      {
        id: tariff.id,
        name: tariff.name,
        monthly_price_cents: tariff.monthly_price_cents,
        hourly_rate_cents: tariff.hourly_rate_cents,
        billing_period_days: tariff.billing_period_days,
        description: tariff.description,
        active: tariff.active
      }
    end

    def payment_payload(payment)
      {
        id: payment.id,
        label: payment.label,
        status: payment.status,
        requested_amount_cents: payment.requested_amount_cents,
        credited_amount_cents: payment.credited_amount_cents,
        provider_net_amount_cents: payment.provider_net_amount_cents,
        paid_at: payment.paid_at,
        created_at: payment.created_at
      }
    end

    def ledger_payload(entry)
      {
        id: entry.id,
        kind: entry.kind,
        amount_cents: entry.amount_cents,
        balance_after_cents: entry.balance_after_cents,
        metadata: entry.metadata,
        created_at: entry.created_at
      }
    end

    def news_source_payload(source)
      {
        id: source.id,
        name: source.name,
        base_url: source.base_url,
        active: source.active,
        crawl_delay_min_seconds: source.crawl_delay_min_seconds,
        crawl_delay_max_seconds: source.crawl_delay_max_seconds,
        config: source.config,
        sections: source.news_sections.order(:name).map { |section| news_section_payload(section) },
        last_crawl_run: news_crawl_run_payload(source.news_crawl_runs.order(started_at: :desc).first)
      }
    end

    def news_section_payload(section)
      {
        id: section.id,
        news_source_id: section.news_source_id,
        source_name: section.news_source.name,
        name: section.name,
        url: section.url,
        active: section.active,
        config: section.config,
        last_crawled_at: section.last_crawled_at,
        articles_count: section.news_articles.size
      }
    end

    def news_article_payload(article)
      {
        id: article.id,
        news_source_id: article.news_source_id,
        news_section_id: article.news_section_id,
        source_name: article.news_source.name,
        section_name: article.news_section.name,
        source_article_id: article.source_article_id,
        canonical_url: article.canonical_url,
        title: article.title,
        preview_text: article.preview_text,
        preview_html: sanitized_news_html(article.preview_html),
        body_text: article.body_text,
        body_html: sanitized_news_html(article.body_html),
        image_url: news_article_image_url(article),
        published_at: article.published_at,
        fetched_at: article.fetched_at,
        translated_at: article.translated_at,
        translation_model: article.translation_model,
        translation_status: article.translation_status,
        translation_error: article.translation_error,
        translation_started_at: article.translation_started_at,
        translation_completed_at: article.translation_completed_at,
        translation_request_id: article.translation_request_id,
        translation_attempts: article.translation_attempts,
        translation_target_locale: article.translation_target_locale,
        translation_source_locale: article.translation_source_locale,
        content_hash: article.content_hash,
        raw_payload: article.raw_payload
      }
    end

    def sanitized_news_html(html)
      ActionController::Base.helpers.sanitize(
        html.to_s,
        tags: %w[p br div span strong em b i u s ul ol li blockquote figure figcaption a img h1 h2 h3 h4 h5 h6 iframe video source],
        attributes: %w[href src alt title width height class style allow allowfullscreen frameborder loading referrerpolicy rel target data-src data-lazy-src poster]
      )
    end

    def news_article_image_url(article)
      return if article.image_url.blank?

      "/api/news/#{article.id}/image"
    end

    def news_crawl_run_payload(run)
      return unless run

      {
        id: run.id,
        news_source_id: run.news_source_id,
        news_section_id: run.news_section_id,
        status: run.status,
        started_at: run.started_at,
        finished_at: run.finished_at,
        pages_visited: run.pages_visited,
        articles_found: run.articles_found,
        articles_saved: run.articles_saved,
        articles_skipped: run.articles_skipped,
        crawl_errors: run.crawl_errors,
        metadata: run.metadata
      }
    end
  end
end
