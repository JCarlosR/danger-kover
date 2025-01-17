require 'nokogiri'

module Danger

  # Parse a Kover report to enforce code coverage on CI. 
  # Results are passed out as a table in markdown.
  #
  # It depends on having a Kover coverage report generated for your project.
  #
  #
  # @example Running with default values for Kover
  #
  #          # Report coverage of modified files, fail if either total project coverage
  #          # or any modified file's coverage is under 90%
  #          kover.report 'Project Name', 'path/to/kover/report.xml'
  #
  # @example Running with custom coverage thresholds for Kover
  #
  #          # Report coverage of modified files, fail if total project coverage is under 80%,
  #          # or if any modified file's coverage is under 95%
  #          kover.report 'Project Name', 'path/to/kover/report.xml', 80, 95
  #
  # @example Warn on builds instead of failing for Kover
  #
  #          # Report coverage of modified files the same as the above example, except the
  #          # builds will only warn instead of fail if below thresholds
  #          kover.report 'Project Name', 'path/to/kover/report.xml', 80, 95, false
  #    
  # @tags android, kover, code coverage, coverage report
  #
  class DangerKover < Plugin

    # Total project code coverage % threshold [0-100].
    # @return [Integer]
    attr_accessor :total_threshold

    # A getter for `total_threshold`, returning 70% by default.
    # @return [Integer]
    def total_threshold
      @total_threshold ||= 70
    end

    # Modified file code coverage % threshold [0-100].
    # @return [Integer]
    attr_accessor :file_threshold

    # A getter for `file_threshold`, returning 70% by default.
    # @return [Integer]
    def file_threshold
      @file_threshold ||= 70
    end

    # Fail if under threshould, just warn otherwise.
    # @return [Boolean]
    attr_accessor :fail_if_under_threshold

    # A getter for `fail_if_under_threshold`, returning `true` if not defined.
    # @return [Boolean]
    def fail_if_under_threshold
      if defined?(@fail_if_under_threshold)
        @fail_if_under_threshold
      else
        true
      end
    end

    # Show plugin repository link.
    # @return [Boolean]
    attr_accessor :link_repository

    # A getter for `link_repository`, returning `true` by default.
    # @return [Boolean]
    def link_repository
      if defined?(@link_repository)
        @link_repository
      else
        true
      end
    end

    # Show not found files in report count.
    # @return [Boolean]
    attr_accessor :count_not_found

    # A getter for `count_not_found`, returning `true` by default.
    # @return [Boolean]
    def count_not_found
      if defined?(@count_not_found)
        @count_not_found
      else
        true
      end
    end

    # Report coverage on diffed files, as well as overall coverage.
    #
    # @param   [String] moduleName
    #          the display name of the project or module
    #
    # @param   [String] file
    #          file path to a Kover xml coverage report.
    #
    # @return  [void]
    def report(moduleName, file)
      raise "Please specify file name." if file.empty?
      raise "No Kover xml report found at #{file}" unless File.exist? file
      
      rawXml = File.read(file)
      parsedXml = Nokogiri::XML.parse(rawXml)
      totalInstructionCoverage = parsedXml.xpath("/report/counter[@type='INSTRUCTION']")
      missed = totalInstructionCoverage.attr("missed").value.to_i
      covered = totalInstructionCoverage.attr("covered").value.to_i
      total = missed + covered
      coveragePercent = (covered / total.to_f) * 100

      # get array of files names touched by this PR (modified + added)
      touchedFileNames = @dangerfile.git.modified_files.map { |file| File.basename(file) }
      touchedFileNames += @dangerfile.git.added_files.map { |file| File.basename(file) }

      # used to later report files that were modified but not included in the report
      fileNamesNotInReport = []

      # hash for keeping track of coverage per filename: {filename => coverage percent}
      touchedFilesHash = {}

      touchedFileNames.each do |touchedFileName|
        xmlForFileName = parsedXml.xpath("//class[@sourcefilename='#{touchedFileName}']/counter[@type='INSTRUCTION']")

        if (xmlForFileName.length > 0)
          missed = 0
          covered = 0
          xmlForFileName.each do |classCountXml|
            missed += classCountXml.attr("missed").to_i
            covered += classCountXml.attr("covered").to_i
          end
          touchedFilesHash[touchedFileName] = (covered.to_f / (missed + covered)) * 100
        else
          fileNamesNotInReport << touchedFileName
        end
      end

      puts "Here are unreported files"
      puts fileNamesNotInReport.to_s
      
      puts "Here is the touched files coverage hash"
      puts touchedFilesHash

      output = "### 🎯 #{moduleName} Code Coverage: **`#{'%.2f' % coveragePercent}%`**\n\n"

      if touchedFilesHash.empty?
        output << "The new and updated files are not part of this module coverage report 👀.\n"
      else
        output << "**Modified files:**\n\n"
        output << "File | Coverage\n"
        output << ":-----|:-----:\n"
      end

      # Go through each file:
      touchedFilesHash.sort.each do |fileName, coveragePercent|
        output << "`#{fileName}` | **`#{'%.2f' % coveragePercent}%`**\n"

        # Check file coverage
        if (coveragePercent == 0)
          advise("Oops! #{fileName} does not have any test coverage.")
        elsif (coveragePercent < file_threshold)
          advise("Oops! #{fileName} is under #{file_threshold}% coverage.")
        end
      end

      puts "Value of count_not_found: #{count_not_found}"
      puts "Value of link_repository: #{link_repository}"

      if (count_not_found)
        output << "\n\n"
        output << "Number of files not found in coverage report: #{fileNamesNotInReport.size}."
      end

      if (link_repository)
        output << "\n\n"
        output << 'Code coverage by [danger-kover](https://github.com/JCarlosR/danger-kover).'
      end
      
      markdown output

      # Check total coverage
      if (coveragePercent < total_threshold)        
        advise("Oops! The module #{moduleName} codebase is under #{total_threshold}% coverage.")
      end
    end

    # Warn or fail, depending on the `fail_if_under_threshold` flag.
    private def advise(message)
      if (fail_if_under_threshold)
        fail message
      else
        warn message
      end
    end

  end
end
