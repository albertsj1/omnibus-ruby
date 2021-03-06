require 'spec_helper'

module Omnibus
  describe Library do
    #
    # Helper method for generating a fake software definition.
    #
    def generate_software(name, version, dependencies = [])
      software = Software.new(project, {}, "#{name}.rb")
      software.name(name.to_s)
      software.version(version)

      dependencies.each do |dependency|
        software.dependency(dependency)
      end

      software
    end

    let(:project) { Project.load(project_path('chefdk')) }
    let(:library) { Library.new(project) }

    let(:bundler)     { generate_software('bundler', '1.5.4') }
    let(:curl)        { generate_software('curl', '1.5.4', %w(openssl zlib)) }
    let(:chef)        { generate_software('chef', '1.0.0', %w(bundler ohai ruby)) }
    let(:erchef)      { generate_software('erchef', '4b19a96d57bff9bbf4764d7323b92a0944009b9e', %w(curl erlang rsync)) }
    let(:erlang)      { generate_software('erlang', 'R15B03-1', %w(openssl zlib)) }
    let(:libgcc)      { generate_software('libgcc', '0.0.0') }
    let(:ncurses)     { generate_software('ncurses', '5.9', %w(libgcc)) }
    let(:ohai)        { generate_software('ohai', 'master', %w(ruby rubygems yajl)) }
    let(:openssl)     { generate_software('openssl', '1.0.1g', %w(zlib)) }
    let(:postgresql)  { generate_software('postgresql', '9.2.8', %w(zlib openssl)) }
    let(:preparation) { generate_software('preparation', '1.0.0') }
    let(:rsync)       { generate_software('rsync', '3.0.9') }
    let(:ruby)        { generate_software('ruby', '1.9.3-p481', %w(zlib ncurses)) }
    let(:rubygems)    { generate_software('rubygems', '1.8.24', %w(ruby)) }
    let(:skitch)      { generate_software('skitch', '4.4.1', %w(postgresql)) }
    let(:yajl)        { generate_software('yajl', '1.1.0', %w(rubygems)) }
    let(:zlib)        { generate_software('zlib', '1.2.6', %w(libgcc)) }

    describe '#component_added' do
      it 'adds the software to the component list' do
        library.component_added(erchef)
        expect(library.components).to eql([erchef])
      end

      it 'does not add a component more than once' do
        library.component_added(erchef)
        library.component_added(erchef)
        expect(library.components).to eql([erchef])
      end
    end

    describe '#build_order' do
      let(:project) do
        allow(IO).to receive(:read)
          .with('/chef-server.rb')
          .and_return <<-EOH.gsub(/^ {12}/, '')
            name          'chef-server'
            maintainer    'Chef Software, Inc'
            homepage      'http://getchef.com'
            build_version '1.0.0'

            install_dir '/opt/chef-server'

            dependency 'preparation'
            dependency 'erchef'
            dependency 'postgresql'
            dependency 'chef'
          EOH

        Project.load('/chef-server.rb')
      end

      let(:library) do
        library = Library.new(project)
        library.component_added(preparation)
        library.component_added(erlang)
        library.component_added(postgresql) # as a skitch trans dep
        library.component_added(skitch)
        library.component_added(erchef)
        library.component_added(ruby)
        library.component_added(chef)
        library
      end

      it 'returns an array of software descriptions, with all top level deps first' do
        expect(library.build_order).to eq([
          preparation,
          erlang,
          postgresql,
          skitch,
          ruby,
          erchef,
          chef,
        ])
      end

      context 'with a complex dep tree' do
        let(:chefdk) { generate_software('chefdk', '1.0.0.alpha', %w(bundler ruby)) }

        let(:project) do
          allow(IO).to receive(:read)
            .with('/chefdk.rb')
            .and_return <<-EOH.gsub(/^ {12}/, '')
              name          'chef-dk'
              maintainer    'Chef Software, Inc'
              homepage      'http://getchef.com'
              build_version '1.0.0'

              install_dir '/opt/chefdk'

              dependency 'preparation'
              dependency 'erchef'
              dependency 'postgresql'
              dependency 'ruby'
              dependency 'chef'
              dependency 'chefdk'
            EOH

          Project.load('/chefdk.rb')
        end

        let(:library) do
          # This is the LOAD ORDER
          library = Library.new(project)
          library.component_added(preparation) # via project
          library.component_added(erlang) # via erchef
          library.component_added(postgresql) # via skitch
          library.component_added(skitch) # via erchef
          library.component_added(erchef) # erchef
          library.component_added(ruby) # via project
          library.component_added(bundler) # via chef
          library.component_added(ohai) # via chef
          library.component_added(chef) # via project
          library.component_added(chefdk) # via project
          library
        end

        it 'returns an array of software descriptions, with all top level deps first, assuming they are not themselves transitive deps' do
          expect(library.build_order).to eql(
            [
              preparation, # first
              erlang, # via erchef project
              postgresql, # via skitch transitive
              skitch, # via erchef project
              ruby, # via bundler transitive
              bundler, # via chef
              ohai, # via chef
              erchef, # project dep
              chef, # project dep
              chefdk, # project dep
             ])
        end
      end

      context 'with real data' do
        before do
          Config.project_root(complicated_path)

          # Ohai stuff
          stub_const('File::ALT_SEPARATOR', '\\')
          stub_ohai(platform: 'windows', version: '2012')

          Omnibus.process_dsl_files
        end

        let(:chefdk_windows) do
          Omnibus.projects.find { |p| p.name.to_s == 'chefdk-windows' }
        end

        it 'has the right build order for chefdk-windows on windows' do
          names = chefdk_windows.library.build_order.map { |m| m.name.to_s }
          expect(names).to eql([
            'preparation', # via project dep
            'ruby-windows', # via libyaml-windows trans dep
            'libyaml-windows', # via ruby-windows trans
            'ruby-windows-devkit', # via trans dep from chef-windows
            'bundler', # via trans dep from chef-windows
            'cacerts', # via chef-windows
            'chef-windows', # via transitive dep from chefdk
            'nokogiri', # via test-kitchen
            'test-kitchen', # via chefdk
            'appbundler', # via chefdk
            'berkshelf', # via chefdk
            'chef-vault', # via chefdk
            'chefdk', # via project dep
            'chef-client-msi', # via top level dep
          ])
        end
      end
    end
  end
end
