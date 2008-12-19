require 'lib/flickrfetchr.rb'
require 'test/unit'
require 'stringio'
require 'logger'

class TestBoundary < Test::Unit::TestCase
  WMIN = 1024
  WMAX = 1920
  HMIN = 720
  HMAX = 1080
  
  def setup
    @logs = StringIO.new("", "w")
    @config = {:logger => Logger.new(@logs), :pretend => true}
    @fill_to = nil
    @config[:token_cache_file] = File.join(ENV['HOME'], ".flickrfetchr.cache")
    @flickr = Flickr.new(@config[:token_cache_file], FlickrFetchr::FLICKR_FETCHR_API_KEY, FlickrFetchr::FLICKR_FETCHR_SHARED_SECRET)
  end
  
  def test_within
    b = FlickrFetchr::ImageBounds.new(WMIN..WMAX, HMIN..HMAX, {:width => WMAX, :height => HMAX}, @fill_to, @config)
    assert(b.within?(WMIN,     HMIN))
    assert(b.within?(WMIN + 1, HMIN))
    assert(b.within?(WMIN,     HMIN + 1))
    assert(b.within?(WMIN + 1, HMIN + 1))
    
    assert(b.within?(WMAX,     HMAX))
    assert(b.within?(WMAX - 1, HMAX))
    assert(b.within?(WMAX,     HMAX - 1))
    assert(b.within?(WMAX - 1, HMAX - 1))
    
    assert(!b.within?(WMIN - 1, HMIN))
    assert(!b.within?(WMIN,     HMIN - 1))
    assert(!b.within?(WMIN - 1, HMIN - 1))
  
    assert(!b.within?(WMAX + 1, HMAX))
    assert(!b.within?(WMAX,     HMAX + 1))
    assert(!b.within?(WMAX + 1, HMAX + 1))
  end
  
  def test_within_minimum
    b = FlickrFetchr::ImageBounds.new(WMIN, HMIN, {:width => WMAX, :height => HMAX}, @fill_to, @config)
    
    assert(b.within?(WMIN,     HMIN))
    assert(b.within?(WMIN + 1, HMIN))
    assert(b.within?(WMIN,     HMIN + 1))
    assert(b.within?(WMIN + 1, HMIN + 1))
    
    assert(b.within?(WMAX,     HMAX))
    assert(b.within?(WMAX - 1, HMAX))
    assert(b.within?(WMAX,     HMAX - 1))
    assert(b.within?(WMAX - 1, HMAX - 1))
    
    assert(!b.within?(WMIN - 1, HMIN))
    assert(!b.within?(WMIN,     HMIN - 1))
    assert(!b.within?(WMIN - 1, HMIN - 1))
  
    assert(b.within?(WMAX + 1, HMAX))
    assert(b.within?(WMAX,     HMAX + 1))
    assert(b.within?(WMAX + 1, HMAX + 1))
  end
  
  def test_acceptable_image_type
    photo = Flickr::Photo.new(@flickr, 12345)
    @config[:image_acceptable_types] = ['jpg', 'png']
    # for :linuxmce_flickr destination only .jpg extension is acceptable
    assert(photo.send('acceptable_image_type?', 'foo.jpg', @config), 'foo.jpg')
    
    @config[:image_acceptable_types] = ['jpg']
    %w(jpeg png JPG JPEG PNG).each do |ext|
      assert(!photo.send('acceptable_image_type?', "foo.#{ext}", @config), "foo.#{ext}")
    end
    
    @config[:image_acceptable_types] = []
    %w(jpg jpeg png JPG JPEG PNG).each do |ext|
      assert(photo.send('acceptable_image_type?', "foo.#{ext}", @config), "foo.#{ext}")
    end
    
    @config[:image_acceptable_types] = nil
    %w(jpg jpeg png JPG JPEG PNG).each do |ext|
      assert(photo.send('acceptable_image_type?', "foo.#{ext}", @config), "foo.#{ext}")
    end
  end
  

  # LinuxMCE uses the photo_id.jpg for the filename
  # for other destinations, return nil
  def test_photo_destination
    photo = Flickr::Photo.new(@flickr, 12345)
    dest_path = '/a/b/c'
    uri = URI.parse("http://example.com/path/12345_67890.jpg")
    filespec = photo.send('photo_destination', :short, uri, dest_path, @config)
    assert(filespec == File.join(dest_path, "12345.jpg"))
    
    filespec = photo.send('photo_destination', :id, uri, dest_path, @config)
    assert(filespec == File.join(dest_path, "12345.jpg"))
    
    filespec = photo.send('photo_destination', :normal, uri, dest_path, @config)
    assert(filespec == File.join(dest_path, "12345_67890.jpg"))
    
    filespec = photo.send('photo_destination', nil, uri, dest_path, @config)
    assert(filespec == File.join(dest_path, "12345_67890.jpg"))
  end

  def test_time_to_path
    photo = Flickr::Photo.new(@flickr, 12345)
    assert(photo.send('time_to_path', Time.parse('July 4 2008')) == '2008/07/04')
  end
  
  def test_load_plugins
    app = FlickrFetchr.new(@config)
    @logs.string = ''
    app.send('collect_plugins', @config)
    app.send('load_plugins', @config)
    assert(@logs.string !~ /require "flickrfetchr-linuxmce.rb"/, "test_load_plugins logs => #{@logs.string}")
    
    @logs.string = ''
    @config[:GROUPS] = [{:plugins => :LinuxMCE_Plugin}]
    app.send('collect_plugins', @config)
    app.send('load_plugins', @config)
    assert(@logs.string =~ /require "flickrfetchr-linuxmce.rb"/, "test_load_plugins logs => #{@logs.string}")
    words = {}
    @logs.string.split(/[\s\(\)\[\]\-]/).each {|w| words[w] ||= 0; words[w] += 1}
    assert(words['require'] == 1, "checking exactly one require")
    assert(words['INFO'] == 1, "checking that there are only one infos: log => " + @logs.string)
    assert(words['ERROR'].nil?, "checking that there are no errors: log => " + @logs.string)
    
    @logs.string = ''
    @config[:USERS] = [{:plugins => :LinuxMCE_Plugin}]
    app.send('collect_plugins', @config)
    app.send('load_plugins', @config)
    assert(@logs.string =~ /require "flickrfetchr-linuxmce.rb"/, "test_load_plugins logs => #{@logs.string}")
    words = {}
    @logs.string.split(/[\s\(\)\[\]\-]/).each {|w| words[w] ||= 0; words[w] += 1}
    # we have already successfully loaded the plugin, so the require will fail on the second attempt.  
    # This is a testing artifact and not a problem.
    assert(words['INFO'] == 1, "checking that there are only one infos: log => " + @logs.string)
    assert(words['ERROR'] == 1, "checking that there are only one errors: log => " + @logs.string)
  end
end