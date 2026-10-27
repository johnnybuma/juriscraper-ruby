# frozen_string_literal: true

require "openssl"

module Juriscraper
  module Pacer
    module TOTP
      module_function

      def code(secret, time: Time.now.to_i)
        raw = secret.to_s.upcase.gsub(/[\s=-]/, "")
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        raise ConfigurationError, "PACER TOTP secret must be Base32" if raw.empty? || raw.chars.any? { |c| !alphabet.include?(c) }
        bits = raw.chars.map { |c| alphabet.index(c).to_s(2).rjust(5, "0") }.join
        key = bits.scan(/.{8}/).map { |byte| byte.to_i(2) }.pack("C*")
        raise ConfigurationError, "PACER TOTP secret is too short" if key.empty?
        digest = OpenSSL::HMAC.digest("SHA1", key, [time.to_i / 30].pack("Q>"))
        offset = digest.getbyte(-1) & 15
        value = digest.byteslice(offset, 4).unpack1("N") & 0x7fffffff
        format("%06d", value % 1_000_000)
      end
    end
  end
end
