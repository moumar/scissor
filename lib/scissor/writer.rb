require 'digest/md5'
require 'pathname'
require 'open4'
require 'temp_dir'

module Scissor
  class Writer
    include Loggable

    class Error < StandardError; end
    class FileExists < Error; end
    class EmptyFragment < Error; end
    class CommandFailed < Error; end
    class CommandNotFound < Error; end

    def initialize
      @tracks = []

      which('ecasound')
      which('ffmpeg')
      which('rubberband')
    end

    def add_track(fragments)
      @tracks << fragments
    end

    def join_fragments(fragments, outfile, tmpdir)
      position = 0.0
      cmd = %w/ecasound/

      fragments.each_with_index do |fragment, index|
        fragment_filename = fragment.filename

        if !index.zero? && (index % 28).zero?
          run_command(cmd.join(' '))
          cmd = %w/ecasound/
        end

        if fragment_filename.extname.downcase == '.wav'
          fragment_outfile = fragment_filename
        else
          fragment_outfile = tmpdir + (Digest::MD5.hexdigest(fragment_filename.to_s) + '.wav')
        end

        unless fragment_outfile.exist?
          run_command("ffmpeg -i \"#{fragment_filename}\" \"#{fragment_outfile}\"")
        end

        cmd << "-a:#{index} -o:#{outfile} -y:#{position}"

        if fragment.stretched? && fragment.pitch.to_f != 100.0
          rubberband_out = tmpdir + (Digest::MD5.hexdigest(fragment_filename.to_s) + "rubberband_#{index}.wav")
          rubberband_temp = tmpdir + "_rubberband.wav"
          
          run_command("ecasound " + 
            "-i:" +
            (fragment.reversed? ? 'reverse,' : '') +
            "select,#{fragment.start},#{fragment.original_duration},\"#{fragment_outfile}\" -o:#{rubberband_temp} "
          )
          run_command("rubberband -T #{fragment.pitch.to_f/100} \"#{rubberband_temp}\" \"#{rubberband_out}\"")

          cmd << "-i:\"#{rubberband_out}\""
        else
          cmd << 
            "-i:" +
            (fragment.reversed? ? 'reverse,' : '') +
            "select,#{fragment.start},#{fragment.original_duration},\"#{fragment_outfile}\" " +
            (fragment.pitch.to_f == 100.0 ? "" : "-ei:#{fragment.pitch} ")
        end

        position += fragment.duration
      end

      run_command(cmd.join(' '))
    end

    def mix_files(filenames, outfile)
      cmd = %w/ecasound/

      filenames.each_with_index do |tf, index|
        cmd << "-a:#{index} -i:#{tf}"
      end

      cmd << "-a:all -o:#{outfile}"
      run_command(cmd.join(' '))
    end

    def to_file(filename, options)
      filename = Pathname.new(filename)
      full_filename = filename.expand_path

      if @tracks.flatten.empty?
        raise EmptyFragment
      end

      options = {
        :overwrite => false,
        :bitrate => '128k'
      }.merge(options)

      if filename.exist?
        if options[:overwrite]
          filename.unlink
        else
          raise FileExists
        end
      end

      TempDir.create do |dir|
        tmpdir = Pathname.new(dir)
        tmpfiles = []

        @tracks.each_with_index do |fragments, track_index|
          tmpfile = tmpdir + 'track_%s.wav' % track_index.to_s
          tmpfiles << tmpfile
          join_fragments(fragments, tmpfile, tmpdir)
        end

        mix_files(tmpfiles, final_tmpfile = tmpdir + 'tmp.wav')

        if filename.extname == '.wav'
          File.rename(final_tmpfile, full_filename)
        else
          run_command("ffmpeg -ab #{options[:bitrate]} -i \"#{final_tmpfile}\" \"#{full_filename}\"")
        end
      end
    end

    def which(command)
      run_command("which #{command}")
    rescue
      raise CommandNotFound.new(command + ': command not found')
    end

    def run_command(cmd)
      logger.debug("run_command: #{cmd}")

      result, error = '', ''
      status = Open4.spawn cmd, 'stdout' => result, 'stderr' => error
      logger.debug(error)

      if status.exitstatus != 0
        raise CommandFailed.new(cmd)
      end

      return result
    end
  end
end
