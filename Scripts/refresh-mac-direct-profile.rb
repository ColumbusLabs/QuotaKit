#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

API_ROOT = "https://api.appstoreconnect.apple.com/v1"

def required_env(name)
  value = ENV[name]
  abort("ERROR: #{name} is required.") if value.nil? || value.empty?
  value
end

def base64url(value)
  Base64.urlsafe_encode64(value, padding: false)
end

def jwt
  key_id = required_env("APP_STORE_CONNECT_KEY_ID")
  issuer_id = required_env("APP_STORE_CONNECT_ISSUER_ID")
  private_key = OpenSSL::PKey::EC.new(File.read(required_env("APP_STORE_CONNECT_API_KEY_FILE")))
  now = Time.now.to_i
  header = base64url(JSON.generate(alg: "ES256", kid: key_id, typ: "JWT"))
  payload = base64url(JSON.generate(iss: issuer_id, iat: now, exp: now + 1_200, aud: "appstoreconnect-v1"))
  input = "#{header}.#{payload}"
  der_signature = private_key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(input))
  sequence = OpenSSL::ASN1.decode(der_signature)
  raw_signature = sequence.value.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join
  "#{input}.#{base64url(raw_signature)}"
end

def request(method, path, token, body = nil)
  uri = URI("#{API_ROOT}#{path}")
  request_class = method == :post ? Net::HTTP::Post : Net::HTTP::Get
  req = request_class.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json" if body
  req.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  unless response.is_a?(Net::HTTPSuccess)
    error = JSON.parse(response.body).fetch("errors", []).map { |item| item["detail"] || item["title"] }.join("; ")
    abort("ERROR: Apple API #{method.to_s.upcase} #{path} failed (#{response.code}): #{error}")
  end
  JSON.parse(response.body)
end

def signing_identity_fingerprint
  identity = required_env("APP_IDENTITY")
  output = `security find-identity -v -p codesigning 2>/dev/null`
  matches = output.lines.map do |line|
    match = line.match(/\b([0-9A-F]{40})\b.*"([^"]+)"/)
    next unless match && match[2] == identity
    match[1]
  end.compact
  abort("ERROR: No valid signing identity named #{identity.inspect} is available.") if matches.empty?
  abort("ERROR: Multiple valid signing identities named #{identity.inspect} are available.") if matches.length > 1
  matches.first
end

token = jwt
fingerprint = signing_identity_fingerprint

certificates = request(
  :get,
  "/certificates?filter%5BcertificateType%5D=DEVELOPER_ID_APPLICATION_G2&limit=200",
  token
).fetch("data")
certificate = certificates.find do |item|
  content = item.dig("attributes", "certificateContent")
  content && Digest::SHA1.hexdigest(Base64.decode64(content)).upcase == fingerprint
end
abort("ERROR: Apple has no active Developer ID Application G2 certificate matching #{fingerprint}.") unless certificate

bundle_identifier = required_env("QUOTAKIT_MAC_BUNDLE_ID")
bundle_ids = request(
  :get,
  "/bundleIds?filter%5Bidentifier%5D=#{URI.encode_www_form_component(bundle_identifier)}&limit=10",
  token
).fetch("data")
bundle_id = bundle_ids.find { |item| item.dig("attributes", "identifier") == bundle_identifier }
abort("ERROR: Apple has no registered bundle ID for #{bundle_identifier}.") unless bundle_id

profile_name = "QuotaKit Mac Direct #{fingerprint[0, 8]}"
profiles = request(
  :get,
  "/profiles?filter%5BprofileType%5D=MAC_APP_DIRECT&filter%5Bname%5D=#{URI.encode_www_form_component(profile_name)}&limit=10",
  token
).fetch("data")
profile = profiles.find { |item| item.dig("attributes", "profileState") == "ACTIVE" }

unless profile
  profile = request(
    :post,
    "/profiles",
    token,
    {
      data: {
        type: "profiles",
        attributes: { name: profile_name, profileType: "MAC_APP_DIRECT" },
        relationships: {
          bundleId: { data: { type: "bundleIds", id: bundle_id.fetch("id") } },
          certificates: { data: [{ type: "certificates", id: certificate.fetch("id") }] }
        }
      }
    }
  ).fetch("data")
end

profile_id = profile.fetch("id")
profile = request(:get, "/profiles/#{profile_id}", token).fetch("data")
content = Base64.decode64(profile.dig("attributes", "profileContent").to_s)
abort("ERROR: Apple returned an empty provisioning profile.") if content.empty?

output_path = required_env("QUOTAKIT_MAC_PROFILE_OUTPUT")
FileUtils.mkdir_p(File.dirname(output_path), mode: 0o700)
temporary_path = "#{output_path}.tmp.#{$$}"
File.binwrite(temporary_path, content)
File.chmod(0o600, temporary_path)
File.rename(temporary_path, output_path)

expiration = profile.dig("attributes", "expirationDate")
puts "Installed #{profile_name}"
puts "  Profile: #{output_path}"
puts "  Certificate SHA-1: #{fingerprint}"
puts "  Expires: #{expiration}"
