require "support/api_umbrella_test_helpers/process"

module ApiUmbrellaTestHelpers
  module Downloads
    DOWNLOADS_ROOT = File.join(ApiUmbrellaTestHelpers::Process::TEST_RUN_ROOT, "capybara-downloads")

    def setup
      super

      if(self.class.run_order == :parallel)
        raise "`ApiUmbrellaTestHelpers::Downloads` cannot be called with `parallelize_me!` in the same class. Since downloads are tracked globally, it cannot be used with parallel tests."
      end

      clear_downloads
    end

    def teardown
      clear_downloads
      super
    end

    def download_paths
      Dir[File.join(DOWNLOADS_ROOT, "*")]
    end

    def download_path
      paths = wait_for_download
      paths.first
    end

    def download_file
      File.open(download_path)
    end

    def wait_for_download
      paths = []
      Timeout.timeout(10) do
        until downloaded?(paths)
          sleep 0.1
          paths = download_paths
        end
      end
      paths
    end

    def downloaded?(paths)
      paths.any? && !downloading?(paths)
    end

    def downloading?(paths)
      paths.grep(/\.(part|crdownload)$/).any?
    end

    def clear_downloads
      FileUtils.rm_rf(DOWNLOADS_ROOT)
      FileUtils.mkdir_p(DOWNLOADS_ROOT)
    end
  end
end
