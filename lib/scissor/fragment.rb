require 'pathname'

module Scissor
  class Fragment
    attr_reader :filename, :attributes

    def initialize(attributes)
      @attributes = { 
        :reverse => false, 
        :pitch => 100, 
        :stretch => false, 
        :pan => 50, 
        :volume => 100, 
        :fade_in_start_volume_ratio => 1.0,
        :fade_in_end_volume_ratio => 1.0, 
        :fade_in_duration => 0.0,
        :fade_out_start_volume_ratio => 1.0, 
        :fade_out_end_volume_ratio => 1.0, 
        :fade_out_duration => 0.0,
      }.merge(attributes)
      [:filename, :start, :length].each do |arg|
        unless @attributes[arg]
          raise ArgumentError, "missing #{arg} argument"
        end
      end
      @filename = Pathname.new(attributes[:filename]).realpath
      freeze
    end

    def method_missing(mid)
      @attributes[mid] or super
    end

    def duration
      @attributes[:length] * (100 / @attributes[:pitch].to_f)
    end

    def original_duration
      @attributes[:length] 
    end

    def reversed?
      @attributes[:reverse] 
    end

    def stretched?
      @attributes[:stretch] 
    end

    def create(remaining_start, remaining_length)
      if remaining_start >= duration
        return [nil, remaining_start - duration, remaining_length]
      end

      have_remain_to_return = (remaining_start + remaining_length) >= duration

      if have_remain_to_return
        new_length = duration - remaining_start
        remaining_length -= new_length
      else
        new_length = remaining_length
        remaining_length = 0
      end

      new_fragment = clone do |attributes|
        attributes.update(
          :start    =>  start + remaining_start * pitch.to_f / 100,
          :length =>  new_length * pitch.to_f / 100,
          :reverse  => false
          )
      end

      return [new_fragment, 0, remaining_length]
    end

    def clone(new_attributes = {})
      if block_given?
        attributes = @attributes.dup
        yield attributes
        self.class.new(attributes)
      else
        self.class.new(@attributes.merge new_attributes)
      end
    end
  end
end
