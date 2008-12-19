#!/usr/bin/env ruby

# == Synopsis
#
# This script will fetch photos from flickr.  You can specify to select
# photos based on users, photosets, groups, interestingness, or searches.
# Multiple selection criteria is allowed (i.e., zero or more users AND
# zero or more photosets AND zero or more groups...).  Further you can
# select images based on size (larger or smaller than a threshold or
# within a range).  Also optionally resize and/or fill to a size.
#
# You will need a Flickr account and will have to visit Flickr to 
# authorize FlickrFetchr for your account only once.  The first time
# you run FlickrFetchr it will give you the URL you have to visit.
#
# This script was originally designed as a replacement for LinuxMCE's 
# flickr.pl script but has since evolved to be a high-level object
# with a command line application.  Currently the LinuxMCE support
# is provide via an optional plugin.
#
# == Details
#
# This script is in two parts, the FlickrFetchr class and then
# a command line runner.
#
# To use the FlickrFetchr class, populate a config Hash (see flickrfetchr.conf[link:files/out/flickrfetchr_conf.html]
# for complete description of the config Hash), then create an instance
# of the FlickrFetchr class passing it the config Hash, and then just
# executing the instance:
#
#  config = {...}
#  flickrfetchr = FlickrFetchr.new(config)
#  flickrfetchr.execute
#
# The selection criteria in the config Hash are under these sections:
# * config[:USER]        => [criteria_hash,...]
# * config[:GROUPS]      => [criteria_hash,...]
# * config[:PHOTOSETS]   => [criteria_hash,...]
# * config[:SEARCHES]    => [criteria_hash,...]
# * config[:INTERESTING] => [criteria_hash,...]
#
# === Flow
# Internally the FlickrFetchr class has the following flow:
#
#   FlickrFetchr.execute
#   * creates rFlickr instance
#   * loads plugins
#   * downloads each selection criteria by section
#     Downloader.open
#     * fetch
#       * fetch_section
#         * fetch_#{section_name}  # ex, fetch_users, fetch_groups
#         * Flickr::photo.save
#           * download
#             * plugins.pre_download
#             * read & save file
#             * plugins.post_download
#             * on error, plugins.on_download_error
#       * plugins.finish
#
# There is a ^C interrupt handler that allows in progress
# photo download to complete before exiting.
#
# All logging is via log4r and uses the logger.method block
# pattern.
#
# The Flickr::Photo is extended to have a public save method
# and several private support methods for the save.
#
# === Plugins
# The plugins are enabled on a per selection criteria basis:
#  config[section][n][:plugins] => [plugin_class_symbol,...]
#
# The plugins are expected to respond to these messages:
#  new(config)
#  pre_download(filespec)
#  post_download(filespec)
#  on_download_error(filespec)
#  self.finish(config)
#
# The LinuxMCE interface is now a plugin.
#
# LinuxMCE_Plugin is an encapsulation class with two purposes: first to handle
# file naming and destination path selection according to LinuxMCE standards;
# the second purpose is to encapsulate the interface to LinuxMCE when
# running on a DCE router (a LinuxMCE core system).  This includes
# DCE and database interfacing.
#
# === Command Line Runner
# The command-line runner handles reading the config files, setting up
# the logger, parsing the command-line arguments, and finally creating a
# FlickrFetchr instance and running it.
#
# == Usage
#
#   ./flickrfetchr.rb --help
#
# FlickrFetchr.rb is designed to be ran automatically.  It is driven by 
# the .flickrfetchr.conf file.  Run the script once with the --setup option
# to generate the following configuration files:
#
#  /etc/flickrfetchr.conf
#  ENV['HOME']/.flickrfetchr.conf
#
# These config files are well documented.  Simply edit one to add your 
# selection criteria.
#
# Note the load order is as above and that the files are merged such that
# config options are replaced with the later definition.  For example,
# say both config files set the config[:USERS] definition using the
# assignment operator '='.  Only the definition from the second file will 
# be used.  To merge the two conflicting definitions, use the addition
# assignment operator '+=' instead.
#
# To fetch photos, simply run the script:
# 
#   ./flickrfetchr.rb
#
# To visually monitor the script, select the --debug or --verbose options.
#
# To see the script in action but not to download any files, use the
# --pretend option.
#
# To have the script log to a file instead of standard output, edit
# your conf file and set config[:logger_output] to your desired log file.
#
# == Requirements
#
# * ruby 1.8
# * rubygems
#
# == Installation
#
# === LinuxMCE Setup Script
#
# There is a setup-linuxmce script for installing on LinuxMCE 0710.
#
# Extract flickrfetchr-*.tgz:
# 
#   tar xvf flickrfetchr-*.tgz
# 
# Change to the created directory:
# 
#   cd flickrfetchr
# 
# Run the setup script:
# 
#   ./setup-linuxmce
# 
# When prompted, you will need to copy a URL then load it into your web browser 
# (the web browser does not have to be running on the dcerouter) to authenticate 
# FlickrFetchr with your Flickr account.
#
# === Kubuntu Setup Script
#
# The installation instructions are the same as for the preceeding LinuxMCE Setup Script,
# except run ./setup-kubuntu instead of ./setup-linuxmce
#
# === Manual Installation
#
# Install ruby-dbi:
# * tar zxf files/dbi-0.2.0.tar.gz
# * cd dbi-0.2.0/
# * ruby setup.rb config --with=dbi,dbd_mysql
# * ruby setup.rb setup
# * sudo ruby setup.rb install
# Full documentation on ruby-dbi installation is at http://www.kitebird.com/articles/ruby-dbi.html
#
# Install these gems:  log4r, commandline, rflickr, rmagick:
# * gem install log4j
# * gem install commandline
# * gem install rflickr
# * gem install rmagick
#
# Apply the furnished patch to rflickr:
# * cp files/rflickr-2006.02.01.patch.1/usr/lib/ruby/gems/1.8/gems/rflickr-2006.02.01/
# * cd /usr/lib/ruby/gems/1.8/gems/rflickr-2006.02.01/
# * sudo patch -p0 <rflickr-2006.02.01.patch.1
#
# Move the script and support files to your desired directory (ex: /usr/local/bin)
# * mv flickrfetchr.rb /usr/local/bin
# * mv flickrfetchr.conf.erb /usr/local/bin
# * mv flickrfetchr-linuxmce.rb /usr/local/bin
# 
# Now to setup FlickrFetcher
# * flickrfetchr.rb --setup
# This should have created ~/.flickrfetchr.conf
# To optionally install /etc/flickrfetchr.conf, as root (sudo), rerun flickrfetchr.rb --setup

