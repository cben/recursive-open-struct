puts "RUBY_VERSION: #{RUBY_VERSION}"

require 'yaml'
require "net/http"
require "uri"
require "active_support/core_ext/hash"
require "benchmark/ips"
require 'recursive_open_struct'

uri = URI.parse("https://cdn.rawgit.com/ManageIQ/manageiq/95130f3360a4abd82128ad2c23550d837799bb45/locale/en.yml")
response = Net::HTTP.get_response(uri)

large_hash = YAML.load(response.body)
large_hash_syms = large_hash.deep_symbolize_keys

puts "keys: #{large_hash["en"]["dictionary"]["column"].keys.size}"
r = RecursiveOpenStruct.new(large_hash).en.dictionary.column
puts "methods.size before accessing: #{r.methods.size}"
large_hash["en"]["dictionary"]["column"].keys.each { |k| r.send(k) }
puts "methods.size after accessing: #{r.methods.size}"
puts "methods(false).size after accessing: #{r.methods(false).size}"

small_hash = { :a => { :b => 'c' } }

Benchmark.ips do |x|
  syms = (:sym000..:sym999).to_a
  x.report("array #{syms.size} symbols .include?") { syms.each { |k| syms.include?(k) } }
end

# Throw in unsubclassed RecursiveOpenStruct...
class RecursiveOpenStruct
  BENCH_NAME = 'RecursiveOpenStruct methods.include?'
end
# and also subclass with original code in case subclassing has overhead
class ROS_MI < RecursiveOpenStruct
  BENCH_NAME = 'subclassed methods.include?'

  def new_ostruct_member(name)
    key_name = _get_key_from_table_(name)
    unless self.methods.include?(name.to_sym)  # <---
      class << self; self; end.class_eval do
        define_method(name) do
          self[key_name]
        end
        define_method("#{name}=") do |x|
          @sub_elements.delete(key_name)
          modifiable[key_name] = x
        end
        define_method("#{name}_as_a_hash") { @table[key_name] }
      end
    end
    key_name
  end
  alias new_ostruct_member! new_ostruct_member
end

class ROS_MFI < RecursiveOpenStruct
  BENCH_NAME = 'methods(false).include?'

  def new_ostruct_member(name)
    key_name = _get_key_from_table_(name)
    unless self.methods(false).include?(name.to_sym)  # <---
      class << self; self; end.class_eval do
        define_method(name) do
          self[key_name]
        end
        define_method("#{name}=") do |x|
          @sub_elements.delete(key_name)
          modifiable[key_name] = x
        end
        define_method("#{name}_as_a_hash") { @table[key_name] }
      end
    end
    key_name
  end
  alias new_ostruct_member! new_ostruct_member
end

class ROS_MD < RecursiveOpenStruct
  BENCH_NAME = 'method_defined?'

  def new_ostruct_member(name)
    key_name = _get_key_from_table_(name)
    unless self.singleton_class.method_defined?(name.to_sym)  # <---
      class << self; self; end.class_eval do
        define_method(name) do
          self[key_name]
        end
        define_method("#{name}=") do |x|
          @sub_elements.delete(key_name)
          modifiable[key_name] = x
        end
        define_method("#{name}_as_a_hash") { @table[key_name] }
      end
    end
    key_name
  end
  alias new_ostruct_member! new_ostruct_member
end

class ROS_R < RecursiveOpenStruct
  BENCH_NAME = 'respond_to?'

  # TODO: respond_to_missing? makes respond_to? true for all fields in @table.
  # Can I ask respond_to? bypassing respond_to_missing? ?
  def respond_to_missing?(mid, include_private = false)
    false # BUG!
  end

  def new_ostruct_member(name)
    key_name = _get_key_from_table_(name)
    unless self.respond_to?(name.to_sym)  # <---
      class << self; self; end.class_eval do
        define_method(name) do
          self[key_name]
        end
        define_method("#{name}=") do |x|
          @sub_elements.delete(key_name)
          modifiable[key_name] = x
        end
        define_method("#{name}_as_a_hash") { @table[key_name] }
      end
    end
    key_name
  end
  alias new_ostruct_member! new_ostruct_member
