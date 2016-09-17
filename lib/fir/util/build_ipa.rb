# encoding: utf-8

module FIR
  module BuildIpa

    def build_ipa(*args, options)
      initialize_build_common_options(args, options)

      @build_tmp_dir = Dir.mktmpdir
      @build_cmd     = initialize_ipa_build_cmd(args, options)
      puts("#{@build_cmd}") if $DEBUG
      logger_info_and_run_build_command

      output_ipa_and_dsym
      publish_build_app(options) if options.publish?
      upload_build_dsym_mapping_file if options.mapping?

      logger_info_blank_line
    end

    private

    def initialize_ipa_build_cmd(args, options)
      @configuration = options[:configuration]
      @target_name   = options[:target]
      @scheme_name   = options[:scheme]
      @profile_name  = options[:profile]
      @destination   = options[:destination]
      @archivepath   = options[:archivepath]
      @appname       = options[:name]

      build_cmd =  'xcodebuild build -sdk iphoneos'
      build_cmd =  "xcodebuild archive -sdk iphoneos -archivePath '#{@output_path}/#{@appname}.xcarchive'" unless @archivepath.blank?
      build_cmd += initialize_xcode_build_path(options)
      build_cmd += " -configuration '#{@configuration}'" unless @configuration.blank?
      build_cmd += " -target '#{@target_name}'" unless @target_name.blank?
      build_cmd += " -destination '#{@destination}'" unless @destination.blank?
      if @archivepath.blank? then
        build_cmd += " -exportProvisioningProfile '#{@profile_name}'" unless @profile_name.blank?
      end
      build_cmd += " #{ipa_custom_settings(args)} 2>&1"
      build_cmd
    end

    def ipa_custom_settings(args)
      custom_settings = split_assignment_array_to_hash(args)

      setting_str =  convert_hash_to_assignment_string(custom_settings)
      if @archivepath.blank? then
        setting_str += " TARGET_BUILD_DIR='#{@build_tmp_dir}'" unless custom_settings['TARGET_BUILD_DIR']
        setting_str += " CONFIGURATION_BUILD_DIR='#{@build_tmp_dir}'" unless custom_settings['CONFIGURATION_BUILD_DIR']
      end
      setting_str += " DWARF_DSYM_FOLDER_PATH='#{@output_path}'" unless custom_settings['DWARF_DSYM_FOLDER_PATH']
      setting_str
    end

    def output_ipa_and_dsym
      if @archivepath.blank? then
        apps = Dir["#{@build_tmp_dir}/*.app"].sort_by(&:size)
        check_no_output_app(apps)

        @temp_ipa = "#{@build_tmp_dir}/#{Time.now.to_i}.ipa"
        archive_ipa(apps)

        check_archived_ipa_is_exist
        rename_ipa_and_dsym

        FileUtils.rm_rf(@build_tmp_dir) unless $DEBUG
      else
        check_no_output_xcarchive
        export_archive

        check_archived_ipa_is_exist
        rename_ipa_and_dsym

        FileUtils.rm_rf("#{@output_path}/#{@appname}.xcarchive") unless $DEBUG
      end

      logger.info 'Build Success'
    end

    def archive_ipa(apps)
      logger.info 'Archiving......'
      logger_info_dividing_line

      @xcrun_cmd = "xcrun -sdk iphoneos PackageApplication -v #{apps.join(' ')} -o #{@temp_ipa}"
      puts @xcrun_cmd if $DEBUG
      logger.info `#{@xcrun_cmd}`
    end

    def export_archive
      logger.info 'Archiving......'
      logger_info_dividing_line

      @temp_ipa = "#{@output_path}/#{Time.now.to_i}.ipa"

      @archive_cmd = "xcodebuild -exportArchive -exportFormat IPA -exportProvisioningProfile '#{@profile_name}' -archivePath '#{@output_path}/#{@appname}.xcarchive' -exportPath '#{@temp_ipa}'"
      puts @archive_cmd if $DEBUG
      logger.info `#{@archive_cmd}`
    end

    def check_archived_ipa_is_exist
      unless File.exist?(@temp_ipa)
        logger.error 'Archive failed'
        exit 1
      end
    end

    def rename_ipa_and_dsym
      ipa_info  = FIR.ipa_info(@temp_ipa)
      dsym_name = "#{@output_path}/#{ipa_info[:name]}.app.dSYM"

      if @name.blank?
        @ipa_name = "#{ipa_info[:name]}-#{ipa_info[:version]}-build-#{ipa_info[:build]}"
      else
        @ipa_name = @name
      end

      @builded_app_path = "#{@output_path}/#{@ipa_name}.ipa"

      FileUtils.mv(@temp_ipa, @builded_app_path, force: true)
      if File.exist?(dsym_name)
        FileUtils.mv(dsym_name, "#{@output_path}/#{@ipa_name}.app.dSYM", force: true)
      end
    end

    def upload_build_dsym_mapping_file
      logger_info_blank_line

      @app_info     = ipa_info(@builded_app_path)
      @mapping_file = Dir["#{@output_path}/#{@ipa_name}.app.dSYM/Contents/Resources/DWARF/*"].first

      mapping @mapping_file, proj:    @proj,
                             build:   @app_info[:build],
                             version: @app_info[:version],
                             token:   @token
    end

    def initialize_xcode_build_path(options)
      if options.workspace?
        workspace = check_and_find_ios_xcworkspace(@build_dir)
        check_ios_scheme(@scheme_name)

        return " -workspace '#{workspace}' -scheme '#{@scheme_name}'"
      else
        project = check_and_find_ios_xcodeproj(@build_dir)

        return " -project '#{project}'"
      end
    end

    %w(xcodeproj xcworkspace).each do |workplace|
      define_method "check_and_find_ios_#{workplace}" do |path|
        unless File.exist?(path)
          logger.error "The first param BUILD_DIR must be a #{workplace} directory"
          exit 1
        end

        if File.extname(path) == ".#{workplace}"
          build_dir = path
        else
          build_dir = Dir["#{path}/*.#{workplace}"].first
          if build_dir.blank?
            logger.error "The #{workplace} file is missing, check the BUILD_DIR"
            exit 1
          end
        end

        build_dir
      end
    end

    def check_ios_scheme(scheme_name)
      if scheme_name.blank?
        logger.error 'Must provide a scheme by `-S` option when build a workspace'
        exit 1
      end
    end

    def check_no_output_app(apps)
      if apps.length == 0
        logger.error 'Builded has no output app, Can not be packaged'
        exit 1
      end
    end

    def check_no_output_xcarchive
      unless File.exist?("#{@output_path}/#{@appname}.xcarchive")
        logger.error 'Builded has no output xcarchive, Can not be packaged'
        exit 1
      end
    end
  end
end