require 'rubygems'
require "cgi"
require "date"
require "dbi"
require "erb"
require "log4r"
require "open-uri"
require "flickr"
require "RMagick"
require 'commandline/optionparser'
include CommandLine

APP_NAME = 'FlickrFetchr'
APP_VERSION = '0.2.0'

# == Synopsis
# Fetch photos from flickr that are specified in the config hash:
#   config[:USERS] = [user_criteria, ...]
#   config[:GROUPS] = [group_criteria, ...]
#   config[:PHOTOSETS] = [photoset_criteria, ...]
#   config[:SEARCHES] = [search_criteria, ...]
#   config[:INTERESTING] = [interesting_criteria, ...]
#
# == Usage
#   config = {...}
#   app = FlickrFetchr.new(config)
#   app.execute
#
class FlickrFetchr
  FLICKR_FETCHR_API_KEY = '26fd9263a5050731188016a1d0f28192'
  FLICKR_FETCHR_SHARED_SECRET = 'eff36d633eb25489'
  
  SECTIONS = [:USERS, :GROUPS, :PHOTOSETS, :SEARCHES, :INTERESTING]
  
  @interrupted = false

  # A trap("INT") in the Runner calls this to indicate that a ^C has been detected.
  # Note, once set, it is never cleared
  def self.interrupt
    puts "control-C detected, finishing current task"
    @interrupted = true
  end
  
  # Long loops should poll this method to see if they should abort
  # Returns:: true if the application has trapped an "INT", false otherwise
  def self.interrupted?
    @interrupted
  end
  
  # The config parameter is the applications config Hash.
  def initialize(config)
    @config = config
    @logger = config[:logger]
    $: << File.dirname(__FILE__)
  end

public

  # This is the main execution loop for the application.
  def execute
    begin
      flickr = Flickr.new(@config[:token_cache_file], FLICKR_FETCHR_API_KEY, FLICKR_FETCHR_SHARED_SECRET)
      
      # authenticate the user with flickr
      authorize flickr do |url|
        @logger.warn {"You must visit #{url} to authorize FlickrFetchr.  Press enter " +
                     "when you have done so. This is the only time you will have to do this."}
        STDIN.gets
      end
      
      collect_plugins(@config)
      load_plugins(@config)
      
      # fetch each of the selection criteria
      Downloader.open(flickr, @config) do |downloader|
        SECTIONS.each {|section| downloader.fetch(section)}
      end
      
    rescue Exception => eMsg
      @logger.warn {eMsg.to_s}
      @logger.debug {eMsg.backtrace.join("\n")}
    end
  end
  
