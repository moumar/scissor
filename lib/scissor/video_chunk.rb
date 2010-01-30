module Scissor

  class VideoChunk < Chunk

    def initialize(filename = nil)
      @type = :video
      @fragments = []

      if filename
        @fragments << Fragment.new(
          filename,
          0,
          VideoFile.new(filename).length)
      end
    end

    def to_file(filename, options = {})
      filename = Pathname.new(filename)

      if @fragments.empty?
        raise EmptyFragment
      end

      options = {
        :overwrite => false,
        :save_work_dir => false
      }.merge(options)

      if filename.exist?
        if options[:overwrite]
          filename.unlink
        else
          raise FileExists
        end
      end

      concat_files = []
      ffmpeg = Scissor.ffmpeg('ffmpeg', nil, options[:save_work_dir])

      position = 0.0
      tmpdir = ffmpeg.work_dir
      tmpfile = tmpdir + 'tmp.avi'

      begin
        @fragments.each_with_index do |fragment, index|
          fragment_filename = fragment.filename
          fragment_duration = fragment.duration

          fragment_tmpfile = tmpdir + (Digest::MD5.hexdigest(fragment_filename) + "_#{index}.avi")

          unless fragment_tmpfile.exist?
            ffmpeg.cut({
                :input_video => fragment_filename,
                :output_video => fragment_tmpfile,
                :start => fragment.start,
                :duration => fragment_duration
            })
            concat_files.push fragment_tmpfile
          end
          position += fragment_duration
        end

        Scissor.mencoder('mencoder', nil, options[:save_work_dir]).concat({
            :input_videos => concat_files,
            :output_video => tmpfile
        })

        ffmpeg.encode({
            :input_video => tmpfile,
            :output_video => filename
        })
      end

      self.class.new(filename)
    end

    def strip_audio
      audio_fragments = []
      ffmpeg = Scissor.ffmpeg
      @fragments.each_with_index do |fragment, index|
        fragment_filename = fragment.filename
        audio_fragments.push ffmpeg.strip_audio(fragment_filename)
      end
      Scissor.join audio_fragments
    end
  end
end
