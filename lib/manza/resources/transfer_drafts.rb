# frozen_string_literal: true

module Manza
  module Resources
    # @deprecated Use {Payments} (`manza.payments`). Kept for all of 1.x;
    #   it is the same class and calls `/api/payments`.
    TransferDrafts = Payments
    deprecate_constant :TransferDrafts
  end
end
