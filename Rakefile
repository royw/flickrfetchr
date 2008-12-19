require 'rake'
require 'date'
require 'erb'
Gem::manage_gems
require 'rake/gempackagetask'
require 'rake/clean'
require 'rake/testtask'

COPYRIGHT = "Copyright #{Time.now.year} by Roy Wright"
LICENSE   = 'License: GPL version 2 (http://www.opensource.org/licenses/gpl-2.0.php)'

APP_NAME = 'FlickrFetchr'
APP_VERSION = '0.2.0'
APP_AUTHOR = 'Roy Wright'
APP_EMAIL = 'roy@wright.org'
APP_HOMEPAGE = 'http://rubyforge.org/projects/flickrfetchr/'
APP_RUBYFORGE = 'flickrfetchr'
DIST_FILENAME = "flickrfetchr-#{APP_VERSION}.tgz"

SRC = 'src'
OUT = 'out'
TEST = 'test'
BIN = 'bin'
LIB = 'lib'
REPORTS = 'reports'

desc "prepare for packaging"
task :prepare => [:clean, :version, :test, :metrics, :docs]

desc "Verify that everything is checked in and ok to build a package"
task(:svn_ok) do
  stat = `svn stat .`
  if stat.length > 0
    puts "You need to check the svn status"
    puts stat
    exit(-1)
  end
end

desc "check that the APP_NAME and APP_VERSION match between flickrfetchr.rb and Rakefile"
task(:version => :svn_ok) do |t|
  puts "#{t.name} - #{t.comment}"
  errors = 0
  IO.foreach("#{LIB}/flickrfetchr.rb") do |line|
    if line =~ /^APP_NAME\s*=\s*['"]([^'"]+)['"]/
      unless $1 == APP_NAME
        puts "APP_NAME does not match between #{LIB}/flickrfetchr.rb and this Rakefile"
        puts "#{SRC}/flickrfetchr.rb => #{line}"
        puts "Rakefile => APP_NAME = #{APP_NAME}"
        errors += 1
      end
    end
    if line =~ /^APP_VERSION\s*=\s*['"]([^'"]+)['"]/
      unless $1 == APP_VERSION
        puts "APP_VERSION does not match between #{LIB}/flickrfetchr.rb and this Rakefile"
        puts "#{LIB}/flickrfetchr.rb => #{line}"
        puts "Rakefile => APP_VERSION = #{APP_VERSION}"
        errors += 1
      end
    end
  end
  if errors > 0
    puts "#{errors} error(s) found"
    exit(-1)
  else
    puts "APP_NAME and APP_VERSION are good"
    puts "APP_NAME = #{APP_NAME}"
    puts "APP_VERSION = #{APP_VERSION}"
  end
end

desc "run metrics"
task :metrics do
  sh "mkdir -p #{REPORTS}"
  sh "flog #{LIB}/*.rb > #{REPORTS}/flog.txt"
  sh "saikuro -c -t -y 0 -i #{LIB} -o #{REPORTS}"
  sh "sloccount #{LIB}/*.rb > #{REPORTS}/sloc.txt"
  sh "rcov #{TEST}/*.rb"
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/test*.rb']
  t.verbose = true
end


file "README" => "#{SRC}/README.erb" do
  dist_filename = DIST_FILENAME
  readme_template = ERB.new(IO.read(File.join(SRC, 'README.erb')))
  File.open('README', "w") do |file|
    file.puts readme_template.result(binding)
  end
end

file "flickrfetchr.conf" => "#{SRC}/flickrfetchr.conf.erb" do
  config = {
    :app_name => APP_NAME,
    :app_version => APP_VERSION,
    :limit => 100,
    :max_save_attempts => 3
  }
  out_filename = File.expand_path('flickrfetchr.conf')
  src_filename = File.expand_path(File.join(SRC, 'flickrfetchr.conf.erb'))
  if File.exists? src_filename
    template = ERB.new(IO.read(src_filename), 0, "%")
    File.open(out_filename, "w") do |file|
      file.puts template.result(binding)
    end
  end
end

file 'revision' do
  revision = ''
  `svn info .`.each {|line| revision=$1 if line =~ /^Revision\:\s*(\d+)/}
  unless revision.empty?
    filename = 'revision'
    File.delete filename if File.exists? filename
    File.open(filename, "w") do |file|
      file.puts revision
    end
  end
end

desc "create documenation"
task :docs => ['README', 'flickrfetchr.conf'] do |t|
  doc_dir = File.expand_path 'docs'
  sh "rm -rf #{doc_dir}"
  sh rdoc_command(doc_dir)
end

task :package => [:clean]

CLEAN.include('pkg')
CLEAN.include('docs')
CLEAN.include('README')
CLEAN.include('flickrfetchr.conf')

spec = Gem::Specification.new do |s|
  s.name = APP_NAME
  s.version = APP_VERSION
  s.author = APP_AUTHOR
  s.email = APP_EMAIL
  s.homepage = APP_HOMEPAGE
  s.rubyforge_project = APP_RUBYFORGE
  s.platform = Gem::Platform::RUBY
  s.summary = 'A high-level class that allows easy fetching of photos from flickr'
  s.files = FileList["{bin,lib,test}/**/*"]
  s.require_path = 'lib'
  s.test_file = 'test/testflickrfetchr.rb'
  s.has_rdoc = true
  s.extra_rdoc_files = ["README", "flickrfetchr.conf", "revision"]
  s.add_dependency("rflickr", "=2006.02.01")
  s.add_dependency("log4r", ">=1.0.5")
  s.add_dependency("rmagick", ">=2.5.0")
  s.add_dependency("commandline", ">=0.7.10")
  # dbi is not yet available as a gem, but the next release is suppose to be
  # s.add_dependency("dbi", ">=0.2.0")
end

desc "create gem"
Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = true
end

#--------------- Helpers

def rdoc_command(doc_dir)
  "rdoc --all --diagram --line-numbers --promiscuous --main #{LIB}/flickrfetchr.rb --fmt HTML --op=#{doc_dir} #{LIB}/*.rb README flickrfetchr.conf"
end

# Generate config file selection criteria documentation
#   # config[:ctag] =
#   #   [
#   #     {
#   #       options[:otags[0]]
#   #       options[:otags[1]]
#   #       ...
#   #       options[:otags[N]]
#   #     }
#   #   ]
# ctag:: the selection criteria key [:USERS, :GROUPS, :PHOTOSETS, :SEARCHES, :INTERESTING]
# options:: a Hash whose key is an option symbol and whos value is a comment describing that option.
# otags:: a set of option symbols to loopkup in the options Hash.
# Returns:: the expanded comment String
def gen_config_doc(ctag, options, otags=[])
  buf = []
  buf << "# config[#{ctag}] ="
  buf << "#   ["
  buf << "#    {"
  otags.each {|t| buf << options[t]}
  buf << "#    }"
  buf << "#   ]"
  buf.join("\n")
end

