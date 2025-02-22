# dependencies
require "openssl"
require "securerandom"

# modules
require "lockbox/box"
require "lockbox/encryptor"
require "lockbox/key_generator"
require "lockbox/io"
require "lockbox/migrator"
require "lockbox/model"
require "lockbox/padding"
require "lockbox/utils"
require "lockbox/version"

# integrations
require "lockbox/carrier_wave_extensions" if defined?(CarrierWave)
require "lockbox/railtie" if defined?(Rails)

if defined?(ActiveSupport)
  ActiveSupport.on_load(:active_record) do
    extend Lockbox::Model
  end

  ActiveSupport.on_load(:mongoid) do
    Mongoid::Document::ClassMethods.include(Lockbox::Model)
  end
end

module Lockbox
  class Error < StandardError; end
  class DecryptionError < Error; end
  class PaddingError < Error; end

  extend Padding

  class << self
    attr_accessor :default_options
    attr_writer :master_key
  end
  self.default_options = {}

  def self.master_key
    @master_key ||= ENV["LOCKBOX_MASTER_KEY"]
  end

  def self.migrate(model, restart: false)
    Migrator.new(model).migrate(restart: restart)
  end

  def self.generate_key
    SecureRandom.hex(32)
  end

  def self.generate_key_pair
    require "rbnacl"
    # encryption and decryption servers exchange public keys
    # this produces smaller ciphertext than sealed box
    alice = RbNaCl::PrivateKey.generate
    bob = RbNaCl::PrivateKey.generate
    # alice is sending message to bob
    # use bob first in both cases to prevent keys being swappable
    {
      encryption_key: to_hex(bob.public_key.to_bytes + alice.to_bytes),
      decryption_key: to_hex(bob.to_bytes + alice.public_key.to_bytes)
    }
  end

  def self.attribute_key(table:, attribute:, master_key: nil, encode: true)
    master_key ||= Lockbox.master_key
    raise ArgumentError, "Missing master key" unless master_key

    key = Lockbox::KeyGenerator.new(master_key).attribute_key(table: table, attribute: attribute)
    key = to_hex(key) if encode
    key
  end

  def self.to_hex(str)
    str.unpack("H*").first
  end

  # legacy
  def self.new(**options)
    Encryptor.new(**options)
  end
end