end

class ROS_SI < RecursiveOpenStruct
  BENCH_NAME = '@sub_elements.include? (BUG?)'

  def new_ostruct_member(name)
    key_name = _get_key_from_table_(name)
    unless @sub_elements.include?(name.to_sym)  # <---
      class << self; self; end.class_eval do
        define_method(name) do
          self[key_name]
        end
        define_method("#{name}=") do |x|
          @sub_elements.delete(key_name)
          modifiable[key_name] = x
        end
        define_method("#{name}_as_a_hash") { @table[key_name] }
      end
    end
    key_name
  end
  alias new_ostruct_member! new_ostruct_member
end

class ROS_FALSE < RecursiveOpenStruct
  BENCH_NAME = 'false (BUG?)'

  def new_ostruct_member(name)
    key_name = _get_key_from_table_(name)
    unless false  # BUG?! <---
      class << self; self; end.class_eval do
        define_method(name) do
          self[key_name]
        end
        define_method("#{name}=") do |x|
          @sub_elements.delete(key_name)
          modifiable[key_name] = x
        end
        define_method("#{name}_as_a_hash") { @table[key_name] }
      end
    end
    key_name
  end
  alias new_ostruct_member! new_ostruct_member
end

class ROS_NO_METHODS < RecursiveOpenStruct
  BENCH_NAME = 'dont create methods'

  def method_missing(mid, *args)
    len = args.length
    if mid =~ /^(.*)=$/
      if len != 1
        raise ArgumentError, "wrong number of arguments (#{len} for 1)", caller(1)
      end
      # Not doing:
      #modifiable[new_ostruct_member!($1.to_sym)] = args[0]
      self[$1] = args[0]
    elsif len == 0
      key = mid
      if key =~ /^(.*)_as_a_hash$/
        @table[$1]
      else
        self[key]
      end
      # Not doing:
      #new_ostruct_member!(key)
      #send(mid)
    else
      err = NoMethodError.new "undefined method `#{mid}' for #{self}", mid, args
      err.set_backtrace caller(1)
      raise err
    end
  end
end

IMPLEMENTATIONS = [RecursiveOpenStruct, ROS_MI, ROS_MFI, ROS_MD, ROS_R, ROS_SI, ROS_FALSE]
# Omit this by default because it's fastest and skews all "4x slower" to be compared to it.
if ENV['HERESY']
  IMPLEMENTATIONS << ROS_NO_METHODS
end

ACCESS_TIMES = 5

Benchmark.ips do |x|
  IMPLEMENTATIONS.each do |ros|
    x.report("Small hash - #{ros::BENCH_NAME}") do
      r = ros.new(small_hash)
      ACCESS_TIMES.times { r.a.b }
    end
  end
  x.compare!
end

Benchmark.ips do |x|
  IMPLEMENTATIONS.each do |ros|
    x.report("Large hash (strings) - #{ros::BENCH_NAME}") do
      r = ros.new(large_hash).en.dictionary.column
      ACCESS_TIMES.times { large_hash["en"]["dictionary"]["column"].keys.each { |k| r.send(k) } }
    end
  end
  x.compare!
end

Benchmark.ips do |x|
  IMPLEMENTATIONS.each do |ros|
    x.report("Large hash (symbols) - #{ros::BENCH_NAME}") do
      r = ros.new(large_hash_syms).en.dictionary.column
      large_hash_syms[:en][:dictionary].keys.each { |k| r.send(k) }
      ACCESS_TIMES.times {  large_hash_syms[:en][:dictionary][:column].keys.each { |k| r.send(k) } }
    end
  end
  x.compare!
end
