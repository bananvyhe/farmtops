module Admin
  class DbTablesController < ApplicationController
    before_action :require_authentication
    before_action :require_admin!
    before_action :ensure_local_environment!
    before_action :set_table_name, only: %i[show edit update]
    before_action :set_record, only: %i[edit update]

    helper_method :table_names, :table_columns, :editable_columns, :column_value, :column_input_type, :record_display_value

    def index
      @table_names = table_names
    end

    def show
      @page = params.fetch(:page, 1).to_i
      @per_page = params.fetch(:per_page, 50).to_i.clamp(1, 100)
      @columns = table_columns
      @records = model_class.order(primary_key_name => :desc).offset((@page - 1) * @per_page).limit(@per_page)
      @total_count = model_class.count
    end

    def edit; end

    def update
      if @record.update(record_params)
        redirect_to admin_db_table_path(@table_name), success: "Запись обновлена."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def ensure_local_environment!
      return if Rails.env.development? || Rails.env.test?

      head :not_found
    end

    def set_table_name
      @table_name = params[:table]
      head :not_found unless table_names.include?(@table_name)
    end

    def set_record
      @record = model_class.find(params[:id])
    end

    def table_names
      @table_names ||= begin
        names = ActiveRecord::Base.connection.tables - %w[schema_migrations ar_internal_metadata]
        names.sort_by { |name| [name.start_with?("news_") ? 0 : 1, name] }
      end
    end

    def model_class
      @model_class ||= Class.new(ActiveRecord::Base) do
        self.abstract_class = false
        self.inheritance_column = :_type_disabled
      end.tap do |klass|
        klass.table_name = @table_name if @table_name.present?
      end
    end

    def primary_key_name
      model_class.primary_key || "id"
    end

    def table_columns
      model_class.columns.reject { |column| %w[id created_at updated_at].include?(column.name) }
    end

    def editable_columns
      table_columns
    end

    def record_display_value(record, column)
      value = record.public_send(column.name)

      case column.type
      when :json, :jsonb
        value.present? ? JSON.pretty_generate(value) : ""
      when :datetime, :timestamp, :timestamptz
        value&.strftime("%Y-%m-%d %H:%M:%S %Z")
      when :date
        value&.to_s
      else
        value
      end
    end

    def column_value(column_name)
      @record.public_send(column_name)
    end

    def column_input_type(column)
      case column.type
      when :boolean
        :boolean
      when :integer, :float, :decimal
        :number
      when :datetime, :timestamp, :timestamptz
        :datetime_local
      when :date
        :date
      when :text, :json, :jsonb
        :text
      else
        :text
      end
    end

    def record_params
      params.require(:record).permit(*editable_columns.map(&:name)).to_h.tap do |attributes|
        editable_columns.each do |column|
          next unless %i[json jsonb].include?(column.type)

          raw_value = attributes[column.name]
          attributes[column.name] = parse_json_attribute(raw_value)
        end
      end
    end

    def parse_json_attribute(value)
      return {} if value.blank?

      JSON.parse(value)
    rescue JSON::ParserError
      value
    end
  end
end
