require 'fileutils'

module Cert
  class Runner
    def launch
      run

      installed = FastlaneCore::CertChecker.installed?(ENV["CER_FILE_PATH"])
      raise "Could not find the newly generated certificate installed" unless installed
      return ENV["CER_FILE_PATH"]
    end

    def run
      FileUtils.mkdir_p(Cert.config[:output_path])

      FastlaneCore::PrintTable.print_values(config: Cert.config, hide_keys: [:output_path], title: "Summary for cert #{Cert::VERSION}")

      Helper.log.info "Starting login with user '#{Cert.config[:username]}'"
      Spaceship.login(Cert.config[:username], nil)
      Spaceship.select_team
      Helper.log.info "Successfully logged in"

      should_create = Cert.config[:force]
      unless should_create
        cert_path = find_existing_cert
        should_create = cert_path.nil?
      end

      return unless should_create

      if create_certificate # no certificate here, creating a new one
        return # success
      else
        raise "Something went wrong when trying to create a new certificate..."
      end
    end

    def find_existing_cert
      certificates.each do |certificate|
        path = store_certificate(certificate)
        private_key_path = File.expand_path(File.join(Cert.config[:output_path], "#{certificate.id}.p12"))

        if FastlaneCore::CertChecker.installed?(path)
          # This certificate is installed on the local machine
          ENV["CER_CERTIFICATE_ID"] = certificate.id
          ENV["CER_FILE_PATH"] = path

          Helper.log.info "Found the certificate #{certificate.id} (#{certificate.name}) which is installed on the local machine. Using this one.".green

          return path
        elsif File.exist?(private_key_path)
          KeychainImporter.import_file(private_key_path)
          KeychainImporter.import_file(path)

          ENV["CER_CERTIFICATE_ID"] = certificate.id
          ENV["CER_FILE_PATH"] = path

          Helper.log.info "Found the cached certificate #{certificate.id} (#{certificate.name}). Using this one.".green

          return path
        else
          Helper.log.info "Certificate #{certificate.id} (#{certificate.name}) can't be found on your local computer"
        end

        File.delete(path) # as apparantly this certificate is pretty useless without a private key
      end

      Helper.log.info "Couldn't find an existing certificate... creating a new one"
      return nil
    end

    # All certificates of this type
    def certificates
      certificate_type.all
    end

    # The kind of certificate we're interested in
    def certificate_type
      cert_type = Spaceship.certificate.production
      cert_type = Spaceship.certificate.development if Cert.config[:development]
      cert_type = Spaceship.certificate.in_house if Spaceship.client.in_house?

      cert_type
    end

    def create_certificate
      # Create a new certificate signing request
      csr, pkey = Spaceship.certificate.create_certificate_signing_request

      # Use the signing request to create a new distribution certificate
      begin
        certificate = certificate_type.create!(csr: csr)
      rescue => ex
        if ex.to_s.include?("You already have a current")
          Helper.log.error "Could not create another certificate, reached the maximum number of available certificates.".red
        end

        raise ex
      end

      # Store all that onto the filesystem

      request_path = File.expand_path(File.join(Cert.config[:output_path], "#{certificate.id}.certSigningRequest"))
      File.write(request_path, csr.to_pem)

      private_key_path = File.expand_path(File.join(Cert.config[:output_path], "#{certificate.id}.p12"))
      File.write(private_key_path, pkey)

      cert_path = store_certificate(certificate)

      # Import all the things into the Keychain
      KeychainImporter.import_file(private_key_path)
      KeychainImporter.import_file(cert_path)

      # Environment variables for the fastlane action
      ENV["CER_CERTIFICATE_ID"] = certificate.id
      ENV["CER_FILE_PATH"] = cert_path

      Helper.log.info "Successfully generated #{certificate.id} which was imported to the local machine.".green

      return cert_path
    end

    def store_certificate(certificate)
      path = File.expand_path(File.join(Cert.config[:output_path], "#{certificate.id}.cer"))
      raw_data = certificate.download_raw
      File.write(path, raw_data, encoding: "ASCII-8BIT")
      return path
    end
  end
end