private

  # Authenticate the user with flickr
  # The block is called given a url that the user needs to visit
  # to authenticate this application with their account.
  # flickr:: the rFlickr instance
  def authorize(flickr) # :yields: url
    unless flickr.auth.token
      flickr.auth.getFrob
      url = flickr.auth.login_link
      yield url
      flickr.auth.getToken
      flickr.auth.cache_token
    end
  end

  # Require any used plugins only once each.
  # config:: is the application's config hash.  Uses config[:plugins], config[:logger]
  def load_plugins(config)
    # try to load each unique plugin
    config[:plugins].uniq.each do |plugin_name|
      name = nil
      name = $1 if plugin_name.to_s =~ /^(.*)_Plugin$/
      unless name.nil?
        plugin_filename = "flickrfetchr-#{name.downcase}.rb"
        config[:logger].info {"Loading #{plugin_name.to_s} (require \"#{plugin_filename}\")"}
        unless require plugin_filename
          config[:logger].error {"Could not load plugin #{plugin_name.to_s} (require \"#{plugin_filename}\" failed)"}
        end
      end
    end
  end
  
  # accumulate all of the :plugins from each of the criteria sections
  # config:: is the application's config hash.  Uses config[:plugins], config[section][][:plugins]
  def collect_plugins(config)
    config[:plugins] = []
    SECTIONS.each do |section|
      unless config[section].nil?
        config[:plugins] += config[section].collect{|criteria| criteria[:plugins]}.flatten.uniq.compact
      end
    end
  end

  # == Synopsis
  # Class for checking if a given image size (width, height) is within
  # an acceptable range.
  #
  class ImageBounds
    include Magick
    
    # width_boundary:: should be a Range, FixNum, or false.
    # height_boundary:: should be a Range, FixNum, or false.
    # * If a Range, then the image's size must inclusively be within the Range.
    # * If a FixNum, then image's size must be greater than or equal the value.
    # * If false, then any image size is ok.
    #
    # desired_size:: is a Hash {:width => FixNum, :height => FixNum} for the size to resize the image to, preserving aspect ratio.  
    #
    # fill_to_size:: is a Hash {:width => FixNum, :height => FixNum, :color => String} and if it is not nil, then the image will be centered on an image of.  The :color parameter defines the background color that the image is placed on top of.
    #
    # config:: is the application's config hash.
    def initialize(width_boundary, height_boundary, desired_size, fill_to_size, config)
      @width_boundary = width_boundary
      @height_boundary = height_boundary
      @desired_size = desired_size
      @fill_to_size = fill_to_size
      @config = config
      @logger = config[:logger]
    end
    
    # Is the given width & height inclusively within the boundary?
    # Returns:: true if the width & height are within the boundary and also returns true if boundary is invalid
    def within?(width, height)
      check(@width_boundary, width) && check(@height_boundary, height)
    end
  
    # Resize the image to @desired_size.
    # Note, for the image to be resized, @desired_size must be a Hash
    # with keys: :width & :height, both of which must have non-nil values.
    # This method will gracefully (silently) fail otherwise.
    # filespec:: The filespec for the image to resize.
    def resize(filespec)
      unless @desired_size.nil? || @config[:pretend]
        if @desired_size.class == Hash
          unless @desired_size[:width].nil? || @desired_size[:height].nil?
            image = ImageList.new(filespec)
            image.resize_to_fit! @desired_size[:width], @desired_size[:height]
            image.write(filespec)
          end
        else
          @logger.debug {"Expected class type of Hash but got #{@desired_size.class}, desired_size is #{@desired_size.inspect}"}
        end
      end
    end
    
    # If the fill_to_size parameter is not nil, then the image will be centered on an image of 
    # fill_to_size[:width] by fill_to_size[:height] with a fill_to_size[:color] background.
    # The config parameter is the application's config hash.
    # filespec:: The filespec for the image to fill around..
    def fill_to(filespec)
      unless @fill_to_size.nil?
        if @fill_to_size.class == Hash
          unless @fill_to_size[:width].nil? || @fill_to_size[:height].nil?
            @fill_to_size[:color] = 'black' if @fill_to_size[:color].nil?
            bcolor = @fill_to_size[:color]
            background = Image.new(@fill_to_size[:width], @fill_to_size[:height]) { self.background_color = bcolor }
            image = ImageList.new(filespec)
            new_image = background.composite(image, CenterGravity, AtopCompositeOp)
            new_image.write(filespec)
          end
        else
          @logger.debug {"Expected class type of Hash but got #{@fill_to_size.class}, fill_to_size is #{@fill_to_size.inspect}"}
        end
      end
    end
    
    # Convert to String for debugging purposes.
    def to_s
      ":image_width_range(#{@width_boundary}) x :image_height_range(#{@height_boundary})"
    end
    
  private
  
    # Check the given value for inclusion in the given range.
    # range:: should be a Range, FixNum, or false.
    # * If a Range, then the value must inclusively be within the Range.
    # * If a FixNum, then the value must be greater than or equal the value.
    # * If any other type, then any image size is ok.
    # value:: is an image dimension and should be a FixNum
    # Returns:: true if:
    # * value is within range when range is a Range
    # * value is greater than or equal to range when range is a FixNum. 
    # * when range is neither a Range nor a Fixnum
    def check(range, value)
      result = true
      unless range.nil?
        if range.class == Range
          result = (range === value)
        elsif range.class == Fixnum
          result = (value >= range)
        end
      end
      result
    end
  end
  
  # == Synopsis
  # Downloader encapsulates fetching using the selection criteria.
  #
  # == Usage
  #   Downloader.open(flickr, @config) do |downloader|
  #     [:USERS, :GROUPS, :PHOTOSETS, :SEARCHES, :INTERESTING].each {|section| downloader.fetch(section)}
  #   end
  # 
  class Downloader
  
    # Protected initialize method, use open instead.
    # flickr:: the rFlickr instance
    # config:: is the application's config hash.
    def initialize(flickr, config)
      @flickr = flickr
      @config = config
      @logger = config[:logger]
      @logger.debug {"Downloader.initialize"}
    end
  
  public
  
    # Open the download for the given flickr object and application config hash.
    # Note, the block is required.
    # flickr:: the rFlickr instance
    # config:: is the application's config hash.
    # block:: the required block responsible for downloading all photos for all the selection criteria.
    # Raises:: Interrupt
    def self.open(flickr, config, &block) # :yields: downloader
      downloader = Downloader.new(flickr, config)
      block.call(downloader)
      downloader.send('finish')
    end
    
    # Fetch the images from flick and save them in the local file system.
    # This method expects to be called by the self.open block.
    # Fetch intercepts :limit and :per_page, and :image_* arguments.
    # section:: a primary key in the application's config Hash whose value is a selection critieria Hash.  [:USERS, :GROUPS, :PHOTOSETS, :SEARCHES, :INTERESTING]
    # Raises:: Interrupt
    def fetch(section)
      @logger.debug {"fetch(#{section.to_s})"}
      unless @config[section].nil?
        @config[section].each do |arg_hash|
          @logger.info {"Downloading photos from #{section.to_s} (#{arg_hash.inspect})"}
          limit = arg_hash[:limit] || @config[:limit] || -1
          arg_hash[:per_page] = arg_hash[:per_page] || arg_hash[:limit] || @config[:limit] || 100
          image_bounds = get_image_bounds(arg_hash, @config)
          fetch_section(section, arg_hash, image_bounds, limit)
        end
      end
    end
    
    private
    
    # This method gets the list of photos for the section, then saves the photos.
    # section:: a primary key in the application's config Hash whose value is a selection critieria Hash.  [:USERS, :GROUPS, :PHOTOSETS, :SEARCHES, :INTERESTING]
    # arg_hash:: a Hash containing the criteria selection
    # image_bounds:: an ImageBounds instance with all of the bounding info for this photo.
    # limit:: the maximum number of photos to fetch
    # Raises:: Interrupt
    def fetch_section(section, arg_hash, image_bounds, limit)
      begin
        # fetch an Array of Photos that match the selection criteria
        methodname = 'fetch_' + section.to_s.downcase
        photos = send(methodname, @flickr, arg_hash, @logger)
        @logger.debug {"number of photos: #{photos.length}"}

        # save each photo
        photos[0..limit].each do |photo| 
          # handle ^C interruption
          raise Interrupt.new("FlickrFetchr was interrupted") if FlickrFetchr.interrupted?

          @logger.debug {"photo id: #{photo.id}"}
          photo.save(arg_hash, image_bounds, @config)
        end
      rescue Interrupt => iMsg
        raise iMsg
      rescue Exception => eMsg
        @logger.warn {eMsg.to_s}
        @logger.debug {eMsg.backtrace.join("\n")}
      end
    end
    
    # Called by open after the block completes (i.e., all the photos are downloaded) 
    # to give the plugins a chance to do any finalizing.
    def finish
      unless @config[:plugins].nil?
        @config[:plugins].each do |plugin_name|
          eval("#{plugin_name.to_s}.finish(@config)")
        end
      end
    end
  
    # Get an ImageBounds instance from the arg_hash, then application's config hash, then defaults.
    # arg_hash:: a Hash containing the criteria selection
    # config:: is the application's config hash.
    def get_image_bounds(arg_hash, config)
      ImageBounds.new(arg_hash[:image_width_range]  || config[:image_width_range]  || false, 
                      arg_hash[:image_height_range] || config[:image_height_range] || false,
                      arg_hash[:image_resize_to]    || config[:image_resize_to],
                      arg_hash[:image_fill_to]      || config[:image_fill_to],
                      config)
    end
  
    # Fetch photos by user name as specified in @config[:USERS]
    # flickr:: the rFlickr instance
    # arguments:: a Hash containing the criteria selection
    # logger:: logger for any user messages
    # Returns:: Array of Flickr::Photo objects
    def fetch_users(flickr, arguments, logger)
      arguments[:nsid] ||= flickr.people.findByUsername(arguments[:username])
      return flickr.people.getPublicPhotos(arguments[:nsid], arguments[:extras], arguments[:per_page], arguments[:page])
    end
    
    # Fetch photos by group IDs as specified in @config[:GROUPS]
    # flickr:: the rFlickr instance
    # arguments:: a Hash containing the criteria selection
    # logger:: logger for any user messages
    # Returns:: Array of Flickr::Photo objects
    def fetch_groups(flickr, arguments, logger)
      unless arguments[:groupname].nil?
        group = flickr.groups.search(arguments[:groupname]).select{|g| arguments[:groupname] == g.name}[0]
        arguments[:nsid] ||= group.nsid unless group.nil?
      end
      return flickr.groups.pools.getPhotos(arguments[:nsid], arguments[:tags], arguments[:extras], arguments[:per_page], arguments[:page])
    end

    # Fetch photos by user photoset as specified in @config[:PHOTOSETS]
    # flickr:: the rFlickr instance
    # arguments:: a Hash containing the criteria selection
    # logger:: logger for any user messages
    # Returns:: Array of Flickr::Photo objects
    def fetch_photosets(flickr, arguments, logger)
      fotos = []
      arguments[:nsid] ||= flickr.people.findByUsername(arguments[:username]).nsid
      photosets = flickr.photosets.getList(arguments[:nsid]).select{|s| arguments[:title].nil? ? true : arguments[:title] == s.title}
      photosets.each do |set|
        fotos += flickr.photosets.getPhotos(set, arguments[:extras])
      end
      return fotos
    end

    # Fetch photos by searching flickr as specified in @config[:SEARCHES]
    # flickr:: the rFlickr instance
    # arguments:: a Hash containing the criteria selection
    # logger:: logger for any user messages
    # Returns:: Array of Flickr::Photo objects
    def fetch_searches(flickr, arguments, logger)
      arguments[:nsid] ||= flickr.people.findByUsername(arguments[:username])
      return flickr.photos.search(arguments[:nsid], arguments[:tags], arguments[:tag_mode], arguments[:text],
                      arguments[:min_upload_date], arguments[:max_upload_date], arguments[:min_taken_date],
                      arguments[:max_taken_date], arguments[:license], arguments[:extras], arguments[:per_page],
                      arguments[:page], arguments[:sort])
    end

    # Fetch the interestingness photos for the past :daycount days as specified in @config[:INTERESTINGNESS]
    # this is how the current linuxmce /usr/pluto/bin/flickr.pl script queries flickr
    # flickr:: the rFlickr instance
    # arguments:: a Hash containing the criteria selection
    # logger:: logger for any user messages
    # Returns:: Array of Flickr::Photo objects
    def fetch_interesting(flickr, arguments, logger)
      fotos = []
      daycount = arguments[:daycount] || 0
      date = Date.today
      date = Date.parse(arguments[:date]) unless arguments[:date].nil?
      daycount.downto(0) do |day|
        begin
          fotos += flickr.interestingness.getList((date - day).to_s, arguments[:extras], arguments[:per_page], arguments[:page])
        rescue Exception => eMsg
          logger.warn {eMsg.to_s}
        end
      end
      return fotos
    end
  end
  
  # == Synopsis
  # Extend Flickr::Photo by adding save method
  #
  class Flickr::Photo # :doc:
    PHOTO_SIZES = [:Original, :Large, :Medium, :Small]
    
    # Download and save the photo image.
    # args:: a Hash containing the criteria selection. Uses: :destination_path, 
    # :destination_path_type, :max_save_attempts, :logger, :image_acceptable_types,
    # and :plugins.
    # image_bounds:: an ImageBounds instance with all of the bounding info for this photo.
    # config:: is the application's config hash.
    #
    # Notes:
    # * The largest possible image within the given boundary will be downloaded.
    # * @config[:max_save_attempts] define the maximum tries at save the image,
    #   this is to handle the occasional burps from flickr
    def save(args, image_bounds, config)
      logger = config[:logger]
      attempt = 0
      begin
        dest_path = destination_path(args[:destination_path], args[:destination_path_type], config)
        existing_files = Dir.glob(File.join(dest_path, "#{self.id.to_s}*.*"))
        if existing_files.empty?
          # get the symbol (:Original, :Large, :Medium, :Small) for the largest available size
          size_symbol = get_max_size(image_bounds, config)
          unless size_symbol.nil?
            # now get the uri to the source image
            source_uri = URI.parse sizes[size_symbol].source
            # and create a fully qualified filespec for the destination
            destination = photo_destination(args[:destination_naming], source_uri, dest_path, config)
            # now get the photo from the source_uri and save it as the destination
            download(source_uri, destination, image_bounds, config) if acceptable_image_type?(destination, config)
          end
        else
          logger.info {"Skipping #{self.id} => [#{existing_files.join(', ')}]"}
        end
      rescue Exception => errorMsg
        logger.warn {"Unable to save file #{destination} - #{errorMsg.to_s} (attempt: #{attempt})"}
        logger.debug {errorMsg.backtrace.join("\n")}
        attempt += 1
        unless attempt > config[:max_save_attempts]
          retry
        end
        exit
      end
    end
  
  private
  
    # Return the path where the photo should be stored
    # photo_dest is the base path that may be modified by the dest_type
    # If the dest_type is :date_path, then the returned path
    # will be "#{photo_dest}/YYYY/MM/DD"
    # photo_dest:: the directory where the photos should go unless modified by dest_type
    # dest_type:: if set to :date_path will return photo_dest/YYYY/MM/DD
    # config:: is the application's config hash.
    # Returns:: path to directory for the image.
    def destination_path(photo_dest, dest_type, config)
      path = case dest_type
      when :date_path
        flickr.photos.getInfo(self)
        File.join(photo_dest, time_to_path(self.dates[:posted]))
      else
        photo_dest
      end
      config[:logger].debug {"destination_path(#{photo_dest}, #{dest_type.inspect}) => #{path}"}
      path
    end
  
    # Create the final filespec for the photo.
    # If the naming_type is :short or :id, then use the photo's id
    # for the base filename, otherwise use the name from Flickr
    # naming_type:: if :short or :id, then use the photo ID for the base filename, else use the basename from uri
    # uri:: the URI of the file on flickr
    # dest_path:: the directory to save the image in.
    # config:: is the application's config hash.
    # Returns:: expanded path String
    def photo_destination(naming_type, uri, dest_path, config)
      path = case naming_type
      when :short, :id
        File.join(dest_path, self.id.to_s + File.extname(uri.path))
      else
        File.join(dest_path, File.basename(uri.path))
      end
      config[:logger].debug {"photo_destination(#{naming_type}, #{uri}, #{dest_path}) => #{path}"}
      File.expand_path path
    end
  
    # Linuxmce stores flickr images in a YYYY/MM/DD hierarchy, so this
    # method will convert the given Time into a "YYYY/MM/DD" path.
    # Called when :destination_path_type is :date_path
    # time:: a Time instance, usually from the photo's dates Hash.
    # Returns:: "YYYY/MM/DD" String
    def time_to_path(time)
      date = Date.new(time.year, time.month, time.day)
      date.to_s.gsub(/\-/, '/')
    end
  
    # Check if the image type as determined by the file extension is
    # in the :image_acceptable_types list.  If the :image_acceptable_types
    # list is empty or nil, then all extensions are acceptable.
    # filespec:: the image's filespec
    # config:: is the application's config hash.
    # Returns:: true if the image type is acceptable, false otherwise
    def acceptable_image_type?(filespec, config)
      acceptable = true
      unless config[:image_acceptable_types].nil? || config[:image_acceptable_types].empty?
        dot_ext = File.extname filespec
        no_dot_ext = dot_ext.gsub('.', '')
        acceptable = config[:image_acceptable_types].include?(dot_ext) || config[:image_acceptable_types].include?(no_dot_ext)
      end
      acceptable
    end
  
    # Get the label for the maximum size available for the given photo.
    # image_bounds:: the ImageBounds instance that contains the boundary info for this photo.
    # config:: is the application's config hash.
    # Returns:: label (:Original, :Large, :Medium, or :Small)
    # Note: photo.flickr.photos.getSizes can raise an Exception
    def get_max_size(image_bounds, config)
      label = nil
      flickr.photos.getSizes(self)
      PHOTO_SIZES.reverse.each do |key|
        unless sizes[key].nil?
          if image_bounds.within?(sizes[key].width, sizes[key].height)
            label = key
          end
        end
      end
      if label.nil?
        config[:logger].debug do 
          avail = sizes.collect{|k,v| "#{v.label}(#{v.width}x#{v.height})"}.join(', ')
          "Could not find image with size with requested bounds (#{image_bounds.to_s}).  Available sizes are #{avail}"
        end
      end
      label
    end
    
    # Finally download and save the photo from flickr
    # source_uri:: the URI to the file on flickr
    # destination:: the filespec where we should download the photo to.
    # image_bounds:: the ImageBounds instance that contains the boundary info for this photo.
    # config:: is the application's config hash.
    def download(source_uri, destination, image_bounds, config)
      # don't re-download if the file already exists locally
      prefix = config[:pretend] ? '[pretend] ' : ''
      unless File.exists? destination
        begin
          unless config[:pretend]
            config[:logger].info {prefix + "downloading #{source_uri} to #{destination}"}
            system("mkdir -p \"#{File.dirname(destination)}\"")
            plugin_send(:pre_download, destination, config)
            File.open(destination, "wb") {|f| f.write(open(source_uri).read)}
            image_bounds.resize destination
            image_bounds.fill_to destination
            plugin_send(:post_download, destination, config)
          end
        rescue => eMsg
          config[:logger].warn {prefix + "Unable to download #{destination} - #{eMsg.to_s}"}
          config[:logger].debug {eMsg.backtrace.join("\n")}
          # something bad happened, so cleanup the partially written local image file if it exists
          File.delete destination if File.exists? destination
          plugin_send(:on_download_error, destination, config)
        end
      else
        config[:logger].info {prefix + "Skipping #{source_uri} => #{destination}"}
      end
    end
    
    # Call given method for each of the plugins (config[:plugins] Array)
    # method:: the method on the plugin instance to invoke (plugin.method(destination))
    # destination:: the image's destination filespec
    # config:: is the application's config hash.
    def plugin_send(method, destination, config)
      unless config[:plugins].nil?
        config[:plugins].each do |plugin_name|
          plugin = eval("#{plugin_name.to_s}.new(config)")
          plugin.send(method.to_s, destination)
        end
      end
    end
    
  end
  
