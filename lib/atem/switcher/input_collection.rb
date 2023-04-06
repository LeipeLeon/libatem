module ATEM
  class Switcher
    class InputCollection
      include Enumerable

      attr_reader :switcher

      def initialize switcher
        @switcher = switcher
        @inputs = {}
      end

      def add input
        @inputs[input.id] = input
      end

      def [] index
        return @inputs[index] if @inputs[index]

        if index.is_a? String
          @inputs.each do |a, input|
            return input if (input.name == index) || (input.short_name.downcase == index.downcase)
          end
        end
      end

      def each(&block)
        @inputs.each(&block)
      end
    end
  end
end
