class Item < ActiveRecord::Base
  belongs_to :category
  has_many :order_details
  has_many :orders, through: :order_details
  has_many :requested_orders, -> { for_requested_statuses }, through: :order_details, source: :order
  validates :description, presence: true

  # Specify which fields will trigger an audit entry
  has_paper_trail only: [:current_quantity, :description, :category_id],
                  meta: { edit_amount: :edit_amount,
                          edit_method: :edit_method,
                          edit_reason: :edit_reason,
                          edit_source: :edit_source }

  attr_accessor :edit_amount, :edit_method, :edit_reason, :edit_source
  attr_writer :requested_quantity

  enum edit_reasons: [:donation, :purchase, :correction, :order_adjustment]
  enum edit_methods: [:add, :subtract, :new_total]

  def self.for_category(category_id)
    where(category_id: category_id)
  end

  def self.selectable_edit_reasons
    @selectable_edit_reasons ||= edit_reasons.select { |x| x != "order_adjustment" }
  end

  def self.inject_requested_quantities(items)
    map = Item.where(id: items.map(&:id)).with_requested_quantity.index_by { |x| x }
    items.each { |item| item.requested_quantity = map[item].requested_quantity }
  end

  def self.with_requested_quantity
    references(requested_orders: :order_details).includes(requested_orders: :order_details)
  end

  def total_value
    current_quantity * value
  end

  def requested_quantity
    @requested_quantity ||=
      begin
        if requested_orders.loaded? && requested_orders.all? { |order| order.order_details.loaded? }
          requested_orders.map(&:order_details).flatten.select { |x| x.item_id == id }.sum(&:quantity)
        else
          raise "Cannot retrieve requested_quantity unless it is set first!"
        end
      end
  end

  def available_quantity
    current_quantity - requested_quantity
  end

  def to_json
    {
      id: id,
      description: description,
      current_quantity: current_quantity,
      requested_quantity: requested_quantity
    }
  end

  def pending_orders
    orders.where(status: Order.statuses[:pending])
  end

  def mark_event(params)
    return unless params[:edit_amount] && params[:edit_method] && params[:edit_reason]
    self.edit_amount = params[:edit_amount].to_i
    self.edit_method = params[:edit_method]
    self.edit_reason = params[:edit_reason]
    self.edit_source = params[:edit_source]

    update_quantity
  end

  def quantity_versions
    versions.select { |v| v.changeset["current_quantity"] }.reverse
  end

  private

  def update_quantity
    case edit_method
    when "add"
      self.current_quantity += edit_amount
    when "subtract"
      self.current_quantity -= edit_amount
    when "new_total"
      self.current_quantity = edit_amount
    end
  end
end
