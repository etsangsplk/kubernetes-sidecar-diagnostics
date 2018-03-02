require_relative 'json_serializable'

module ApplicationInsights
  module Channel
    module Contracts
      require_relative 'data_point_type'
      require_relative 'dependency_kind'
      require_relative 'dependency_source_type'
      # Data contract class for type RemoteDependencyData.
      class RemoteDependencyData < JsonSerializable
        # Initializes a new instance of the RemoteDependencyData class.
        def initialize(options={})
          defaults = {
            'ver' => 2,
            'name' => nil,
            'id' => nil,
            'resultCode' => nil,
            'duration' => nil,
            'success' => true,
            'data' => nil,
            'target' => nil,
            'type' => nil,
            'properties' => {},
            'measurements' => {}
          }
          values = {
            'ver' => 2,
            'name' => nil,
            'id' => nil,
            'success' => true,
          }
          super defaults, values, options
        end
        
        # Gets the ver property.
        def ver
          @values['ver']
        end
        
        # Sets the ver property.
        def ver=(value)
          @values['ver'] = value
        end
        
        # Gets the name property.
        def name
          @values['name']
        end
        
        # Sets the name property.
        def name=(value)
          @values['name'] = value
        end

        def id
          @values['id']
        end

        def id=(value)
          @values['id'] = value
        end

        def result_code
          @values['resultCode']
        end

        def result_code=(value)
          @values['resultCode'] = value
        end

        def duration
          @values['duration']
        end

        def duration=(value)
          @values['duration'] = value
        end

        def success
          @values['success']
        end

        def success=(value)
          @values['success'] = value
        end

        def data
          @values['data']
        end

        def data=(value)
          @values['data'] = value
        end

        def target
          @values['target']
        end

        def target=(value)
          @values['target'] = value
        end

        def type
          @values['type']
        end

        def type=(value)
          @values['type'] = value
        end

        def properties
          @values['properties']
        end

        def properties=(value)
          @values['properties'] = value
        end

        def measurements
          @values['measurements']
        end

        def measurements=(value)
          @values['measurements'] = value
        end

      end
    end
  end
end
