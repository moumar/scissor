require 'open-uri'
require 'tempfile'

module Scissor
  class Tape
    class Error < StandardError; end
    class EmptyFragment < Error; end

    attr_reader :fragments

    def initialize(filename = nil)
      @fragments = []

      if filename
        filename = Pathname(filename).expand_path
        @fragments << Fragment.new(
          :filename => filename,
          :start => 0,
          :length => SoundFile.new_from_filename(filename).length)
      end
    end

    def self.new_from_url(url)
      file = nil
      content_types = {
        'audio/wav' => 'wav',
        'audio/x-wav' => 'wav',
        'audio/wave' => 'wav',
        'audio/x-pn-wav' => 'wav',
        'audio/mpeg' => 'mp3',
        'audio/x-mpeg' => 'mp3',
        'audio/mp3' => 'mp3',
        'audio/x-mp3' => 'mp3',
        'audio/mpeg3' => 'mp3',
        'audio/x-mpeg3' => 'mp3',
        'audio/mpg' => 'mp3',
        'audio/x-mpg' => 'mp3',
        'audio/x-mpegaudio' => 'mp3',
      }

      open(url) do |f|
        ext = content_types[f.content_type.downcase]

        file = Tempfile.new(['audio', '.' + ext])
        file.write(f.read)
        file.flush
      end

      tape = new(file.path)

      # reference tempfile to prevent GC
      tape.instance_variable_set('@__tempfile', file)
      tape
    end

    def add_fragment(fragment)
      @fragments << fragment
    end

    def add_fragments(fragments)
      fragments.each do |fragment|
        add_fragment(fragment)
      end
    end

    def duration(new_duration = nil)
      if new_duration
        stretch(new_duration*100/self.duration)
      else
        @fragments.inject(0) do |memo, fragment|
          memo += fragment.duration
        end
      end
    end

    def slice(start, length)
      if start + length > duration
        length = duration - start
      end

      new_instance = self.class.new
      remaining_start = start.to_f
      remaining_length = length.to_f

      @fragments.each do |fragment|
        new_fragment, remaining_start, remaining_length =
          fragment.create(remaining_start, remaining_length)

        if new_fragment
          new_instance.add_fragment(new_fragment)
        end

        if remaining_length == 0
          break
        end
      end

      new_instance
    end

    alias [] slice

    def concat(other)
      add_fragments(other.fragments)

      self
    end

    alias << concat

    def +(other)
      new_instance = Scissor()
      new_instance.add_fragments(@fragments + other.fragments)
      new_instance
    end

    def loop(count)
      orig_fragments = @fragments.clone
      new_instance = Scissor()

      count.times do
        new_instance.add_fragments(orig_fragments)
      end

      new_instance
    end

    alias * loop

    def split(count)
      splitted_duration = duration / count.to_f
      results = []

      count.times do |i|
        results << slice(i * splitted_duration, splitted_duration)
      end

      results
    end

    alias / split

    def fill(filled_duration)
      if duration.zero?
        raise EmptyFragment
      end

      loop_count = (filled_duration / duration).to_i
      remain = filled_duration % duration

      loop(loop_count) + slice(0, remain)
    end

    def replace(start, length, replaced)
      new_instance = self.class.new
      offset = start + length

      new_instance += slice(0, start)

      if new_instance.duration < start
        new_instance + Scissor.silence(start - new_instance.duration)
      end

      new_instance += replaced

      if duration > offset
        new_instance += slice(offset, duration - offset)
      end

      new_instance
    end

    def reverse
      fragment_loop(true) do |fragment, attributes|
        attributes[:reverse] = !fragment.reversed?
      end
    end

    def pitch(pitch, stretch = false)
      fragment_loop do |fragment, attributes|
        attributes[:pitch]   = fragment.pitch * (pitch.to_f / 100)
        attributes[:stretch] = stretch
      end
    end

    def stretch(factor)
      factor_for_pitch = 1 / (factor.to_f / 100) * 100
      pitch(factor_for_pitch, true)
    end

    def pan(right_percent)
      fragment_loop do |fragment, attributes|
        attributes[:pan] = right_percent
      end
    end

    def fade_in(fade_duration)
      volume_ratio_at_position = proc do |pos|
        pos -= @fragments[0].start
        [ (pos/fade_duration), 1.0].min
      end
      fade_duration_left = fade_duration
      fragment_loop do |fragment, attributes|
        if fragment.start <= (self.duration + fragment.start - fade_duration)
          attributes[:fade_in_start_volume_ratio] *= volume_ratio_at_position.call(fragment.start)
          d = [fragment.duration, fade_duration_left].min
          attributes[:fade_in_end_volume_ratio]   *= volume_ratio_at_position.call(fragment.start + d)
          attributes[:fade_in_duration] = d
          fade_duration_left -= d
        end
      end
    end

    def fade_out(fade_duration)
      fade_position = self.duration - fade_duration
      volume_ratio_at_position = proc do |pos|
        pos -= @fragments.first.start
        pos -= fade_position
        1 - [0, [pos / fade_duration, 1].min].max
      end
      fade_duration_left = fade_duration
      fragment_loop do |fragment, attributes|
        fragment_end = fragment.start + fragment.duration - @fragments.first.start
        if fragment_end > fade_position
          #puts "fragment_end #{fragment_end} fade_duration_left #{fade_duration_left} fade_position #{fade_position}"
          attributes[:fade_out_start_volume_ratio] *= volume_ratio_at_position.call(fragment.start)
          attributes[:fade_out_end_volume_ratio]   *= volume_ratio_at_position.call(fragment.start + fragment.duration)
          duration = [fade_duration_left - (self.duration - fragment_end ), fade_duration_left].min
          attributes[:fade_out_duration] = duration
          fade_duration_left -= duration
        end
      end
    end

    def volume(v)
      fragment_loop do |fragment, attributes|
        attributes[:volume] = v
      end
    end

    def to_file(filename, options = {})
      Scissor.mix([self], filename, options)
    end

    alias > to_file

    def >>(filename)
      to_file(filename, :overwrite => true)
    end

    def silence
      Scissor.silence(duration)
    end

    private

    def fragment_loop(reverse = false)
      new_instance = self.class.new
      fragments = reverse ? @fragments.reverse : @fragments
      fragments.each do |fragment|
        new_instance.add_fragment(fragment.clone do |attributes|
          yield fragment, attributes
        end)
      end
      new_instance
    end
  end
end
