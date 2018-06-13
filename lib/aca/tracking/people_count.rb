module Aca; end
module Aca::Tracking; end
class Aca::Tracking::PeopleCount < CouchbaseOrm::Base
    design_document :pcount

    # Connection details
    attribute :room_email,   type: String  
    attribute :booking_id,   type: String  
    attribute :system_id,    type: String  
    attribute :capacity,     type: Integer 
    attribute :maximum,      type: Integer 
    attribute :average,      type: Integer 
    attribute :median,       type: Integer
    attribute :organiser,    type: String
    attribute :counts,       type: Array, default: []

    protected


    before_create :set_id

    def set_id
        self.id = "count-#{self.booking_id}"
    end

end