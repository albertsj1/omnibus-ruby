require 'spec_helper'

module Omnibus
  describe GitCache do
    before do
      allow(IO).to receive(:read).and_call_original
    end

    let(:install_dir) { '/opt/chef' }

    let(:project) do
      allow(IO).to receive(:read)
        .with('/path/to/demo.rb')
        .and_return <<-EOH.gsub(/^ {10}/, '')
          name 'demo'
          install_dir '/opt/demo'

          build_version '1.0.0'

          maintainer 'Chef Software, Inc'
          homepage 'http://getchef.com'

          dependency 'preparation'
          dependency 'snoopy'
          dependency 'zlib'
        EOH

      Project.load('/path/to/demo.rb')
    end

    let(:zlib_config) { File.join(RSpec::SPEC_DATA, 'software', 'zlib.rb') }

    let(:zlib) do
      software = Software.new(project, {}, zlib_config)
      software.name('zlib')
      software.default_version('1.7.2')
      software
    end

    let(:snoopy) do
      software = Software.new(project, {}, 'snoopy.rb')
      software.name('snoopy')
      software.default_version('1.0.0')
      software
    end

    let(:preparation) do
      software = Software.new(project, {}, 'preparation.rb')
      software.name('preparation')
      software.default_version('1.0.0')
      software
    end

    let(:cache_path) { File.join("/var/cache/omnibus/cache/git_cache", install_dir) }

    let(:ipc) do
      project.library.component_added(preparation)
      project.library.component_added(snoopy)
      project.library.component_added(zlib)
      described_class.new(install_dir, zlib)
    end

    describe '#cache_path' do
      it 'returns the install path appended to the install_cache path' do
        expect(ipc.cache_path).to eq('/var/cache/omnibus/cache/git_cache/opt/chef')
      end
    end

    describe '#cache_path_exists?' do
      it 'checks for existence' do
        expect(File).to receive(:directory?).with(ipc.cache_path)
        ipc.cache_path_exists?
      end
    end

    describe '#tag' do
      it 'returns the correct tag' do
        expect(ipc.tag).to eql('zlib-329d861e3928a74938f1ff9ff2672ea4e1c0b6ac3b7f32e66fd61064f516f751')
      end

      describe 'with no deps' do
        let(:ipc) do
          described_class.new(install_dir, zlib)
        end

        it 'returns the correct tag' do
          expect(ipc.tag).to eql('zlib-4093b06ca5b22654b650a207736136964a1e8a362548a058702adbf501955189')
        end
      end
    end

    describe '#create_cache_path' do
      it 'runs git init if the cache path does not exist' do
        allow(File).to receive(:directory?)
          .with(ipc.cache_path)
          .and_return(false)
        allow(File).to receive(:directory?)
          .with(File.dirname(ipc.cache_path))
          .and_return(false)
        expect(FileUtils).to receive(:mkdir_p)
          .with(File.dirname(ipc.cache_path))
        expect(ipc).to receive(:shellout!)
          .with("git --git-dir=#{cache_path} init -q")
        ipc.create_cache_path
      end

      it 'does not run git init if the cache path exists' do
        allow(File).to receive(:directory?)
          .with(ipc.cache_path)
          .and_return(true)
        allow(File).to receive(:directory?)
          .with(File.dirname(ipc.cache_path))
          .and_return(true)
        expect(ipc).to_not receive(:shellout!)
          .with("git --git-dir=#{cache_path} init -q")
        ipc.create_cache_path
      end
    end

    describe '#incremental' do
      before(:each) do
        allow(ipc).to receive(:shellout!)
        allow(ipc).to receive(:create_cache_path)
      end

      it 'creates the cache path' do
        expect(ipc).to receive(:create_cache_path)
        ipc.incremental
      end

      it 'adds all the changes to git removing git directories' do
        expect(ipc).to receive(:remove_git_dirs)
        expect(ipc).to receive(:shellout!)
          .with("git --git-dir=#{cache_path} --work-tree=#{install_dir} add -A -f")
        ipc.incremental
      end

      it 'commits the backup for the software' do
        expect(ipc).to receive(:shellout!)
          .with(%Q(git --git-dir=#{cache_path} --work-tree=#{install_dir} commit -q -m "Backup of #{ipc.tag}"))
        ipc.incremental
      end

      it 'tags the software backup' do
        expect(ipc).to receive(:shellout!)
          .with(%Q(git --git-dir=#{cache_path} --work-tree=#{install_dir} tag -f "#{ipc.tag}"))
        ipc.incremental
      end
    end

    describe '#remove_git_dirs' do
      let(:git_files) { ['git/HEAD', 'git/description', 'git/hooks', 'git/info', 'git/objects', 'git/refs' ] }
      it 'removes bare git directories' do
        allow(Dir).to receive(:glob).and_return(['git/config'])
        git_files.each do |git_file|
          expect(File).to receive(:exist?).with(git_file).and_return(true)
        end
        allow(File).to receive(:dirname).and_return('git')
        expect(FileUtils).to receive(:rm_rf).with('git')

        ipc.remove_git_dirs
      end
      
      it 'does ignores non git directories' do
        allow(Dir).to receive(:glob).and_return(['not_git/config'])
        expect(File).to receive(:exist?).with('not_git/HEAD').and_return(false)
        allow(File).to receive(:dirname).and_return('not_git')
        expect(FileUtils).not_to receive(:rm_rf).with('not_git')

        ipc.remove_git_dirs
      end
    end

    describe '#restore' do
      let(:git_tag_output) { "#{ipc.tag}\n" }

      let(:tag_cmd) do
        cmd_double = double(Mixlib::ShellOut)
        allow(cmd_double).to receive(:stdout).and_return(git_tag_output)
        allow(cmd_double).to receive(:error!).and_return(cmd_double)
        cmd_double
      end

      before(:each) do
        allow(ipc).to receive(:shellout)
          .with(%Q(git --git-dir=#{cache_path} --work-tree=#{install_dir} tag -l "#{ipc.tag}"))
          .and_return(tag_cmd)
        allow(ipc).to receive(:shellout!)
          .with(%Q(git --git-dir=#{cache_path} --work-tree=#{install_dir} checkout -f "#{ipc.tag}"))
        allow(ipc).to receive(:create_cache_path)
      end

      it 'creates the cache path' do
        expect(ipc).to receive(:create_cache_path)
        ipc.restore
      end

      it 'checks for a tag with the software and version, and if it finds it, checks it out' do
        expect(ipc).to receive(:shellout)
          .with(%Q(git --git-dir=#{cache_path} --work-tree=#{install_dir} tag -l "#{ipc.tag}"))
          .and_return(tag_cmd)
        expect(ipc).to receive(:shellout!)
          .with(%Q(git --git-dir=#{cache_path} --work-tree=#{install_dir} checkout -f "#{ipc.tag}"))
        ipc.restore
      end

      describe 'if the tag does not exist' do
        let(:git_tag_output) { "\n" }

        it 'does nothing' do
          expect(ipc).to receive(:shellout)
            .with(%Q(git --git-dir=#{cache_path} --work-tree=#{install_dir} tag -l "#{ipc.tag}"))
            .and_return(tag_cmd)
          expect(ipc).to_not receive(:shellout!)
            .with(%Q(git --git-dir=#{cache_path} --work-tree=#{install_dir} checkout -f "#{ipc.tag}"))
          ipc.restore
        end
      end
    end
  end
end