end

# Are we running this file from the command line?
if __FILE__ == $0

    # == Synopsis
  # The Runner module encapsulates the command line application
  module Runner

    # == Synopsis
    # Command line exit codes
    class ExitCode
      UNKNOWN = 3
      CRITICAL = 2
      WARNING = 1
      OK = 0
    end
  
    # Run the command-line application
    # args:: the command-line argument Array
    # Returns:: ExitCode value
    def self.run(args)
      exit_code = ExitCode::OK
      
      # we start a STDOUT logger, but it will be switched after 
      # the config files are read if config[:logger_output] is set
      logger = Log4r::Logger.new('flickrfetchr')
      logger.outputters = Log4r::StdoutOutputter.new(:console)
      logger.level = Log4r::DEBUG
      
      begin
        # trap ^C interrupts and let the FlickrFetchr instance cleanly exit any long loops
        Signal.trap("INT") {FlickrFetchr.interrupt}
        
        # parse the command line
        options = setupParser()
        od = options.parse(args)

        # load config values
        default_config = defaultConfig()
        config = default_config
        config[:pretend] = od["--pretend"]
        config[:setup] = od["--setup"]
        
        # the first reinitialize_logger adds the command line logging options to the default config
        # then we load the config files
        # then we run reinitialize_logger again to modify the logger for any logging options from the config files
        
        reinitialize_logger(logger, config, od["--verbose"], od["--debug"])
        config = load_configs(config.dup, logger)
        reinitialize_logger(logger, config, od["--verbose"], od["--debug"])
        
        # create and execute class instance here
        unless config[:setup]
          fetchr = FlickrFetchr.new(config)
          fetchr.execute
        end
      rescue Exception => eMsg
        logger.error {eMsg.to_s}
        logger.error {options.to_s}
        logger.error {eMsg.backtrace.join("\n")}
        exit_code = ExitCode::CRITICAL
      end
      exit_code
    end

    # Default configuration values
    # Returns:: is the application's config hash.
    def self.defaultConfig()
      config = {}
      config[:app_name] = APP_NAME
      config[:app_version] = APP_VERSION
      config[:config_template] = File.expand_path(File.join(File.dirname(__FILE__), 'flickrfetchr.conf.erb'))
      config[:token_cache_file] = File.join(ENV['HOME'], ".flickrfetchr.cache")
      config[:limit] = 100
      config[:max_save_attempts] = 3
      config[:image_width_range] = 1000..1920
      config[:image_height_range] = 720..1080
      config[:image_resize_to]  = nil
      config[:image_acceptable_types] = []
      config[:logfile] = '/var/log/flickrfetchr.log'
      config[:logfile_level] = Log4r::DEBUG
      config[:setup] = false
      config[:GROUPS] = []
      config[:SEARCHES] = []
      config[:USERS] = []
      config[:PHOTOSETS] = []
      config[:INTERESTING] = []
      config
    end

    # Load the config files.
    # config:: is the application's config hash.
    # logger:: logger for any user messages
    # Returns:: is the application's config hash.
    def self.load_configs(config, logger)
      configFile = File.basename(__FILE__, ".*") + '.conf'
      dotConfigFile = '.' + configFile
      [
        File.join('/etc', configFile), 
        File.join("#{ENV['HOME']}", dotConfigFile)
      ].each do |filespec|
        loaded_config = load_conf_file(filespec, config, logger, config[:setup])
        config.merge! loaded_config
      end
      config
    end

    # Setup the command line option parser
    # Returns:: OptionParser instances
    def self.setupParser()
      options = OptionParser.new()
      options << Option.new(:flag, :names => %w(--help), 
                            :opt_found => lambda {Log4r::Logger['flickrfetchr'].error{options.to_s} ; exit(ExitCode::OK)}, 
                            :opt_description => "This usage information")
      options << Option.new(:flag, :names => %w(--pretend -p))
      options << Option.new(:flag, :names => %w(--verbose -v))
      options << Option.new(:flag, :names => %w(--debug -d))
      options << Option.new(:flag, :names => %w(--setup -s))
      options
    end

    # Load the given config file
    # filename:: config file name to load
    # config:: is the application's config hash.
    # logger:: logger for any user messages
    # create_config_file:: if true, then create the config file if it doesn't exist
    # Returns:: is the application's config hash.
    # Raises:: Exception
    def self.load_conf_file(filespec, config_hash, logger, create_config_file)
      logger.info {"Loading #{filespec}"}
      begin
        result = config_hash.dup
        if create_config_file
          create_config_file(filespec, config_hash, logger) unless File.exists? filespec
        end
        if File.exists? filespec
          str = IO.read(filespec)
          sections = {}
          FlickrFetchr::SECTIONS.each {|section| sections[section] = config_hash[section]}
          result.merge! eval("config=#{sections.inspect}\n#{str}\nconfig")
        end
        result
      rescue Exception => eMsg
        logger.error {"Error loading config file (#{filespec}) - #{eMsg.to_s}"}
        logger.info {eMsg.backtrace.join("\n")}
        raise eMsg
      end
    end

    # Create the given config file and populate it with lots of comments :)
    # filename:: config file name to create
    # config:: is the application's config hash.
    # logger:: logger for any user messages
    # Raises:: Exception
    def self.create_config_file(filename, config, logger)
      begin
        logger.info {"Creating config file: #{filename}"}
        if File.exists? config[:config_template]
          template = ERB.new(IO.read(config[:config_template]), 0, "%")
          File.open(filename, "w") do |file|
            file.puts template.result(binding)
          end
        else
          logger.warn {"Could not find config file template: #{config[:config_template]}"}
        end
      rescue Exception => eMsg
        logger.error {"Error creating config file (#{filename}) - #{eMsg.to_s}"}
        logger.info {eMsg.backtrace.join("\n")}
        raise eMsg
      end
    end

    # Reinitialize the logger using the loaded config.
    # logger:: logger for any user messages
    # config:: is the application's config hash.
    def self.reinitialize_logger(logger, config, verbose, debug)
      # switch the logger to the one specified in the config files
      unless config[:logfile].nil?
        logfile_outputter = Log4r::RollingFileOutputter.new(:logfile, :filename => config[:logfile], :maxsize => 1000000 )
        logger.add logfile_outputter
        logfile_outputter.level = Log4r::INFO
        Log4r::Outputter[:logfile].formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :: %M")
        unless config[:logfile_level].nil?
          level_map = {'DEBUG' => Log4r::DEBUG, 'INFO' => Log4r::INFO, 'WARN' => Log4r::WARN}
          logfile_outputter.level = level_map[config[:logfile_level]] || Log4r::INFO
        end
      end
      Log4r::Outputter[:console].level = Log4r::WARN
      Log4r::Outputter[:console].level = Log4r::INFO if verbose
      Log4r::Outputter[:console].level = Log4r::DEBUG if debug
      # logger.trace = true
      config[:logger] = logger
    end

    # This is a support method for flickrfetchr.conf.erb
    #
    # Generate config file selection criteria documentation
    #
    #   # config[:ctag] =
    #   #   [
    #   #     {
    #   #       options[:otags[0]]
    #   #       options[:otags[1]]
    #   #       ...
    #   #       options[:otags[N]]
    #   #     }
    #   #   ]
    #
    # ctag:: the selection criteria key [:USERS, :GROUPS, :PHOTOSETS, :SEARCHES, :INTERESTING]
    # options:: a Hash whose key is an option symbol and whos value is a comment describing that option.
    # otags:: a set of option symbols to loopkup in the options Hash.
    # Returns:: the expanded comment String
    def self.gen_config_doc(ctag, options, otags=[])
      buf = []
      buf << "# config[#{ctag}] ="
      buf << "#   ["
      buf << "#    {"
      otags.each {|t| buf << options[t]}
      buf << "#    }"
      buf << "#   ]"
      buf.join("\n")
    end

  end
  
  exit Runner.run(ARGV)
end


